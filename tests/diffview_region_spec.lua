-- Integration: native Diffview controls inside a live editor/shell/chat layout.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
for _, plugin in ipairs({ "plenary.nvim", "diffview.nvim", "mini.nvim" }) do
	vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.cmd("runtime plugin/diffview.lua")
vim.o.hidden, vim.o.swapfile = true, false
local api = vim.api
local cwd, root = vim.fn.getcwd(), vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local function git(...)
	local args = {
		"git",
		"-C",
		root,
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.test",
		"-c",
		"commit.gpgsign=false",
		"-c",
		"core.hooksPath=/dev/null",
	}
	vim.list_extend(args, { ... })
	local result = vim.system(args, { text = true }):wait()
	assert(result.code == 0, result.stderr)
end
git("init")
vim.fn.writefile({ "one", "before", "three" }, root .. "/one.txt")
vim.fn.writefile({ "before" }, root .. "/two.txt")
git("add", ".")
git("commit", "-m", "baseline")
vim.fn.writefile({ "one", "after", "three" }, root .. "/one.txt")
vim.fn.writefile({ "after" }, root .. "/two.txt")
vim.cmd.cd(root)
vim.cmd.edit(root .. "/one.txt")
api.nvim_win_set_cursor(0, { 3, 0 })
local editor_buf = api.nvim_get_current_buf()
local original_actions = { ga = 0, gs = 0 }
for _, key in ipairs({ "ga", "gs" }) do
	vim.keymap.set("n", key, function()
		original_actions[key] = original_actions[key] + 1
	end, { buffer = editor_buf, desc = "Original " .. key })
end
vim.cmd("botright vnew")
local chat = api.nvim_get_current_win()
local chat_job = vim.fn.jobstart({ "cat" }, { term = true })
vim.cmd("wincmd h")
vim.cmd("belowright new")
local shell = api.nvim_get_current_win()
local shell_job = vim.fn.jobstart({ "cat" }, { term = true })
vim.cmd("wincmd k")
local function geometry(win)
	return {
		api.nvim_win_get_position(win),
		api.nvim_win_get_width(win),
		api.nvim_win_get_height(win),
		api.nvim_win_get_buf(win),
	}
end
local companions = { [shell] = geometry(shell), [chat] = geometry(chat) }
local function preserved()
	for win, expected in pairs(companions) do
		assert(api.nvim_win_is_valid(win), "companion window was closed")
		assert(
			vim.deep_equal(geometry(win), expected),
			"companion geometry/buffer changed: " .. vim.inspect(geometry(win)) .. " expected " .. vim.inspect(expected)
		)
	end
	assert(vim.fn.jobwait({ shell_job, chat_job }, 0)[1] == -1, "shell process stopped")
	assert(vim.fn.jobwait({ shell_job, chat_job }, 0)[2] == -1, "agent process stopped")
end
package.loaded["config.agent_session"] = {
	capture = function()
		return { project = root, sessionID = "region-test", harness = "opencode" }
	end,
}
dofile(cwd .. "/lua/plugins/git/diffview.lua").config()
local review = require("config.opencode_review")
local tab = api.nvim_get_current_tabpage()
assert(review.start("HEAD", root))
assert(api.nvim_get_current_tabpage() == tab, "agent review escaped the editor region into a new tab")
local lib = require("diffview.lib")
local view = lib.get_current_view()
local function settled()
	local pending = view:set_file_in_flight()
	return view.ready and view.cur_entry and not view.panel.updating and (not pending or pending:is_done())
end
assert(vim.wait(5000, settled, 20), "embedded review did not load")
preserved()
assert(view.panel:is_open(), "native file sidebar is missing")
local region = require("config.diffview_region")
local pane = require("config.window_zoom")
for _, source in ipairs({ view.panel.winid, view.cur_layout.windows[1].id, view.cur_layout.windows[2].id }) do
	api.nvim_set_current_win(source)
	assert(pane.toggle())
	assert(api.nvim_win_get_config(0).relative ~= "", "pane zoom did not open a float")
	assert(api.nvim_get_current_buf() == api.nvim_win_get_buf(source), "pane zoom selected the wrong buffer")
	assert(lib.get_current_view() == view, "pane zoom lost its Diffview controls")
	assert(view.tabpage == tab and not view.region.zoom, "pane zoom changed workspace state")
	assert(pane.toggle())
	assert(api.nvim_get_current_win() == source, "pane zoom did not restore focus")
	preserved()
end
view.panel.updating = true
vim.schedule(function()
	view.panel.updating = false
end)
for _, source in ipairs({ view.panel.winid, view.cur_layout.windows[1].id, view.cur_layout.windows[2].id }) do
	api.nvim_set_current_win(source)
	local windows = api.nvim_tabpage_list_wins(tab)
	assert(region.toggle_zoom(), "Diffview zoom was not handled")
	assert(view.tabpage ~= tab and api.nvim_get_current_tabpage() == view.tabpage, "review did not zoom collectively")
	for _, win in ipairs(windows) do
		if view.region.windows[win] then
			assert(api.nvim_win_get_tabpage(win) == view.tabpage, "a review window was left behind")
		end
	end
	assert(api.nvim_get_current_win() == source, "zoom lost the focused review window")
	assert(pane.toggle())
	local floating = api.nvim_get_current_win()
	assert(lib.get_current_view() == view, "nested pane zoom lost the review")
	assert(pane.toggle())
	assert(view.region.zoom, "restoring pane zoom also restored the workspace")
	assert(not api.nvim_win_is_valid(floating), "pane zoom leaked its float")
	local zoom_tab = view.tabpage
	api.nvim_set_current_tabpage(tab)
	api.nvim_set_current_win(chat)
	assert(review.current(root), "zoom lost the review context in its host agent panel")
	api.nvim_set_current_tabpage(zoom_tab)
	api.nvim_set_current_win(source)
	preserved()
	assert(pane.toggle())
	floating = api.nvim_get_current_win()
	assert(region.toggle_zoom(), "Diffview unzoom was not handled")
	assert(not api.nvim_win_is_valid(floating), "workspace restore left an individual pane zoomed")
	assert(view.tabpage == tab and #api.nvim_list_tabpages() == 1, "unzoom leaked a tab")
	assert(api.nvim_get_current_win() == source, "unzoom lost focus")
	preserved()
end
api.nvim_set_current_win(chat)
assert(not region.toggle_zoom(), "agent panel inherited collective zoom")
assert(lib.get_current_view() == nil, "agent panel inherited Diffview controls")
assert(review.current(root), "background review lost its pinned context in the agent panel")
local background_refresh = false
view:update_files(nil, function()
	background_refresh = true
end)
assert(
	vim.wait(5000, function()
		return background_refresh and settled()
	end, 20),
	"background refresh stalled"
)
assert(api.nvim_get_current_win() == chat, "background refresh stole agent focus")
preserved()
api.nvim_set_current_win(view.cur_layout:get_main_win().id)
view:next_file(true)
assert(vim.wait(5000, settled, 20), "file navigation did not settle")
preserved()
for _ = 1, 3 do
	local previous = view.cur_layout
	require("diffview.actions").cycle_layout()
	assert(
		vim.wait(5000, function()
			return view.cur_layout ~= previous and settled()
		end, 20),
		"layout cycling stalled"
	)
	preserved()
end
view.panel:close()
view.panel:open()
preserved()
local refreshed = false
view:update_files(nil, function()
	refreshed = true
end)
assert(
	vim.wait(5000, function()
		return refreshed and settled()
	end, 20),
	"refresh stalled"
)
preserved()
-- A lost diff side must recover within the region, never around window 1.
api.nvim_win_close(view.cur_layout.windows[1].id, true)
view:ensure_layout()
assert(
	vim.wait(5000, function()
		return settled() and view.cur_layout:validate().valid
	end, 20),
	"layout recovery stalled"
)
preserved()
view.panel:focus()
assert(region.toggle_zoom())
local zoom_tab = view.tabpage
local previous_layout = view.cur_layout
require("diffview.actions").cycle_layout()
assert(
	vim.wait(5000, function()
		return view.cur_layout ~= previous_layout and settled()
	end, 20),
	"zoomed layout cycling stalled"
)
view:next_file(true)
assert(vim.wait(5000, settled, 20), "zoomed navigation stalled")
view.panel:close()
view.panel:open()
local zoom_refreshed = false
view:update_files(nil, function()
	zoom_refreshed = true
end)
assert(
	vim.wait(5000, function()
		return zoom_refreshed and settled()
	end, 20),
	"zoomed refresh stalled"
)
preserved()
view.panel:focus()
assert(region.toggle_zoom(), "changed zoom layout did not restore")
assert(view.tabpage == tab and not api.nvim_tabpage_is_valid(zoom_tab), "changed layout leaked its zoom tab")
preserved()
assert(region.toggle_zoom())
zoom_tab = view.tabpage
view.panel.updating = true -- Closing must restore even if a refresh is in flight.
assert(pane.toggle())
local closing_float = api.nvim_get_current_win()
vim.cmd("DiffviewClose")
assert(not api.nvim_win_is_valid(closing_float), "closing Diffview leaked a pane zoom")
assert(not api.nvim_tabpage_is_valid(zoom_tab), "closing zoomed review leaked its temporary tab")
assert(api.nvim_get_current_tabpage() == tab, "closing review closed its host tab")
assert(api.nvim_get_current_buf() == editor_buf, "closing review did not restore the editor buffer")
assert(api.nvim_win_get_cursor(0)[1] == 3, "closing review did not restore the cursor")
assert(vim.fn.maparg("ga", "n", false, true).desc == "Original ga", "closing review did not restore ga")
assert(vim.fn.maparg("gs", "n", false, true).desc == "Original gs", "closing review did not restore gs")
preserved()
assert(lib.get_current_view() == nil, "closed region is still registered")
-- Narrow editor regions retain the full native UI and can be opened from chat.
api.nvim_win_set_width(chat, 49)
for win in pairs(companions) do
	companions[win] = geometry(win)
end
api.nvim_set_current_win(chat)
assert(review.start(nil, root), "review could not reopen from the agent panel")
view = lib.get_current_view()
assert(view and view.region, "agent-panel review did not select the editor region")
assert(vim.wait(5000, settled, 20), "narrow review did not load")
preserved()
assert(review.start(nil, root), "existing embedded review could not be reused")
assert(lib.get_current_view() == view, "reuse created a duplicate embedded review")
preserved()
view.panel:focus()
vim.api.nvim_feedkeys("q", "xt", false)
assert(
	vim.wait(2000, function()
		return not lib.has_view(view)
	end, 20),
	"q did not close the embedded view"
)
preserved()
-- Closing the temporary tab through Neovim also restores the host editor.
assert(review.start(nil, root))
view = lib.get_current_view()
assert(vim.wait(5000, settled, 20))
assert(region.toggle_zoom())
vim.cmd("tabclose")
assert(
	vim.wait(2000, function()
		return not lib.has_view(view)
	end, 20),
	"closed zoom tab left a registered review"
)
assert(api.nvim_get_current_buf() == editor_buf, "closing the zoom tab lost the host editor")
preserved()
local idle = require("config.diffview_idle")
assert(idle.open_diff(root, "HEAD").status == "opened", "compatibility handoff did not open")
view = lib.get_current_view()
assert(view and view.region, "compatibility handoff escaped the region")
assert(vim.wait(5000, settled, 20), "compatibility review did not load")
preserved()
vim.cmd("DiffviewClose")
local broken = assert(lib.diffview_open({ "-C=" .. root, "HEAD" }))
broken.post_open = function()
	error("injected opening failure")
end
local opened, failure = pcall(require("config.diffview_region").open, broken)
assert(not opened, "opening failure was swallowed")
assert(tostring(failure):find("injected opening failure", 1, true), tostring(failure))
assert(not lib.has_view(broken), "failed opening left a registered region")
assert(api.nvim_get_current_buf() == editor_buf, "failed opening did not restore the editor")
preserved()
vim.cmd("DiffviewOpen HEAD")
assert(api.nvim_get_current_tabpage() ~= tab, "standalone DiffviewOpen must retain its own tab")
vim.cmd("DiffviewClose")
-- Shortcut lifecycle is independent of the zoom stress sequence above.
local annotations = require("config.annotations")
annotations.setup()
assert(review.start(nil, root))
view = lib.get_current_view()
assert(vim.wait(5000, settled, 20), "shortcut review did not load")
local annotation_calls = {}
local original_list, original_send = annotations.list, annotations.send_drafts
annotations.list = function(directory)
	annotation_calls[#annotation_calls + 1] = { "list", directory }
end
annotations.send_drafts = function(directory)
	annotation_calls[#annotation_calls + 1] = { "send", directory }
end
vim.cmd.cd(cwd)
for _, source in ipairs({ view.panel.winid, view.cur_layout.windows[1].id, view.cur_layout.windows[2].id }) do
	api.nvim_set_current_win(source)
	assert(vim.fn.maparg("ga", "n", false, true).desc == "Review annotations", "missing review-local ga")
	assert(vim.fn.maparg("gs", "n", false, true).desc == "Send draft review round", "missing review-local gs")
	vim.api.nvim_feedkeys("gags", "xt", false)
end
assert(
	vim.deep_equal(annotation_calls, {
		{ "list", root },
		{ "send", root },
		{ "list", root },
		{ "send", root },
		{ "list", root },
		{ "send", root },
	}),
	"review shortcuts must use the current view's repository in every pane"
)
api.nvim_set_current_win(view.panel.winid)
assert(vim.fn.maparg("s", "n", false, true).desc == "Stage/unstage file", "s must keep staging")
assert(vim.fn.maparg("S", "n", false, true).desc == "Stage all", "S must keep staging all")
assert(vim.fn.maparg("C", "n") ~= "", "C must keep clearing reviewed marks")
assert(vim.fn.maparg("gA", "n", false, true).callback == annotations.add_current, "gA must keep immediate comments")
assert(vim.fn.maparg("<leader>ans", "n") ~= "", "the existing send alias must remain")
local source = view.cur_layout.windows[2].id
api.nvim_set_current_win(source)
local review_tab = api.nvim_get_current_tabpage()
vim.cmd("tabnew")
api.nvim_win_set_buf(0, editor_buf)
assert(vim.fn.maparg("ga", "n", false, true).desc == "Original ga", "ga leaked into an ordinary tab")
assert(vim.fn.maparg("gs", "n", false, true).desc == "Original gs", "gs leaked into an ordinary tab")
vim.api.nvim_feedkeys("gags", "xt", false)
assert(original_actions.ga == 1 and original_actions.gs == 1, "ordinary editing shortcuts were not restored")
assert(#annotation_calls == 6, "ordinary editing dispatched a review action")
vim.cmd("tabclose")
assert(api.nvim_get_current_tabpage() == review_tab, "test did not return to its review")
api.nvim_set_current_win(source)
assert(vim.wait(5000, settled, 20), "review shortcuts did not reattach after tab switching")
assert(vim.fn.maparg("gs", "n", false, true).desc == "Send draft review round", "gs did not reattach")
annotations.list, annotations.send_drafts = original_list, original_send
vim.cmd.cd(root)
vim.cmd("DiffviewClose")
assert(vim.fn.maparg("ga", "n", false, true).desc == "Original ga", "closing shortcut review did not restore ga")
assert(vim.fn.maparg("gs", "n", false, true).desc == "Original gs", "closing shortcut review did not restore gs")
vim.wait(200, function()
	return false
end)
vim.fn.jobstop(shell_job)
vim.fn.jobstop(chat_job)
require("config.hotreload").unwatch_directory(root)
vim.cmd.cd(cwd)
vim.fn.delete(root, "rf")
print("PASS embedded Diffview: navigation, native controls, layouts, refresh, close and live companion sessions")

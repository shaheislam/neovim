-- Exercise commit cycling in a real Diffview with live shell and chat companions.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
for _, plugin in ipairs({ "plenary.nvim", "diffview.nvim", "mini.nvim" }) do
	vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.shell = "/bin/sh"
vim.env.SHELL = "/bin/sh"
for _, key in ipairs({ "TMUX", "TMUX_PANE", "NVIM", "REX_SESSION", "REX_BLOCK", "REX_CLIENT", "REX_SERVER" }) do
	vim.env[key] = nil
end
vim.o.hidden, vim.o.swapfile = true, false
vim.cmd("runtime plugin/diffview.lua")
local api = vim.api
local cwd, root = vim.fn.getcwd(), vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local function git(...)
	local args = { "git", "-C", root, "-c", "user.name=Test", "-c", "user.email=test@example.test",
		"-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" }
	vim.list_extend(args, { ... })
	local result = vim.system(args, { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
git("init")
for i = 1, 3 do
	vim.fn.writefile({ "version " .. i }, root .. "/one.txt")
	git("add", "one.txt")
	git("commit", "-m", "version " .. i)
end
vim.cmd.cd(root)
vim.cmd.edit(root .. "/one.txt")
package.loaded["config.agent_session"] = {
	capture = function() return { project = root, sessionID = "footer-test", harness = "opencode" } end,
}
local workflow = require("git.workflow")
workflow.setup()
local editor = api.nvim_get_current_win()
vim.cmd("botright vnew")
local chat = api.nvim_get_current_win()
local chat_job = vim.fn.jobstart({ "cat" }, { term = true })
api.nvim_set_current_win(editor)
vim.cmd("belowright new")
local shell = api.nvim_get_current_win()
local shell_job = vim.fn.jobstart({ "cat" }, { term = true })
api.nvim_set_current_win(editor)
vim.o.columns, vim.o.lines = 140, 45
vim.cmd("redraw")
dofile(cwd .. "/lua/plugins/git/diffview.lua").config()
assert(require("config.opencode_review").start("HEAD~1", root))
local lib = require("diffview.lib")
local view = assert(lib.get_current_view())
local function settled()
	local pending = view:set_file_in_flight()
	return view.ready and view.cur_entry and not view.panel.updating and (not pending or pending:is_done())
end
assert(vim.wait(5000, settled, 20), "Diffview did not settle")
local function geometry(win)
	return { api.nvim_win_get_position(win), api.nvim_win_get_width(win), api.nvim_win_get_height(win) }
end
local companions = { [chat] = geometry(chat), [shell] = geometry(shell) }
local function footer()
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_buf_get_name(api.nvim_win_get_buf(win)):match("Commit Info$") then return win end
	end
	error("commit info is missing")
end
local function scoped()
	vim.cmd("redraw")
	local top, left, bottom, right = math.huge, math.huge, 0, 0
	for win in pairs(view.region.windows) do
		if api.nvim_win_is_valid(win) then
			local pos = api.nvim_win_get_position(win)
			top, left = math.min(top, pos[1]), math.min(left, pos[2])
			bottom = math.max(bottom, pos[1] + api.nvim_win_get_height(win))
			right = math.max(right, pos[2] + api.nvim_win_get_width(win))
		end
	end
	local win = footer()
	local pos = api.nvim_win_get_position(win)
	assert(pos[1] >= top and pos[2] >= left, "footer escaped above/left of Diffview")
	assert(pos[2] + api.nvim_win_get_width(win) + 2 <= right, "footer covers chat")
	assert(pos[1] + api.nvim_win_get_height(win) + 2 <= bottom, "footer covers shell")
	for companion, expected in pairs(companions) do
		assert(vim.deep_equal(geometry(companion), expected), "footer resized a companion")
	end
end
local function cycle(key)
	local refreshed = false
	view.emitter:once("files_updated", function() refreshed = true end)
	vim.fn.maparg(key, "n", false, true).callback()
	assert(vim.wait(5000, function() return refreshed and settled() end, 20), "commit cycling stalled")
end
cycle("[R")
scoped()
-- Commit cycling reuses the float without changing the focused diff window.
local info = footer()
for _, key in ipairs({ "[R", "]R" }) do
	api.nvim_set_current_win(view.cur_layout:get_main_win().id)
	local focused = api.nvim_get_current_win()
	local previous_sha = workflow.commit_cycle_state.to_sha
	cycle(key)
	assert(workflow.commit_cycle_state.to_sha ~= previous_sha, "commit did not change")
	assert(footer() == info, "cycling replaced the float")
	assert(api.nvim_get_current_win() == focused, "footer stole focus")
	scoped()
end
for _ = 1, 3 do
	local previous = view.cur_layout
	require("diffview.actions").cycle_layout()
	assert(vim.wait(5000, function() return view.cur_layout ~= previous and settled() end, 20), "layout cycling stalled")
	workflow.reposition_commit_info_window()
	scoped()
end
-- Reposition while focus is outside Diffview must retain the owning region.
api.nvim_set_current_win(chat)
api.nvim_win_set_width(chat, 50)
for win in pairs(companions) do companions[win] = geometry(win) end
api.nvim_exec_autocmds("WinResized", { group = "GitCommitInfoLayout" })
scoped()
workflow.close_commit_info_window()
assert(not api.nvim_win_is_valid(info), "footer was not closed")
api.nvim_set_current_win(view.cur_layout:get_main_win().id)
vim.cmd("DiffviewClose")
-- Standalone commit previews retain their editor-wide footer.
workflow.show_single_commit_info(git("rev-parse", "HEAD"))
assert(api.nvim_win_get_width(footer()) == vim.o.columns - 2, "standalone preview lost its width")
workflow.close_commit_info_window()
assert(vim.fn.jobwait({ shell_job, chat_job }, 0)[1] == -1, "shell process stopped")
assert(vim.fn.jobwait({ shell_job, chat_job }, 0)[2] == -1, "chat process stopped")
vim.fn.jobstop(shell_job)
vim.fn.jobstop(chat_job)
require("config.hotreload").unwatch_directory(root)
vim.cmd.cd(cwd)
vim.fn.delete(root, "rf")
print("PASS commit footer: region bounds, cycling, resize, focus and standalone preview")

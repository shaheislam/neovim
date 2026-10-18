-- Ordinary Diffview opens auto-submit only to their captured agent session.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
for _, plugin in ipairs({ "plenary.nvim", "diffview.nvim" }) do
	vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.cmd("runtime plugin/diffview.lua")
vim.o.hidden, vim.o.swapfile = true, false
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
	return vim.trim(result.stdout)
end
git("init")
vim.fn.writefile({ ".tmp/" }, root .. "/.gitignore")
vim.fn.writefile({ "first", "before", "last" }, root .. "/example.txt")
git("add", ".")
git("commit", "-m", "baseline")
local before = git("rev-parse", "HEAD")
vim.fn.writefile({ "first", "committed", "last" }, root .. "/example.txt")
git("commit", "-am", "next")
local after = git("rev-parse", "HEAD")
vim.fn.writefile({ "first", "staged", "last" }, root .. "/example.txt")
git("add", "example.txt")
vim.fn.writefile({ "first", "working", "last" }, root .. "/example.txt")
vim.cmd.cd(root)
local owner, sent, notices = nil, {}, {}
package.loaded["config.agent_session"] = {
	capture = function(directory)
		assert(directory == root)
		return owner and vim.deepcopy(owner)
	end,
	resolve = function(provenance)
		return vim.deep_equal(provenance, owner) and { directory = root, sessionID = owner.sessionID } or nil
	end,
	submit = function(provenance, prompt, callback)
		sent[#sent + 1] = { provenance = vim.deepcopy(provenance), prompt = prompt }
		callback("submitted")
		return true
	end,
}
vim.notify = function(text)
	notices[#notices + 1] = text
end
dofile(cwd .. "/lua/plugins/git/diffview.lua").config()
local review, annotations, lib =
	require("config.opencode_review"), require("config.annotations"), require("diffview.lib")
annotations.setup()
assert(vim.fn.maparg("gA", "n") ~= "" and vim.fn.maparg("gA", "x") ~= "", "missing compact annotation shortcuts")
local function open(args)
	vim.cmd("DiffviewOpen " .. args)
	local view = assert(lib.get_current_view())
	assert(
		vim.wait(5000, function()
			local pending = view:set_file_in_flight()
			return view.ready and view.cur_entry and not view.panel.updating and (not pending or pending:is_done())
		end, 20),
		"Diffview did not settle"
	)
	return view
end
local function comment(view, text, symbol)
	local window
	for _, candidate in ipairs(view.cur_layout.windows) do
		if candidate.file.symbol == (symbol or "b") then
			window = candidate
			break
		end
	end
	assert(window, "missing requested diff side")
	vim.api.nvim_set_current_win(window.id)
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	vim.ui.input = function(opts, callback)
		assert(
			opts.prompt:find("Enter:", 1, true) and opts.prompt:find("Esc:", 1, true),
			"annotation prompt hides save/cancel semantics"
		)
		if view.opencode_review then
			assert(
				opts.prompt:find(view.opencode_review.provenance.sessionID, 1, true),
				"annotation prompt hides its recipient"
			)
		else
			assert(opts.prompt:find("locally", 1, true), "unbound annotation prompt hides local-only behavior")
		end
		callback(text)
	end
	annotations.add_current()
end
local function close()
	vim.cmd("DiffviewClose")
	vim.wait(30, function()
		return false
	end)
end
local function saved()
	return vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
end
for _, harness in ipairs({ "opencode", "claude", "codex" }) do
	owner = {
		kind = harness == "opencode" and "native" or "acp",
		harness = harness,
		project = root,
		sessionID = "session-" .. harness,
		generation = harness,
	}
	local view = open("--imply-local=false " .. before .. ".." .. after)
	assert(view.opencode_review, "ordinary DiffviewOpen did not bind annotation auto-send")
	assert(view.left.commit == before and view.right.commit == after, "auto-review changed the comparison")
	assert(#sent == 0, "opening a view replayed existing annotations")
	comment(view, "Historical " .. harness)
	assert(#sent == 1 and vim.deep_equal(sent[1].provenance, owner), "comment missed the exact agent")
	assert(sent[1].prompt:find(before, 1, true) and sent[1].prompt:find(after, 1, true), "prompt lost revision context")
	assert(sent[1].prompt:find("+committed", 1, true), "hunk did not describe the displayed historical diff")
	assert(not sent[1].prompt:find("+working", 1, true), "historical review used current worktree content")
	local original = vim.deepcopy(owner)
	owner.sessionID = "replacement"
	comment(view, "Stale " .. harness, "a")
	assert(#sent == 1, "stale view redirected its comment to the replacement session")
	assert(saved()[#saved()].review.provenance.sessionID == original.sessionID)
	close()
	sent = {}
end
owner = { kind = "native", project = root, sessionID = "staged", generation = "staged" }
local view = open("--cached")
comment(view, "Staged only")
assert(#sent == 1 and sent[1].prompt:find("index:0", 1, true), "staged revision was lost")
assert(sent[1].prompt:find("+staged", 1, true) and not sent[1].prompt:find("+working", 1, true))
close()
sent = {}
view = open("")
comment(view, "Index to working tree")
assert(#sent == 1 and sent[1].prompt:find("index:0", 1, true), "default comparison lost its index base")
assert(sent[1].prompt:find("-staged", 1, true) and sent[1].prompt:find("+working", 1, true))
-- Live Visual marks must win over an earlier selection's '< and '> marks.
vim.fn.setpos("'<", { 0, 3, 1, 0 })
vim.fn.setpos("'>", { 0, 3, 1, 0 })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! Vj")
vim.ui.input = function(_, callback)
	callback("Live visual range")
end
annotations.add_visual()
local selected_note = saved()[#saved()]
assert(selected_note.line == 1 and selected_note.end_line == 2, "gA used stale Visual marks")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
local selections = require("diffview.api.selections")
selections.select({ "example.txt" }, { view = view, kind = "working" })
vim.fn.writefile({ "first", "ordinary view edit", "last" }, root .. "/example.txt")
local refreshed = false
view:update_files(nil, function()
	refreshed = true
end)
assert(
	vim.wait(5000, function()
		return refreshed
	end, 20),
	"ordinary view did not refresh"
)
assert(selections.is_selected("example.txt", { view = view }), "ordinary Diffview reviewed marks remain unchanged")
close()
sent = {}
vim.cmd("DiffviewFileHistory example.txt")
view = assert(lib.get_current_view())
assert(
	vim.wait(5000, function()
		local pending = view:set_file_in_flight()
		return view.cur_entry and (not pending or pending:is_done())
	end, 20),
	"file history did not select a revision"
)
assert(view.opencode_review, "file history did not capture an agent")
comment(view, "Historical entry")
assert(#sent == 1 and saved()[#saved()].review.comparison.a.commit, "history comment lost its selected revisions")
close()
owner = nil
local count = #sent
view = open("HEAD")
comment(view, "Local-only comment")
assert(#sent == count, "unbound Diffview reused another review route")
local local_note = saved()[#saved()]
assert(local_note.text == "Local-only comment" and not local_note.review, "unbound annotation was not saved locally")
assert(table.concat(notices, "\n"):find("saved locally", 1, true), "missing local-only explanation")
close()
-- A real merge view must keep stage-three feedback separate from ours/result.
git("restore", "--staged", "--worktree", "example.txt")
git("checkout", "-b", "other")
vim.fn.writefile({ "first", "their change", "last" }, root .. "/example.txt")
git("commit", "-am", "theirs")
git("checkout", "-b", "ours", after)
vim.fn.writefile({ "first", "our change", "last" }, root .. "/example.txt")
git("commit", "-am", "ours")
assert(vim.system({ "git", "-C", root, "-c", "commit.gpgsign=false", "merge", "other" }):wait().code ~= 0)
owner = { kind = "native", project = root, sessionID = "merge", generation = "merge" }
sent = {}
view = open("")
comment(view, "Theirs feedback", "c")
local merge_note = saved()[#saved()]
assert(merge_note.side == "theirs" and merge_note.review.comparison.c.stage == 3, "merge side was mislabeled")
assert(#sent == 1 and sent[1].prompt:find("their change", 1, true), "merge selection context was lost")
close()
require("config.hotreload").unwatch_directory(root)
vim.cmd.cd(cwd)
vim.fn.delete(root, "rf")
print(
	"PASS ordinary Diffview auto-review: exact native/ACP sessions, historical/staged context, stale and absent routes"
)

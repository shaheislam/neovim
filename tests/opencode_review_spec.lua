-- Integration: real Git worktree, Diffview buffers, file watcher and native routes.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
for _, plugin in ipairs({ "plenary.nvim", "diffview.nvim" }) do
	vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.cmd("runtime plugin/diffview.lua")
vim.o.autoread = true
vim.o.hidden = true
vim.o.swapfile = false

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message .. "\nactual: " .. vim.inspect(actual))
end
local function wait_for(predicate, message)
	assert(vim.wait(5000, predicate, 20), message)
end
local scratch = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
vim.fn.mkdir(scratch .. "/repo/src", "p")
local function git(dir, ...)
	local argv = {
		"git",
		"-C",
		dir,
		"-c",
		"user.name=Review Test",
		"-c",
		"user.email=review@example.test",
		"-c",
		"commit.gpgsign=false",
		"-c",
		"core.hooksPath=/dev/null",
	}
	vim.list_extend(argv, { ... })
	local result = vim.system(argv, { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
git(scratch .. "/repo", "init")
vim.fn.writefile({ ".tmp/" }, scratch .. "/repo/.gitignore")
vim.fn.writefile({ "first", "before", "last" }, scratch .. "/repo/src/example.txt")
git(scratch .. "/repo", "add", ".")
git(scratch .. "/repo", "commit", "-m", "baseline")
git(scratch .. "/repo", "worktree", "add", "--detach", scratch .. "/review space", "HEAD")
local root = vim.uv.fs_realpath(scratch .. "/review space")
vim.cmd.cd(root)
local baseline = git(root, "rev-parse", "HEAD")
vim.fn.writefile({ "first", "after", "last" }, root .. "/src/example.txt")

local handoff = require("config.opencode_handoff")
handoff.setup()
handoff.register_terminal(root, "gen_review")
local hello = handoff.receive({ version = 1, type = "hello", directory = root, generation = "gen_review" })
local function bind(session, revision)
	return handoff.receive({
		version = 1,
		type = "bind",
		directory = root,
		generation = "gen_review",
		lease = hello.lease,
		sessionID = session,
		routeRevision = revision,
	})
end
local calls = {}
local port
local server = vim.fn.jobstart({
	"python3",
	"-u",
	"-c",
	[=[
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    failed = False
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        text = body['parts'][0]['text']
        status = 204
        if 'Simulate delivery failure' in text and not Handler.failed:
            Handler.failed = True
            status = 503
        self.send_response(status)
        self.end_headers()
        print(json.dumps({'path': self.path, 'text': text,
                          'dir': self.headers['x-opencode-directory'], 'status': status}), flush=True)
    def log_message(self, *args): pass
server = HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
]=],
}, {
	on_stdout = function(_, data)
		for _, line in ipairs(data) do
			if tonumber(line) then
				port = tonumber(line)
			elseif line ~= "" then
				calls[#calls + 1] = vim.json.decode(line)
			end
		end
	end,
})
assert(server > 0, "local HTTP fixture did not start")
wait_for(function()
	return port ~= nil
end, "local HTTP fixture did not publish its port")
vim.g.opencode_server_url = "http://127.0.0.1:" .. port
vim.env.OPENCODE_SERVER_PASSWORD = "review-test"
local notifications = {}
vim.notify = function(text)
	notifications[#notifications + 1] = text
end
dofile(original_cwd .. "/lua/plugins/git/diffview.lua").config()
local ok, review = pcall(require, "config.opencode_review")
assert(ok and type(review.start) == "function", "live review must open a pinned-base Diffview for the bound session")
review.setup()
eq(review.start(), false, "review cannot guess a session before a native bind")
bind("ses_review", 1)
eq(review.start("missing-review-base"), false, "an invalid base cannot open a review")
assert(review.start(), "review starts for the exact native binding")
local lib = require("diffview.lib")
local view = lib.get_current_view()
eq(view.left.commit, baseline, "review pins the starting commit")
eq(view.left.track_head, false, "review never follows moving HEAD")
local async = require("diffview.async")
local delay = async.wrap(function(callback)
	vim.defer_fn(callback, 250)
end, 1)
local render, rendering, maximum, injected = view.panel.render, 0, 0, false
view.panel.render = function(panel)
	rendering = rendering + 1
	maximum = math.max(maximum, rendering)
	if not injected then
		injected = true
		view:update_files()
		async.await(delay())
	end
	render(panel)
	rendering = rendering - 1
end
local serial_done = false
view:update_files(nil, function()
	serial_done = true
end)
wait_for(function()
	return serial_done and rendering == 0
end, "review refresh did not finish")
eq(maximum, 1, "refresh requests cannot destroy a panel while its renderer is yielding")
view.panel.render = render
local function side(symbol)
	for _, win in ipairs(view.cur_layout.windows) do
		if win.file and win.file.symbol == symbol and win.file.bufnr and vim.api.nvim_buf_is_loaded(win.file.bufnr) then
			return win
		end
	end
end
wait_for(function()
	return side("b") and side("a")
end, "real Diffview buffers did not load")
local right = side("b")
vim.api.nvim_set_current_win(right.id)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local context = review.current()
eq(context.base, baseline, "review retains the immutable baseline")
eq(context.provenance.sessionID, "ses_review", "review captures its exact session")
local merge_head = git(root, "rev-parse", "--git-path", "MERGE_HEAD")
vim.fn.writefile({ baseline }, merge_head)
assert(not vim.wait(800, function()
	return lib.get_current_view() ~= view
end, 20), "automatic conflict switching must not replace a pinned review")
vim.fn.delete(merge_head)

-- A committed edit stays in view; a new untracked file appears without focus.
git(root, "add", "src/example.txt")
git(root, "commit", "-m", "agent edit")
vim.fn.writefile({ "new file" }, root .. "/src/new.txt")
wait_for(function()
	for _, entry in view.files:iter() do
		if entry.path == "src/new.txt" then
			return true
		end
	end
	return false
end, "the existing file watcher did not refresh the review file list")
eq(view.left.commit, baseline, "auto-commit does not collapse the review diff")
assert(review.start(), "starting again focuses the existing review")
eq(lib.get_current_view(), view, "starting again does not create another tab or reset the base")
eq(vim.api.nvim_get_current_win(), right.id, "refresh preserves the focused diff window")
eq(vim.api.nvim_win_get_cursor(right.id), { 2, 0 }, "refresh preserves the review cursor")

local annotations = require("config.annotations")
annotations.setup()
vim.ui.input = function(_, callback)
	callback("Handle this edge case")
end
annotations.add_current()
wait_for(function()
	return #calls == 1
end, "comment did not reach the exact-session HTTP endpoint")
eq(#calls, 1, "saving a review comment automatically submits one prompt")
eq(calls[1].path, "/session/ses_review/prompt_async", "comment targets the captured session")
eq(calls[1].dir, root, "comment targets the linked worktree, not its main checkout")
assert(calls[1].text:find("+after", 1, true), "comment hunk is against the pinned base, even after commit")
assert(calls[1].text:find("new side", 1, true), "comment names the side of the diff")
assert(calls[1].text:find(baseline, 1, true), "comment names the immutable baseline")
local saved = vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
eq(saved[1].file, "src/example.txt", "nested worktree paths stay repo-relative")
eq(saved[1].review.provenance.sessionID, "ses_review", "saved comment retains routing provenance for retries")

local left = side("a")
vim.api.nvim_set_current_win(left.id)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
annotations.add_current()
wait_for(function()
	return #calls == 2
end, "old-side comment did not reach HTTP")
eq(#calls, 2, "comments on the old side also auto-submit")
assert(calls[2].text:find("old side", 1, true), "old-side comment is distinguished")
local marks =
	vim.api.nvim_buf_get_extmarks(left.file.bufnr, vim.api.nvim_create_namespace("repo_annotations"), 0, -1, {})
eq(#marks, 1, "comments render in real Diffview nowrite buffers")

annotations.list()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.fn.maparg("<CR>", "n", false, true).callback()
wait_for(function()
	return vim.api.nvim_get_current_win() == left.id
end, "opening an old-side comment did not focus its diff window")
eq(vim.api.nvim_win_get_buf(left.id), left.file.bufnr, "panel navigation preserves the old-side diff buffer")

vim.fn.writefile({ "first", "agent addressed review", "last" }, root .. "/src/example.txt")
wait_for(function()
	return vim.api.nvim_buf_get_lines(right.file.bufnr, 1, 2, false)[1] == "agent addressed review"
end, "external edits did not reload the visible worktree buffer")
eq(vim.api.nvim_get_current_win(), left.id, "external source reload preserves the old-side focus")
saved = vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
saved[2].text = "RESOLVED: " .. saved[2].text
vim.fn.writefile({ vim.json.encode(saved) }, root .. "/.tmp/annotations.json")
wait_for(function()
	return #vim.api.nvim_buf_get_extmarks(
			left.file.bufnr,
			vim.api.nvim_create_namespace("repo_annotations"),
			0,
			-1,
			{}
		) == 0
end, "agent resolution did not remove the inline comment")

vim.ui.input = function(_, callback)
	callback("Simulate delivery failure")
end
annotations.add_current()
wait_for(function()
	return vim.iter(notifications):any(function(text)
		return text:find("delivery failed", 1, true)
	end)
end, "transport failure was not surfaced as a saved, retryable comment")
annotations.ask_current()
wait_for(function()
	return #calls == 4
end, "explicit retry did not reach HTTP")
eq(calls[4].status, 204, "failed delivery can be retried through the same session")
eq(calls[4].path, "/session/ses_review/prompt_async", "retry keeps the original route")

-- Idle handoff refreshes in place rather than opening a file over the review.
local focused = vim.api.nvim_get_current_win()
handoff.receive({
	version = 1,
	type = "idle_batch",
	directory = root,
	generation = "gen_review",
	lease = hello.lease,
	sessionID = "ses_review",
	routeRevision = 1,
	paths = { "src/new.txt" },
})
wait_for(function()
	return #vim.fn.getqflist() == 1
end, "idle batch did not run")
eq(vim.api.nvim_get_current_win(), focused, "idle does not steal review focus")
eq(lib.get_current_view(), view, "idle keeps the pinned review open")

-- A route change during the comment input cannot send the note elsewhere.
local input_callback
vim.ui.input = function(_, callback)
	input_callback = callback
end
annotations.add_current()
bind("ses_other", 2)
input_callback("Saved but stale")
eq(#calls, 4, "a session switch during input blocks automatic delivery")
annotations.ask_all()
eq(#calls, 4, "retry cannot redirect old comments to a new session")
saved = vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
assert(
	vim.iter(saved):any(function(item)
		return item.text == "Saved but stale"
	end),
	"failed delivery keeps the comment on disk"
)

require("config.hotreload").unwatch_directory(root)
vim.api.nvim_del_augroup_by_name("opencode_review")
local drained = false
view:update_files(nil, function()
	drained = true
end)
wait_for(function()
	return drained
end, "Diffview refresh did not drain before teardown")
view:close()
vim.cmd.edit(root .. "/src/example.txt")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.ui.input = function(_, callback)
	callback("Edited outside the review")
end
annotations.add_current()
annotations.ask_current()
eq(#calls, 4, "editing a saved review note outside Diffview cannot redirect delivery")
saved = vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
eq(saved[1].review.provenance.sessionID, "ses_review", "editing outside review retains the original provenance")
assert(not vim.wait(300, function()
	return #calls > 4
end, 20), "stale comments never issue an asynchronous request to another session")
handoff.unregister_terminal(root, "gen_review")
vim.cmd.cd(original_cwd)
vim.fn.jobstop(server)
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_get_name(buf):sub(1, #scratch) == scratch then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
-- Drain the existing plugin's deferred focus/checktime callbacks before cleanup.
vim.wait(600, function()
	return false
end, 20)
vim.fn.delete(scratch, "rf")
print("PASS live Diffview review: pinned commits, external edits, inline comments and exact-session routing")

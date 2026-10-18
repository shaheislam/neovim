-- Opt-in provider test: AGENT_LIVE_HARNESS=claude|codex|hermes|opencode, with -u ./init.lua.
local harness = assert(vim.env.AGENT_LIVE_HARNESS, "set AGENT_LIVE_HARNESS")
local notify = vim.notify
vim.notify = function(text, level, opts)
	if not level or level >= vim.log.levels.WARN then
		notify(text, level, opts)
	end
end
assert(vim.tbl_contains({ "claude", "codex", "hermes", "opencode" }, harness))
local scratch, cwd = vim.fn.tempname(), vim.fn.getcwd()
vim.fn.mkdir(scratch .. "/repo/src", "p")
local function git(root, ...)
	local argv = {
		"git",
		"-C",
		root,
		"-c",
		"user.name=Live Review",
		"-c",
		"user.email=test@example.invalid",
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
git(scratch .. "/repo", "init", "-q")
vim.fn.writefile({ ".tmp/" }, scratch .. "/repo/.gitignore")
vim.fn.writefile({ "first", "before", "last" }, scratch .. "/repo/src/example.txt")
git(scratch .. "/repo", "add", ".")
git(scratch .. "/repo", "commit", "-qm", "baseline")
git(scratch .. "/repo", "worktree", "add", "-q", "--detach", scratch .. "/review space", "HEAD")
local root = vim.uv.fs_realpath(scratch .. "/review space")
vim.cmd.cd(root)
vim.fn.writefile({ "first", "needs-review", "last" }, root .. "/src/example.txt")
local agent = require("config.agent_session")
assert(agent.open(harness, root, { hidden = true, new = true }), "live owner did not bind")
local route = assert(agent.capture(root))
local permission = require("codecompanion.interactions.chat.acp.request_permission")
local original_confirm, approvals = permission.confirm, 0
-- Test-only approval is restricted to this disposable fixture; production uses the client's UI.
permission.confirm = function(_, request)
	local tool = request.tool_call or {}
	local locations = tool.locations or {}
	local allowed = (tool.kind == "edit" or tool.kind == "read") and #locations > 0
	for _, location in ipairs(locations) do
		allowed = allowed
			and (location.path == root .. "/src/example.txt" or location.path == root .. "/.tmp/annotations.json")
	end
	for _, option in ipairs(request.options or {}) do
		if option.kind == (allowed and "allow_once" or "reject_once") then
			approvals = approvals + 1
			return request.respond(option.optionId, false)
		end
	end
	request.respond(nil, true)
end
require("lazy").load({ plugins = { "diffview.nvim" } })
local review, annotations = require("config.opencode_review"), require("config.annotations")
assert(review.start())
local view = require("diffview.lib").get_current_view()
local baseline = view.left.commit
local function right()
	for _, win in ipairs(view.cur_layout.windows) do
		if win.file and win.file.symbol == "b" and win.file.bufnr and vim.api.nvim_buf_is_loaded(win.file.bufnr) then
			return win
		end
	end
end
assert(
	vim.wait(10000, function()
		return right() ~= nil
	end, 20),
	"diff buffers did not load"
)
local win = right()
vim.api.nvim_set_current_win(win.id)
vim.api.nvim_win_set_cursor(win.id, { 2, 0 })
local original_input = vim.ui.input
vim.ui.input = function(_, callback)
	callback(
		"Replace only line 2 of src/example.txt with exactly reviewed-"
			.. harness
			.. ". Read and edit only that file and .tmp/annotations.json. Do not run shell commands, create other files, or commit. Mark this annotation RESOLVED after making the edit."
	)
end
annotations.add_current()
vim.ui.input = original_input
local function notes()
	return vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
end
local resolved = vim.wait(180000, function()
	local items = notes()
	return vim.fn.readfile(root .. "/src/example.txt")[2] == "reviewed-" .. harness
		and items[1].text:find("RESOLVED:", 1, true) ~= nil
end, 100)
if not resolved then
	print("Source: " .. vim.inspect(vim.fn.readfile(root .. "/src/example.txt")))
	print("Notes: " .. vim.inspect(notes()))
	local owner = require("config.agent_acp").resolve(route)
	if owner then
		print(table.concat(vim.api.nvim_buf_get_lines(owner.chat.bufnr, 0, -1, false), "\n"))
	end
end
assert(resolved, "agent did not apply and resolve the auto-submitted inline comment")
assert(
	vim.wait(15000, function()
		return vim.api.nvim_buf_get_lines(win.file.bufnr, 1, 2, false)[1] == "reviewed-" .. harness
	end, 20),
	"external agent edit did not reload"
)
assert(
	view.left.commit == baseline and vim.api.nvim_get_current_win() == win.id,
	"live review lost its baseline or focus"
)
assert(vim.deep_equal(notes()[1].review.provenance, route), "feedback changed delivery targets")
git(root, "add", "src/example.txt")
git(root, "commit", "-qm", "reviewed")
assert(view.left.commit == baseline, "commit collapsed the pinned review")
local switch = require("config.agent_switch")
assert(
	vim.wait(30000, function()
		if route.kind == "acp" then
			return not require("config.agent_acp").busy(root)
		end
		local done, idle = false, false
		require("config.opencode_http").get("/session/status", function(ok, output)
			if ok then
				local status = vim.json.decode(output)[route.sessionID]
				idle = not status or status.type == "idle"
			end
			done = true
		end, { dir = root })
		return vim.wait(3000, function()
			return done
		end, 20) and idle
	end, 100),
	"source did not finish its turn"
)
if vim.env.AGENT_LIVE_SWITCH == "1" then
	local destination = vim.env.AGENT_LIVE_DESTINATION or (harness == "claude" and "codex" or "claude")
	assert(destination ~= harness and vim.tbl_contains({ "claude", "codex", "hermes", "opencode" }, destination))
	assert(switch.begin(destination))
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:find("Replace this", 1, true) then
			lines[i] = "Validation complete. Reply HANDOFF_OK without tools or file changes."
		end
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	local original_select = vim.ui.select
	vim.ui.select = function(_, _, callback)
		callback("Keep feedback with its original session")
	end
	assert(switch.continue(false))
	vim.ui.select = original_select
	local next_route = assert(agent.capture(root))
	assert(next_route.harness == destination and not agent.resolve(route), "switch did not retire the original owner")
	assert(
		view.opencode_review.base == baseline and vim.deep_equal(view.opencode_review.provenance, next_route),
		"switch did not retain and rebind the review"
	)
	assert(agent.preference(root) == destination and vim.deep_equal(notes()[1].review.provenance, route))
	assert(
		vim.wait(180000, function()
			return not require("config.agent_acp").busy(root)
		end, 50),
		"handoff turn did not finish"
	)
	route = next_route
end
assert(switch.quiesce(route, false))
permission.confirm = original_confirm
require("config.hotreload").unwatch_directory(root)
vim.api.nvim_del_augroup_by_name("opencode_review")
local refreshed = false
view:update_files(nil, function()
	refreshed = true
end)
assert(vim.wait(5000, function()
	return refreshed
end, 20))
view:close()
vim.cmd.cd(cwd)
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):find(scratch, 1, true) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
vim.wait(650, function()
	return false
end, 20)
vim.fn.delete(scratch, "rf")
print(
	"PASS "
		.. harness
		.. " live inline review, real file edit/resolution, permissions="
		.. approvals
		.. ", pinned commit and optional harness handoff"
)

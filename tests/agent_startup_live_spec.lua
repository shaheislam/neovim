-- Opt in: AGENT_LIVE_HARNESS=opencode|claude|codex nvim --headless -u ./init.lua -l ...
local harness = assert(vim.env.AGENT_LIVE_HARNESS, "set AGENT_LIVE_HARNESS")
assert(vim.tbl_contains({ "opencode", "claude", "codex" }, harness))
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
local skill_dir = root .. (harness == "claude" and "/.claude/skills/" or "/.agents/skills/") .. "startup-probe"
vim.fn.mkdir(skill_dir, "p")
local token = "STARTUP_PROBE_ONLY_FROM_SKILL_9A7C"
vim.fn.writefile({
	"---",
	"name: startup-probe",
	"description: Verify explicit startup skill invocation.",
	"---",
	"Reply exactly " .. token .. ". Do not change files or run tools except to read this skill.",
}, skill_dir .. "/SKILL.md")
local path = root .. "/startup.json"
vim.fn.writefile({
	vim.json.encode({
		version = 1,
		project = root,
		harness = harness,
		model = vim.env.AGENT_LIVE_MODEL or "",
		prompt = (harness == "codex" and "$" or "/") .. "startup-probe",
	}),
}, path)
assert(vim.uv.fs_chmod(path, 384))
local failure
local notify = vim.notify
vim.notify = function(message, level, opts)
	if tostring(message):find("Initial agent prompt stopped:", 1, true) then
		failure = tostring(message)
	end
	return notify(message, level, opts)
end
local http = require("config.opencode_http")
local post, native_output, sent = http.post, nil, 0
http.post = function(endpoint, body, callback, opts)
	if not endpoint:match("/command$") then
		return post(endpoint, body, callback, opts)
	end
	sent = sent + 1
	return post(endpoint, body, function(ok, output)
		native_output = output
		callback(ok, output)
	end, opts)
end
local ok, err = pcall(function()
	assert(require("config.agent_startup").run(path, root, harness), failure)
	local claimed = path .. ".claimed." .. vim.fn.getpid()
	assert(
		vim.wait(180000, function()
			return failure or not vim.uv.fs_stat(claimed)
		end, 20),
		"startup timed out"
	)
	assert(not failure, failure)
	local route = assert(require("config.agent_session").capture(root))
	if harness == "opencode" then
		assert(
			sent == 1 and native_output and native_output:find(token, 1, true),
			"native skill did not produce its private token"
		)
	else
		local owner = assert(require("config.agent_acp").resolve(route))
		local text = table.concat(vim.api.nvim_buf_get_lines(owner.chat.bufnr, 0, -1, false), "\n")
		assert(text:find(token, 1, true), "ACP skill did not produce its private token")
		assert(require("config.agent_acp").close(root), "startup turn remained busy")
	end
end)
http.post, vim.notify = post, notify
if harness == "opencode" then
	require("config.opencode_terminal").close(root)
else
	local owner = require("config.agent_acp").resolve(require("config.agent_acp").capture(root))
	if owner then
		owner.connection:disconnect()
	end
end
require("config.hotreload").unwatch_directory(root)
vim.fn.delete(root, "rf")
assert(ok, err)
print("PASS " .. harness .. " live startup model and native skill dispatch")

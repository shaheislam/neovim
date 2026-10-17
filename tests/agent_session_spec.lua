package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
root = vim.uv.fs_realpath(root)
local native = { kind = "native", project = root, sessionID = "ses_native", generation = "native-owner" }
local acp_route
local sent = {}
package.loaded["config.opencode_handoff"] = {
	capture_route = function()
		return native
	end,
	resolve_plan_route = function(route)
		return route == native and { directory = root, sessionID = native.sessionID } or nil
	end,
}
package.loaded["config.agent_acp"] = {
	open = function()
		return {}
	end,
	capture = function()
		return acp_route
	end,
	resolve = function(route)
		return route == acp_route and acp_route or nil
	end,
	submit = function(route, text, cb)
		sent[#sent + 1] = { route, text }
		cb("queued")
		return true
	end,
}
package.loaded["config.opencode_http"] = {
	prompt_async = function(id, text, opts, cb)
		sent[#sent + 1] = { id, text, opts.dir }
		cb(true)
	end,
}
local agent = require("config.agent_session")
assert(agent.capture(root) == native, "native route remains compatible")
assert(agent.submit(native, "native feedback", function(state)
	assert(state == "submitted")
end))
acp_route = { kind = "acp", project = root, harness = "claude", sessionID = "claude-id", generation = "acp-owner" }
assert(not agent.capture(root), "ambiguous active owners must not be guessed")
assert(not agent.open("claude", root), "ambiguous ownership cannot launch another writer")
native = nil
assert(agent.capture(root) == acp_route)
assert(agent.submit(acp_route, "ACP feedback", function(state)
	assert(state == "queued")
end))
assert(#sent == 2 and sent[2][1] == acp_route)
acp_route = nil
assert(not agent.submit({ kind = "acp", project = root }, "stale", function()
	error("no transport")
end))
assert(#sent == 2, "stale ACP routes never fall back to native HTTP")
assert(agent.preference(root) == "opencode")
assert(agent.set_preference(root, "codex"))
assert(agent.preference(root) == "codex")
assert(not pcall(agent.set_preference, root, "codex;bad"))
local created, launched = 0, {}
package.loaded.lazy = { load = function() end }
package.loaded["config.opencode_http"].request = function(method, path, body, cb)
	assert(method == "POST" and path == "/session")
	assert(type(body.title) == "string", "the session creation body must encode as a JSON object")
	created = created + 1
	cb(true, vim.json.encode({ id = "ses_created" }))
end
package.loaded["config.opencode_terminal"] = {
	generation_for = function()
		return "native-owner"
	end,
	start = function(_, context)
		assert(context.session_id == "ses_created", "a fresh native launch must use an explicitly created session")
		launched[#launched + 1] = context.session_id
		native = { kind = "native", project = root, sessionID = context.session_id, generation = "native-owner" }
	end,
}
assert(agent.open("opencode", root, { hidden = true }))
assert(created == 1 and #launched == 1, "create the exact native session before launching its terminal")
local original_open, cwd = agent.open, vim.fn.getcwd()
local startup = {}
local editor = vim.api.nvim_get_current_win()
package.loaded["config.project_terminal"] = {
	open = function(dir)
		assert(dir == root)
		startup[#startup + 1] = "shell"
		vim.cmd.split()
	end,
}
agent.open = function(harness, dir)
	assert(harness == "codex" and dir == root, "startup preserves the selected harness and project")
	assert(vim.api.nvim_get_current_win() == editor, "restore the editor before opening the agent pane")
	startup[#startup + 1] = "agent"
end
vim.fn.chdir(root)
vim.env.NVIM_AGENT_HARNESS, vim.env.NVIM_AGENT_LAYOUT = "codex", "1"
agent.setup()
assert(not vim.env.NVIM_AGENT_HARNESS and not vim.env.NVIM_AGENT_LAYOUT, "startup flags do not leak to child shells")
vim.api.nvim_exec_autocmds("VimEnter", {})
assert(
	vim.wait(1000, function()
		return #startup == 2
	end),
	"selected worktree agent opens after VimEnter"
)
assert(vim.deep_equal(startup, { "shell", "agent" }), "worktree startup builds the shell before its selected agent")
agent.open = original_open
vim.fn.chdir(cwd)
vim.fn.delete(root, "rf")
print("PASS neutral routes, ambiguous-owner rejection, exact transports, worktree preference and startup")

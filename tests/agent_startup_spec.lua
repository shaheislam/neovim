package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local opened, sent, route = {}, {}, nil
local switch_on_capture = false
local outcome = function(callback)
	callback(true, "")
end
local commands = { { name = "goal" }, { name = "$goal" } }
local notifications = {}
vim.notify = function(message)
	notifications[#notifications + 1] = message
end
package.loaded["config.agent_session"] = {
	open = function(harness, dir, opts)
		opened[#opened + 1] = { harness = harness, dir = dir, model = opts.model }
		route = {
			kind = harness == "opencode" and "native" or "acp",
			harness = harness,
			project = dir,
			sessionID = "ses_exact",
			generation = "owner",
		}
		return route
	end,
	capture = function()
		if switch_on_capture then
			route = vim.tbl_extend("force", route, { generation = "replacement", sessionID = "ses_other" })
		end
		return route
	end,
	resolve = function(value)
		return value == route and route
	end,
	submit = function(value, text, callback)
		assert(value == route)
		sent[#sent + 1] = { text = text, harness = value.harness }
		callback("turn_ended")
		return true
	end,
}
package.loaded["config.agent_acp"] = {
	commands = function()
		return commands
	end,
}
package.loaded["config.opencode_http"] = {
	get = function(path, callback, opts)
		if path == "/command" then
			assert(opts.timeout >= 30, "command discovery must allow the MCP connection startup budget")
		end
		callback(
			true,
			vim.json.encode(
				path == "/provider"
						and { all = { { id = "provider", models = { chosen = {} } } }, connected = { "provider" } }
					or { { name = "goal" } }
			)
		)
	end,
	post = function(path, body, callback, opts)
		assert(opts.dir == root and path:find("ses_exact", 1, true))
		sent[#sent + 1] = { path = path, body = body }
		outcome(callback)
	end,
}
local files = {}
local function request(harness, model, prompt, project)
	local file = vim.fn.tempname()
	files[#files + 1] = file
	vim.fn.writefile({
		vim.json.encode({
			version = 1,
			harness = harness,
			model = model,
			prompt = prompt,
			project = project or root,
		}),
	}, file)
	assert(vim.uv.fs_chmod(file, 384))
	return file
end
local startup = require("config.agent_startup")
local file = request("opencode", "provider/chosen", "")
assert(startup.run(file, root, "opencode"))
assert(
	#opened == 1 and opened[1].model == "provider/chosen" and #sent == 0,
	"model-only startup never sends a dummy turn"
)
assert(vim.fn.filereadable(file) == 0, "successful requests are consumed")
assert(not startup.run(file, root, "opencode") and #opened == 1, "consumed requests cannot replay")
switch_on_capture = true
assert(
	not startup.run(request("opencode", "provider/chosen", ""), root, "opencode"),
	"a replacement owner cannot claim a successful model-only startup"
)
switch_on_capture = false
local text = 'inspect "quotes" $() — café\nsecond line\n'
assert(startup.run(request("opencode", "provider/chosen", text), root, "opencode"))
assert(
	sent[1].body.parts[1].text == text and sent[1].body.model.modelID == "chosen",
	"exact text and selected model reach the owned session"
)
assert(startup.run(request("opencode", "", "/goal inspect\nmore"), root, "opencode"))
assert(
	sent[2].path == "/session/ses_exact/command"
		and sent[2].body.command == "goal"
		and sent[2].body.arguments == "inspect\nmore",
	"skills use the command endpoint"
)
local count = #sent
file = request("opencode", "", "/missing args")
assert(not startup.run(file, root, "opencode") and #sent == count, "unknown commands never degrade to ordinary prompts")
assert(vim.fn.glob(file .. ".claimed.*") ~= "", "failed dispatch preserves its private draft")
count = #opened
assert(
	not startup.run(request("opencode", "provider/unavailable", "never send"), root, "opencode") and #opened == count,
	"invalid models stop before opening"
)
assert(startup.run(request("claude", "opus", "/goal task"), root, "claude"))
assert(opened[#opened].model == "opus" and sent[#sent].text == "/goal task")
assert(startup.run(request("codex", "gpt-6-sol", "$goal task"), root, "codex"))
assert(sent[#sent].text == "$goal task", "Codex skill spelling is preserved")
assert(startup.run(request("hermes", "", "/goal task"), root, "hermes"))
assert(sent[#sent].harness == "hermes" and sent[#sent].text == "/goal task")
outcome = function(callback)
	callback(false, "timeout")
	callback(true, "late acceptance")
end
file = request("opencode", "", "uncertain delivery")
count = #sent
assert(startup.run(file, root, "opencode") and #sent == count + 1, "uncertain submissions are never retried")
assert(vim.fn.glob(file .. ".claimed.*") ~= "", "late duplicate completion cannot erase an uncertain draft")
outcome = function(callback)
	callback(true, "")
end
commands = nil
count = #sent
assert(
	not startup.run(request("claude", "", "/goal task"), root, "claude") and #sent == count,
	"unobserved command discovery cannot authorize dispatch"
)
count = #opened
assert(
	not startup.run(request("codex", "", "text", root .. "/other"), root, "codex") and #opened == count,
	"requests cannot cross project boundaries"
)
file = request("claude", "", "private")
assert(vim.uv.fs_chmod(file, 420))
assert(not startup.run(file, root, "claude") and #opened == count, "publicly readable payloads are rejected")
vim.fn.delete(file)
file = request("claude", "", "private")
assert(vim.uv.fs_symlink(file, file .. ".link"))
assert(not startup.run(file .. ".link", root, "claude") and #opened == count, "symlink payloads cannot be claimed")
vim.fn.delete(file .. ".link")
for _, path in ipairs(files) do
	vim.fn.delete(path)
	for _, claimed in ipairs(vim.fn.glob(path .. ".claimed.*", false, true)) do
		vim.fn.delete(claimed)
	end
end
vim.fn.delete(root, "rf")
print("PASS one-shot startup, model-only selection, exact text, native commands, and fail-closed drafts")

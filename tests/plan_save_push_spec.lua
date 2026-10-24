package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message or (vim.inspect(actual) .. " ~= " .. vim.inspect(expected)))
end

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

local root = vim.fn.tempname()
assert(vim.fn.mkdir(root, "p") == 1, "failed to create temporary project")
root = canonical(root)
local plan_path = root .. "/.plan.md"
assert(vim.fn.writefile({ "# Plan", "initial" }, plan_path) == 0, "failed to create plan")

local idle = require("config.diffview_idle")
idle.setup()
eq(idle.open_plan(root, { kind = "rex", sessionID = "ses_live" }).status, "opened", "plan opens with Rex provenance")
local plan_buf = vim.api.nvim_get_current_buf()

local original_session = vim.env.REX_SESSION
local original_block = vim.env.REX_BLOCK
local original_vim_system = vim.system
local original_http = package.loaded["config.opencode_http"]
local route_is_owned = true
local verify_calls = {}
local prompt_succeeds = true
local prompt_calls = {}
local complete_prompts_immediately = true
local prompt_callbacks = {}

vim.env.REX_SESSION = "session:one"
vim.env.REX_BLOCK = "block:editor"
vim.system = function(args)
	if vim.list_contains(args, "--verify-route") then
		table.insert(verify_calls, { project = args[3], route = vim.json.decode(args[5]) })
		return {
			wait = function()
				return { code = route_is_owned and 0 or 1, stdout = "", stderr = "" }
			end,
		}
	end
	return {
		wait = function()
			return { code = 0, stdout = "", stderr = "" }
		end,
	}
end
package.loaded["config.opencode_http"] = {
	prompt_async = function(session_id, text, opts, callback)
		table.insert(prompt_calls, { session_id = session_id, text = text, dir = opts.dir })
		table.insert(prompt_callbacks, callback)
		if complete_prompts_immediately then
			callback(prompt_succeeds, prompt_succeeds and "" or "unavailable")
		end
	end,
}

vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "human direction one" })
vim.cmd("write")
eq(#prompt_calls, 1, "changed human plan save notifies one OpenCode session")
eq(prompt_calls[1].session_id, "ses_live", "plan save targets the routed session")
eq(prompt_calls[1].dir, root, "plan save targets the routed project")
assert(prompt_calls[1].text:find("HUMAN PLAN SAVE", 1, true), "plan prompt is visibly labelled")
assert(prompt_calls[1].text:find("re-read", 1, true), "plan prompt tells the agent to re-read disk state")
assert(not prompt_calls[1].text:find("planctl", 1, true), "plan prompt removes the obsolete planctl contract")
assert(prompt_calls[1].text:find("edit .plan.md directly", 1, true), "plan prompt reflects direct living-plan maintenance")

vim.cmd("write")
eq(#prompt_calls, 1, "unchanged plan save does not notify twice")

prompt_succeeds = false
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "retry this direction" })
vim.cmd("write")
eq(#prompt_calls, 2, "failed plan notification is attempted")
prompt_succeeds = true
vim.cmd("write")
eq(#prompt_calls, 3, "failed plan notification remains retryable")

complete_prompts_immediately = false
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "single flight one" })
vim.cmd("write")
eq(#prompt_calls, 4, "the first delayed plan notification starts immediately")
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "single flight two" })
vim.cmd("write")
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "single flight newest" })
vim.cmd("write")
eq(#prompt_calls, 4, "new saves coalesce while one notification is in flight")
prompt_callbacks[4](true, "")
eq(#prompt_calls, 5, "completion sends exactly one coalesced follow-up")
prompt_callbacks[5](true, "")
vim.cmd("write")
eq(#prompt_calls, 5, "the newest coalesced signature becomes the notified baseline")
complete_prompts_immediately = true

route_is_owned = false
verify_calls = {}
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "unowned route" })
vim.cmd("write")
eq(#prompt_calls, 5, "unverified source route fails closed")
eq(#verify_calls, 1, "route validation consults the shared verifier")
eq(verify_calls[1], { project = root, route = { kind = "rex", sessionID = "ses_live" } }, "verifier receives the routed identity")

route_is_owned = true
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "owned again" })
vim.cmd("write")
eq(#prompt_calls, 6, "a re-proven route resumes notification")

vim.env.REX_BLOCK = nil
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "missing route" })
vim.cmd("write")
eq(#prompt_calls, 6, "missing route fails closed")

local original_handoff = package.loaded["config.opencode_handoff"]
local native_live = true
package.loaded["config.opencode_handoff"] = {
	resolve_plan_route = function()
		return native_live and { sessionID = "ses_native", directory = root } or nil
	end,
}
idle.open_plan(root, {
	kind = "native",
	project = root,
	sessionID = "ses_native",
	generation = "generation_native",
	routeRevision = 4,
	routeToken = "route_native",
})
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "native save" })
vim.cmd("write")
eq(#prompt_calls, 7, "a live native plan route notifies its exact session")
eq(prompt_calls[7].session_id, "ses_native", "native save uses its own exact session")

native_live = false
verify_calls = {}
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "stale native save" })
vim.cmd("write")
eq(#prompt_calls, 7, "a stale native plan route fails closed")
eq(#verify_calls, 0, "a stale native route never falls back to Rex provenance")
package.loaded["config.opencode_handoff"] = original_handoff

vim.system = original_vim_system
vim.env.REX_SESSION = original_session
vim.env.REX_BLOCK = original_block
package.loaded["config.opencode_http"] = original_http

local http = require("config.opencode_http")
local original_post = http.post
local posted
http.post = function(path, body, callback, opts)
	posted = { path = path, body = body, dir = opts.dir }
	callback(true, "")
end
local async_ok
http.prompt_async("ses_target", "Read the plan.", { dir = root }, function(ok)
	async_ok = ok
end)
eq(async_ok, true, "targeted async prompt reports success")
eq(posted.path, "/session/ses_target/prompt_async", "targeted async prompt uses the exact session endpoint")
eq(posted.body, { parts = { { type = "text", text = "Read the plan." } } }, "targeted async prompt sends text parts")
eq(posted.dir, root, "targeted async prompt sends the canonical project header")
posted = nil
http.prompt_async("../wrong", "Do not send.", { dir = root }, function(ok)
	async_ok = ok
end)
eq(async_ok, false, "invalid session id is rejected")
eq(posted, nil, "invalid session id never reaches HTTP")
http.post = original_post

assert(vim.fn.delete(root, "rf") == 0, "failed to remove temporary project")

print("PASS exact-session human plan save notification")
print("PASS targeted OpenCode async prompt helper")

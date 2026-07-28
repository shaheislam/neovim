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
eq(idle.open_plan(root).status, "opened", "plan must open before save notification test")
local plan_buf = vim.api.nvim_get_current_buf()

local original_tmux_pane = vim.env.TMUX_PANE
local original_state_home = vim.env.XDG_STATE_HOME
local original_system = vim.fn.system
local original_vim_system = vim.system
local original_http = package.loaded["config.opencode_http"]
local state_home = root .. "/state"
local route_dir = state_home .. "/opencode/plan-routes"
local route_path = route_dir .. "/pane-1.json"
local source_window = "@1"
local server_pid = "855"
local pane_is_owned = true
local verify_calls = {}
local prompt_succeeds = true
local prompt_calls = {}

local function write_route(fields)
	local route = { version = 1, sessionID = "ses_live", pane = "%1", directory = root, serverPid = "855" }
	for key, value in pairs(fields or {}) do
		-- false is the "omit this key" sentinel; assigning nil in a table
		-- literal would simply never reach this loop.
		route[key] = value ~= false and value or nil
	end
	assert(vim.fn.writefile({ vim.json.encode(route) }, route_path) == 0, "failed to write plan route")
end

assert(vim.fn.mkdir(route_dir, "p") == 1, "failed to create plan route directory")
vim.env.TMUX_PANE = "%2"
vim.env.XDG_STATE_HOME = state_home
write_route()
vim.fn.system = function(args)
	if args[2] == "show-option" and args[#args] == "@agent_source_pane" then
		return "%1\n"
	end
	if args[2] == "display-message" and args[#args] == "#{pid}" then
		return server_pid .. "\n"
	end
	if args[2] == "display-message" and args[#args] == "#{pane_id}" then
		return args[5] .. "\n"
	end
	if args[2] == "display-message" and args[#args] == "#{window_id}" then
		return args[5] == "%1" and source_window .. "\n" or "@1\n"
	end
	if args[2] == "display-message" and args[#args] == "#{pane_current_path}" then
		return root .. "\n"
	end
	return ""
end
vim.system = function(args)
	if args[2] == "verify-pane" then
		table.insert(verify_calls, { pane = args[3], project = args[4], session = args[5] })
		return {
			wait = function()
				return { code = pane_is_owned and 0 or 1, stdout = "", stderr = "" }
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
		callback(prompt_succeeds, prompt_succeeds and "" or "unavailable")
	end,
}

vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "human direction one" })
vim.cmd("write")
eq(#prompt_calls, 1, "changed human plan save notifies one OpenCode session")
eq(prompt_calls[1].session_id, "ses_live", "plan save targets the routed session")
eq(prompt_calls[1].dir, root, "plan save targets the routed project")
assert(prompt_calls[1].text:find("HUMAN PLAN SAVE", 1, true), "plan prompt is visibly labelled")
assert(prompt_calls[1].text:find("re-read", 1, true), "plan prompt tells the agent to re-read disk state")
assert(prompt_calls[1].text:find("planctl", 1, true), "plan prompt preserves planctl-owned agent writes")

vim.cmd("write")
eq(#prompt_calls, 1, "unchanged plan save does not notify twice")

prompt_succeeds = false
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "retry this direction" })
vim.cmd("write")
eq(#prompt_calls, 2, "failed plan notification is attempted")
prompt_succeeds = true
vim.cmd("write")
eq(#prompt_calls, 3, "failed plan notification remains retryable")

source_window = "@9"
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "wrong window" })
vim.cmd("write")
eq(#prompt_calls, 3, "cross-window route fails closed")
source_window = "@1"
write_route({ directory = root .. "/other" })
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "wrong project" })
vim.cmd("write")
eq(#prompt_calls, 3, "wrong-project route fails closed")

-- Pane IDs are reused across tmux server restarts, so a route from a previous
-- generation must never deliver a human save into an unrelated session.
write_route()
server_pid = "999"
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "stale generation" })
vim.cmd("write")
eq(#prompt_calls, 3, "stale-generation route fails closed")
server_pid = "855"

write_route({ serverPid = false })
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "legacy route" })
vim.cmd("write")
eq(#prompt_calls, 3, "route without a tmux generation fails closed")

-- Matching window and directory are not ownership: the shared verifier decides.
write_route()
pane_is_owned = false
verify_calls = {}
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "unowned pane" })
vim.cmd("write")
eq(#prompt_calls, 3, "unverified source pane fails closed")
eq(#verify_calls, 1, "route validation consults the shared verifier")
eq(verify_calls[1], { pane = "%1", project = root, session = "ses_live" }, "verifier receives the routed identity")

pane_is_owned = true
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "owned again" })
vim.cmd("write")
eq(#prompt_calls, 4, "a re-proven pane resumes notification")

assert(vim.fn.delete(route_path) == 0, "failed to remove plan route")
vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "missing route" })
vim.cmd("write")
eq(#prompt_calls, 4, "missing route fails closed")

vim.system = original_vim_system
vim.fn.system = original_system
vim.env.TMUX_PANE = original_tmux_pane
vim.env.XDG_STATE_HOME = original_state_home
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

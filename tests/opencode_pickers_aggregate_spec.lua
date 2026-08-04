package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local original_schedule = vim.schedule
local original_notify = vim.notify
local original_getcwd = vim.fn.getcwd
local original_tempname = vim.fn.tempname
local original_mkdir = vim.fn.mkdir
local original_writefile = vim.fn.writefile
local original_delete = vim.fn.delete
local original_executable = vim.fn.executable
local original_fs_find = vim.fs.find
local original_system = vim.system

vim.schedule = function(callback) callback() end
local notifications = {}
vim.notify = function(message, level)
	table.insert(notifications, { message = message, level = level })
end
vim.fn.getcwd = function() return "/repo/main" end
local temp_index = 0
vim.fn.tempname = function()
	temp_index = temp_index + 1
	return "/virtual/opencode-aggregate-" .. temp_index
end
vim.fn.mkdir = function() return 1 end
vim.fn.writefile = function() return 0 end
vim.fn.delete = function() return 0 end
vim.fn.executable = function() return 0 end
vim.fs.find = function() return { "/repo/main/.git" } end
local git_should_fail = false
vim.system = function(_, _, callback)
	if git_should_fail then
		callback({ code = 1, stdout = "", stderr = "failed" })
	else
		callback({ code = 0, stdout = "worktree /repo/main\n", stderr = "" })
	end
	return {}
end

package.loaded["config.opencode_http"] = {
	canonical = function(path) return path and path:gsub("/+$", "") end,
}

local picker_calls = {}
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, opts)
		table.insert(picker_calls, { entries = vim.deepcopy(entries), opts = opts })
	end,
}
package.loaded["fzf-lua.utils"] = { strip_ansi_coloring = function(value) return value end }

local catalog = {}
for index = 1, 10 do
	table.insert(catalog, {
		id = ("session-%02d"):format(index),
		title = ("Session %02d"):format(index),
		directory = "/repo/main",
		time = { updated = 100 - index },
	})
end
	table.insert(catalog, { id = "foreign", title = "Foreign", directory = "/other/project", time = { updated = 1 } })

local session_callbacks = {}
local message_callbacks = {}
local message_calls = {}
local immediate_messages = false
local api = {
	sessions = function(callback, opts)
		table.insert(session_callbacks, { callback = callback, opts = vim.deepcopy(opts) })
	end,
	messages = function(session_id, callback, opts)
		table.insert(message_calls, { id = session_id, opts = vim.deepcopy(opts) })
		if immediate_messages then
			callback({
				{
					info = { id = "message-" .. session_id, role = "assistant", time = { created = 1 } },
					parts = { { id = "part-" .. session_id, type = "reasoning", text = "reasoning " .. session_id } },
				},
			})
		else
			message_callbacks[session_id] = callback
		end
	end,
	notify_error = function(err) error(err or "unexpected OpenCode API error") end,
}
package.loaded["config.opencode_messages"] = api

local function response_for(session_id)
	return {
		{
			info = { id = "message-" .. session_id, role = "user", time = { created = 1 } },
			parts = { { id = "part-" .. session_id, type = "text", text = "payload " .. session_id } },
		},
	}
end

local opencode = dofile("lua/config/opencode_pickers.lua")
opencode.all_sessions("all", { session_scope = "local", query = "initial" })
session_callbacks[1].callback(vim.deepcopy(catalog))
eq(#message_calls, 8, "aggregate loading starts at most eight concurrent message requests")
eq(#picker_calls, 0, "aggregate picker waits for every filtered session")

message_callbacks["session-08"](response_for("session-08"))
eq(#message_calls, 9, "one completion starts exactly one queued request")
message_callbacks["session-01"](response_for("session-01"))
eq(#message_calls, 10, "a second completion starts the final queued request")

for _, index in ipairs({ 10, 3, 7, 2, 9, 4, 6 }) do
	local id = ("session-%02d"):format(index)
	message_callbacks[id](response_for(id))
end
message_callbacks["session-05"](nil, "failed")

eq(#picker_calls, 1, "aggregate picker opens after the bounded queue drains")
local aggregate_picker = picker_calls[1]
eq(#aggregate_picker.entries, 9, "failed sessions are omitted without dropping successful sessions")
assert(aggregate_picker.entries[1]:find("Session 01", 1, true), "aggregate results preserve catalog order")
assert(aggregate_picker.entries[#aggregate_picker.entries]:find("Session 10", 1, true), "late callbacks do not reorder results")
eq(aggregate_picker.opts.query, "initial", "aggregate picker receives its launch query")
assert(aggregate_picker.opts.actions["alt-g"], "aggregate picker exposes a location selector")
assert(aggregate_picker.opts.actions["alt-l"], "aggregate picker preserves transcript-plus-live Alt-l")
assert(aggregate_picker.opts.actions["alt-r"], "aggregate picker preserves reasoning Alt-r")
assert(notifications[#notifications].message:match("1 failed"), "partial aggregate failures are summarized")
for _, call in ipairs(message_calls) do
	eq(call.opts.dir, "/repo/main", "aggregate message requests carry each session directory")
end

immediate_messages = true
aggregate_picker.opts.actions["alt-g"]({}, { last_query = "typed", __call_opts = { query = "stale" } })
local location_picker = picker_calls[2]
eq(location_picker.opts.prompt, "OpenCode Location> ", "Alt-g opens a dedicated location selector")
git_should_fail = true
location_picker.opts.actions.enter({ "repo        Git sessions" })
eq(#session_callbacks, 2, "choosing a location relaunches aggregate search")
session_callbacks[2].callback(vim.deepcopy(catalog))
local retained_picker = picker_calls[3]
assert(retained_picker.opts.prompt:find("Local", 1, true), "failed Git discovery retains the prior aggregate scope")
eq(retained_picker.opts.query, "typed", "failed Git discovery retains the parent's live query")
assert(notifications[#notifications].message:match("not widened to Global"), "failed Git discovery explicitly states that it did not widen")

git_should_fail = false
retained_picker.opts.actions["alt-g"]({}, { last_query = "typed", __call_opts = { query = "stale" } })
location_picker = picker_calls[4]
location_picker.opts.actions.enter({ "global      Global sessions" })
eq(#session_callbacks, 3, "choosing Global relaunches aggregate search")
session_callbacks[3].callback(vim.deepcopy(catalog))
local global_picker = picker_calls[5]
eq(#global_picker.entries, 11, "Global aggregate search includes foreign sessions")
eq(global_picker.opts.query, "typed", "location relaunch preserves the parent's live query")
assert(global_picker.opts.prompt:find("Global", 1, true), "aggregate prompt shows active Global scope")

picker_calls = {}
session_callbacks = {}
message_calls = {}
immediate_messages = true
opencode.all_sessions("all", { session_scope = "local", query = "old" })
opencode.all_sessions("all", { session_scope = "local", query = "new" })
eq(#session_callbacks, 2, "two aggregate invocations may overlap at the catalog boundary")
session_callbacks[2].callback({ catalog[1] })
session_callbacks[1].callback({ catalog[2] })
eq(#picker_calls, 1, "a superseded aggregate invocation never opens a stale picker")
eq(picker_calls[1].opts.query, "new", "only the newest aggregate route opens")

picker_calls = {}
session_callbacks = {}
message_calls = {}
opencode.all_sessions("all", { session_scope = "local" })
session_callbacks[1].callback({ catalog[#catalog] })
eq(#message_calls, 0, "empty filtered scopes never fetch messages")
eq(picker_calls[1].entries, {}, "empty aggregate scopes remain open")
assert(picker_calls[1].opts.actions["alt-g"], "empty aggregate scopes can widen through the location selector")

vim.schedule = original_schedule
vim.notify = original_notify
vim.fn.getcwd = original_getcwd
vim.fn.tempname = original_tempname
vim.fn.mkdir = original_mkdir
vim.fn.writefile = original_writefile
vim.fn.delete = original_delete
vim.fn.executable = original_executable
vim.fs.find = original_fs_find
vim.system = original_system

print("PASS OpenCode aggregate picker bounds concurrency, preserves order, and suppresses stale routes")

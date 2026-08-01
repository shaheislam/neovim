package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local scheduled = {}
local original_schedule = vim.schedule
vim.schedule = function(callback)
	table.insert(scheduled, callback)
end

local pickers = {}
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, opts)
		table.insert(pickers, { entries = entries, opts = opts })
	end,
}
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value) return value end,
}

local session = {
	id = "session-1",
	title = "Prompt picker work",
	agent = "build",
	time = { created = 1000, updated = 2000 },
}
local messages = {
	{
		info = { id = "message-1", role = "user", time = { created = 3000 } },
		parts = {
			{ id = "part-1", type = "text", text = "Implement the picker lifecycle" },
		},
	},
}
package.loaded["config.opencode_messages"] = {
	latest_session = function(callback) callback(session) end,
	sessions = function(callback) callback({ session }) end,
	messages = function(_, callback) callback(messages) end,
	notify_error = function(err) error(err or "unexpected OpenCode API error") end,
}

local inserted = {}
local restored = 0
local prompt = {
	owner = {
		insert = function(text) table.insert(inserted, text) end,
		restore = function() restored = restored + 1 end,
	},
}

local opencode = require("config.opencode_pickers")
opencode.all({ prompt = prompt })
eq(#pickers, 1, "prompt mode opens the message picker")
local message_picker = pickers[1]
assert(message_picker.opts.actions.enter, "prompt message picker exposes insertion Enter")
assert(message_picker.opts.actions["alt-s"], "prompt message picker retains safe scope navigation")
assert(message_picker.opts.actions["ctrl-s"], "prompt message picker retains safe session navigation")
assert(not message_picker.opts.actions.default, "prompt message picker removes its normal open action")
assert(not message_picker.opts.actions["ctrl-f"], "prompt message picker removes forking actions")
assert(not message_picker.opts.actions["ctrl-w"], "prompt message picker removes worktree actions")

message_picker.opts.winopts.on_close()
eq(#scheduled, 1, "message picker defers prompt restoration until action dispatch")
message_picker.opts.actions.enter({ message_picker.entries[1] })
eq(#inserted, 1, "message Enter inserts into the prompt owner")
assert(inserted[1]:match("Implement the picker lifecycle"), "inserted text contains the selected message payload")
assert(not inserted[1]:find("\n", 1, true), "message payload is flattened for prompt insertion")
assert(inserted[1]:match(" $"), "message payload ends in one continuation space")
scheduled[1]()
eq(restored, 0, "selection suppresses the deferred cancellation restore")

pickers = {}
scheduled = {}
opencode.sessions("all", { prompt = prompt })
eq(#pickers, 1, "prompt mode opens the session picker")
local session_picker = pickers[1]
eq(vim.tbl_keys(session_picker.opts.actions), { "enter" }, "prompt session picker exposes navigation-only Enter")
session_picker.opts.winopts.on_close()
session_picker.opts.actions.enter({ session_picker.entries[1] })
eq(#scheduled, 2, "session transition queues close restoration before the next picker")
scheduled[1]()
eq(restored, 0, "a session-to-message transition suppresses intermediate restoration")
scheduled[2]()
eq(#pickers, 2, "selecting a session opens its message picker")
local nested_picker = pickers[2]
nested_picker.opts.winopts.on_close()
scheduled[3]()
eq(restored, 1, "cancelling the terminal nested picker restores the prompt exactly once")

vim.schedule = original_schedule

print("PASS OpenCode prompt pickers insert payloads and preserve nested lifecycle")

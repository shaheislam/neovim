package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level, opts)
	table.insert(notifications, { message = message, level = level, opts = opts })
end

local prompt = dofile("lua/config/opencode_prompt.lua")

prompt.set_sink(function(_, opts)
	opts.on_success()
end)
prompt.append("picker selection", { notify_success = false })
eq(notifications, {}, "picker delivery can suppress its success notification")

prompt.append("regular send")
eq(#notifications, 1, "successful delivery still notifies by default")
eq(notifications[1].message, "Sent text to OpenCode", "default success notification is unchanged")

notifications = {}
prompt.set_sink(nil)
prompt.append("picker selection", { notify_success = false })
eq(#notifications, 1, "suppressing success notifications does not hide delivery failures")
eq(notifications[1].level, vim.log.levels.ERROR, "delivery failure keeps its error level")

vim.notify = original_notify

print("PASS OpenCode prompt supports success-only notification suppression")

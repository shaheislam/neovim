package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

-- Minimal Promise compatible with opencode.nvim's own promise.lua: enough
-- :next()/:catch() semantics to prove the patched Server methods resolve and
-- reject exactly like the original HTTP-backed implementations did.
local function promise_new(executor)
	local promise = { status = "pending", next_callbacks = {}, catch_callbacks = {} }

	local function resolve(value)
		if promise.status ~= "pending" then
			return
		end
		promise.status = "fulfilled"
		promise.value = value
		for _, callback in ipairs(promise.next_callbacks) do
			callback(value)
		end
	end

	local function reject(reason)
		if promise.status ~= "pending" then
			return
		end
		promise.status = "rejected"
		promise.value = reason
		for _, callback in ipairs(promise.catch_callbacks) do
			callback(reason)
		end
	end

	function promise:next(callback)
		if self.status == "fulfilled" then
			callback(self.value)
		elseif self.status == "pending" then
			table.insert(self.next_callbacks, callback)
		end
		return self
	end

	function promise:catch(callback)
		if self.status == "rejected" then
			callback(self.value)
		elseif self.status == "pending" then
			table.insert(self.catch_callbacks, callback)
		end
		return self
	end

	executor(resolve, reject)
	return promise
end

local Promise = { new = promise_new }

package.loaded["opencode.promise"] = Promise
package.loaded["opencode.promise.ui"] = {}
package.loaded["nui.input"] = function()
	return {
		map = function() end,
		mount = function() end,
		unmount = function() end,
	}
end

local original_command_calls = {}
package.loaded["opencode.server"] = {
	tui_append_prompt = function(_, text)
		return promise_new(function(resolve)
			resolve({ original = true, text = text })
		end)
	end,
	tui_execute_command = function(_, command)
		table.insert(original_command_calls, command)
		return promise_new(function(resolve)
			resolve({ original = true, command = command })
		end)
	end,
	disconnect = function(_) end,
}

package.loaded["config.opencode_prompt"] = {
	append = function(text, opts)
		package.loaded["config.opencode_prompt"]._last_append = { text = text, opts = opts }
	end,
	submit = function(opts)
		package.loaded["config.opencode_prompt"]._last_submit = { opts = opts }
	end,
}

-- Keep a sentinel for the removed focus API so a future send-driven visibility
-- regression is observable even though the production adapter no longer
-- exports it. The remaining methods avoid real ToggleTerm setup in this test.
local terminal_visibility_calls = {}
package.loaded["config.opencode_terminal"] = {
	setup = function() end,
	send = function() end,
	focus = function(dir)
		table.insert(terminal_visibility_calls, { action = "focus", dir = dir })
	end,
}

local plugin_specs = dofile("lua/plugins/opencode.lua")
plugin_specs[1].config()

local server = package.loaded["opencode.server"]

-- tui_append_prompt now routes through the local composer facade, silently
-- (no double-notify) and without HTTP clipboard fallback, and resolves the
-- Promise only once the facade reports success.
local append_resolved, append_rejected
server:tui_append_prompt("hello world"):next(function(value)
	append_resolved = value
end):catch(function()
	append_rejected = true
end)

local facade = package.loaded["config.opencode_prompt"]
eq(
	#terminal_visibility_calls,
	0,
	"tui_append_prompt does not reveal or focus the terminal while dispatching"
)
assert(facade._last_append, "tui_append_prompt delegates to config.opencode_prompt.append")
eq(facade._last_append.text, "hello world", "the exact prompt text is forwarded")
eq(facade._last_append.opts.fallback_clipboard, false, "no clipboard fallback for opencode.nvim-owned prompts")
eq(facade._last_append.opts.silent, true, "delivery is silent; opencode.nvim's own catch chains surface errors")
assert(not append_resolved and not append_rejected, "the Promise stays pending until the facade calls back")

facade._last_append.opts.on_success()
eq(append_resolved, nil, "on_success resolves with no value")
assert(not append_rejected, "a successful append never rejects")

print("PASS tui_append_prompt routes through the local composer facade")

-- tui_execute_command("prompt.submit") is intercepted the same way...
local submit_resolved, submit_rejected
server:tui_execute_command("prompt.submit"):next(function()
	submit_resolved = true
end):catch(function()
	submit_rejected = true
end)

assert(facade._last_submit, "prompt.submit delegates to config.opencode_prompt.submit")
eq(facade._last_submit.opts.fallback_clipboard, false, "submit never falls back to the clipboard")
eq(#original_command_calls, 0, "prompt.submit never reaches the original broadcast implementation")
eq(#terminal_visibility_calls, 0, "prompt.submit does not reveal or focus the terminal")

facade._last_submit.opts.on_success()
assert(submit_resolved, "a successful submit resolves the Promise")
assert(not submit_rejected, "a successful submit never rejects")

print("PASS prompt.submit is intercepted and never broadcasts")

-- ...but every other TUI command still reaches the original implementation.
local other_resolved
server:tui_execute_command("session.new"):next(function(value)
	other_resolved = value
end)
eq(original_command_calls, { "session.new" }, "non-prompt commands still reach the original broadcast implementation")
eq(other_resolved, { original = true, command = "session.new" }, "the original command result is preserved")

print("PASS non-prompt TUI commands are left untouched")

-- Failure propagates through the Promise instead of being swallowed by the
-- facade's own notify/clipboard fallback (opencode.nvim's own catch chains,
-- e.g. context:resume(), still see the rejection).
local failed_resolved, failed_reason
server:tui_append_prompt("will fail"):next(function()
	failed_resolved = true
end):catch(function(reason)
	failed_reason = reason
end)
facade._last_append.opts.on_error("terminal is gone")
assert(not failed_resolved, "a failed append never resolves")
eq(failed_reason, "terminal is gone", "the failure reason is propagated to the caller's catch chain")
eq(
	#terminal_visibility_calls,
	0,
	"a failed append still does not reveal or focus the terminal"
)

print("PASS append failures reject the Promise instead of being swallowed")

print("PASS opencode.nvim-owned prompt delivery (aoB/aoV/aoQ, go/goo, action-picker prompts) no longer broadcasts")

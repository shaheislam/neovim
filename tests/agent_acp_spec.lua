package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
local calls, chats, connections = {}, {}, {}
local fail_load = false
local auth_result = {}
local auth_methods = { { id = "fixture-provider" }, { id = "hermes-setup", type = "terminal" } }
package.loaded.lazy = { load = function() end }
package.loaded["codecompanion.adapters"] = {
	extend = function(_, opts)
		return opts
	end,
}
package.loaded["codecompanion.adapters.acp"] = {
	extend = function(adapter)
		return adapter
	end,
}
package.loaded["codecompanion.adapters.acp.helpers"] = {
	form_messages = function(_, messages)
		return messages
	end,
}
package.loaded["codecompanion.utils.context"] = {
	get = function()
		return {}
	end,
}
package.loaded["codecompanion.interactions.chat.acp.commands"] = { link_buffer_to_session = function() end }
package.loaded["codecompanion.acp"] = {
	new = function(opts)
		local conn = { adapter = opts.adapter, _state = { handle = {} }, model = "claude-opus-test" }
		function conn:get_models()
			return {
				currentModelId = self.model,
				availableModels = {
					{ modelId = "claude-opus-test", name = "Opus" },
					{ modelId = "gpt-6-sol", name = "Codex" },
				},
			}
		end
		function conn:set_model(value)
			if value == "opus" then
				value = "claude-opus-test"
			end
			if value ~= "claude-opus-test" and value ~= "gpt-6-sol" then
				return false
			end
			self.model = value
			return true
		end
		function conn:handle_available_commands_update() end
		function conn:start_agent_process()
			return true
		end
		function conn:_initialize()
			self._agent_info = { authMethods = auth_methods }
			return true
		end
		function conn:is_ready()
			return not self.closed
		end
		function conn:can_load_session()
			return true
		end
		function conn:send_rpc_request(method, params)
			calls[#calls + 1] = { method = method, params = params }
			if method == "authenticate" then
				assert(not self._authenticated, "Hermes must acknowledge credentials before becoming authenticated")
				return auth_result
			end
			if method == "session/load" and fail_load then
				if fail_load == true then
					return nil
				end
				return fail_load
			end
			local id = method == "session/new" and "exact-session-" .. #connections or params.sessionId
			self:handle_available_commands_update(id, { { name = "goal" } })
			return method == "session/new" and { sessionId = id }
				or { _meta = { hermes = { sessionProvenance = { acpSessionId = id } } } }
		end
		function conn:disconnect()
			self.closed = true
		end
		connections[#connections + 1] = conn
		return conn
	end,
}
package.loaded["codecompanion.interactions.chat"] = {
	new = function(opts)
		local chat = { bufnr = vim.api.nvim_create_buf(false, true), messages = {}, opts = opts }
		function chat:add_message(message)
			self.messages[#self.messages + 1] = message
		end
		function chat:add_buf_message() end
		function chat:submit()
			self.current_request = {}
			self.opts.callbacks.on_submitted(self)
		end
		function chat:close()
			self.acp_connection:disconnect()
			self.opts.callbacks.on_closed(self)
		end
		chats[#chats + 1] = chat
		return chat
	end,
	open = function() end,
}
local acp = require("config.agent_acp")
local owner = assert(acp.open("claude", root, { hidden = true, model = "opus" }))
assert(owner.connection.model == "claude-opus-test", "native Claude aliases resolve to verified advertised models")
assert(
	not acp.open("claude", root, { hidden = true, model = "missing" }),
	"an existing owner cannot silently ignore a rejected model"
)
local route = assert(acp.capture(root))
assert(acp.commands(route, 0)[1].name == "goal", "command publication during session opening is retained")
owner.connection:handle_available_commands_update(owner.sessionID, {})
assert(#acp.commands(route, 0) == 0, "an observed empty command list replaces the old list")
assert(route.sessionID == owner.connection.session_id and route.harness == "claude")
assert(calls[1].params.cwd == vim.uv.fs_realpath(root), "session creation pins the canonical worktree")
local receipts = {}
assert(acp.submit(route, "first", function(state)
	receipts[#receipts + 1] = state
end))
assert(acp.submit(route, "second", function(state)
	receipts[#receipts + 1] = state
end))
assert(
	#owner.chat.messages == 1 and receipts[#receipts] == "queued",
	"busy review comments queue instead of disappearing"
)
owner.chat.current_request = nil
owner.chat.opts.callbacks.on_completed(owner.chat, {})
assert(
	vim.wait(1000, function()
		return #owner.chat.messages == 2
	end),
	"completion drains the exact session's queue"
)
owner.chat.current_request = nil
owner.chat.opts.callbacks.on_completed(owner.chat, {})
assert(acp.close(root), "idle owned chat closes")
assert(not acp.resolve(route) and not acp.submit(route, "stale"), "retired provenance cannot send")
local restored = assert(acp.open("claude", root, { hidden = true }))
assert(calls[#calls].method == "session/load" and calls[#calls].params.sessionId == route.sessionID)
assert(restored.generation ~= route.generation and not acp.resolve(route), "reopening never revives old ownership")
assert(acp.close(root))
fail_load = true
local count = #calls
assert(
	not acp.open("claude", root, { hidden = true }),
	"failed exact resume does not create a replacement conversation"
)
assert(#calls == count + 1 and calls[#calls].method == "session/load", "no session/new fallback")
fail_load = false
local hermes = assert(acp.open("hermes", root, { hidden = true }))
assert(vim.deep_equal(hermes.connection.adapter.commands.default, { "hermes", "acp" }))
assert(hermes.connection.adapter.type == "acp" and hermes.connection.adapter.env.HERMES_HOME())
assert(calls[#calls - 1].method == "authenticate" and calls[#calls - 1].params.methodId == "fixture-provider")
assert(hermes.connection._authenticated and acp.close(root))
local hermes_restored = assert(acp.open("hermes", root, { hidden = true }))
assert(hermes_restored.sessionID == hermes.sessionID and acp.close(root))
for _, invalid in ipairs({
	vim.NIL,
	false,
	"malformed",
	{},
	{ _meta = { hermes = { sessionProvenance = { acpSessionId = "wrong" } } } },
}) do
	fail_load = invalid == false and true or invalid
	count = #calls
	assert(not acp.open("hermes", root, { hidden = true }), "null or malformed exact loads must fail closed")
	assert(#calls == count + 2 and calls[#calls].method == "session/load", "Hermes never falls back to new/resume")
end
fail_load, auth_result = false, vim.NIL
count = #calls
assert(not acp.open("hermes", root, { hidden = true }), "missing credentials cannot launch a Hermes session")
assert(#calls == count + 1 and calls[#calls].method == "authenticate")
auth_result, auth_methods = {}, { { id = "hermes-setup", type = "terminal" } }
count = #calls
assert(not acp.open("hermes", root, { hidden = true }), "terminal setup alone is not evidence of provider credentials")
assert(#calls == count, "unconfigured Hermes cannot authenticate or open a session")
vim.fn.delete(root, "rf")
print("PASS ACP ownership, busy queue, retirement, and fail-closed exact restoration")

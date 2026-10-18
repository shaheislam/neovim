-- Owned ACP chats. Never use CodeCompanion's fallback from failed load to new.
local M = {}
local owners, opening = {}, {}
local packages = {
	hermes = true,
	claude = { "@agentclientprotocol/claude-agent-acp@0.93.0", "claude-agent-acp", "claude_code" },
	codex = { "@agentclientprotocol/codex-acp@2.2.2", "codex-acp", "codex" },
}

local function canonical(root)
	return vim.uv.fs_realpath(root) or root
end

local function session_file(root, harness)
	local result = vim.system({ "git", "-C", root, "rev-parse", "--absolute-git-dir" }, { text = true }):wait()
	assert(result.code == 0, "ACP sessions require a Git worktree")
	return vim.trim(result.stdout) .. "/dotfiles-agent-" .. harness .. ".json"
end

local function alive(owner)
	return owner
		and not owner.closed
		and owner.connection:is_ready()
		and owner.chat.acp_connection == owner.connection
		and owner.connection.session_id == owner.sessionID
		and vim.api.nvim_buf_is_valid(owner.chat.bufnr)
end

function M.capture(root)
	local owner = owners[canonical(root)]
	if alive(owner) then
		return {
			kind = "acp",
			project = owner.root,
			harness = owner.harness,
			sessionID = owner.sessionID,
			generation = owner.generation,
		}
	end
end

function M.resolve(route)
	if type(route) ~= "table" or route.kind ~= "acp" then
		return nil
	end
	local owner = owners[route.project]
	return alive(owner) and vim.deep_equal(M.capture(route.project), route) and owner or nil
end

local function receipt(request, state, err)
	if request and request.state ~= state then
		request.state = state
		if request.callback then
			request.callback(state, err)
		end
	end
end

local function drain(owner)
	if
		not alive(owner)
		or owner.stopping
		or owner.turn_active
		or owner.chat.current_request
		or owner.inflight
		or #owner.queue == 0
	then
		return
	end
	local request = table.remove(owner.queue, 1)
	owner.inflight = request
	owner.chat:add_message({ role = "user", content = request.text })
	owner.chat:add_buf_message({ role = "user", content = request.text })
	local ok, err = pcall(owner.chat.submit, owner.chat, { auto_submit = true })
	if not ok then
		owner.inflight = nil
		receipt(request, "uncertain", tostring(err))
	end
end

function M.submit(route, text, callback)
	local owner = M.resolve(route)
	if not owner or owner.stopping then
		return false
	end
	-- Retrying while a request is queued/in flight must not submit it twice.
	if owner.inflight and owner.inflight.text == text then
		return true
	end
	for _, queued in ipairs(owner.queue) do
		if queued.text == text then
			return true
		end
	end
	local request = { text = text, callback = callback }
	owner.queue[#owner.queue + 1] = request
	receipt(request, "queued")
	drain(owner)
	return true
end

function M.busy(root)
	local owner = owners[canonical(root)]
	return alive(owner)
			and (owner.turn_active or owner.chat.current_request ~= nil or owner.inflight ~= nil or #owner.queue > 0)
		or false
end

function M.cancel(root)
	local owner = owners[canonical(root)]
	if not alive(owner) then
		return false
	end
	owner.stopping = true
	for _, queued in ipairs(owner.queue) do
		receipt(queued, "blocked", "Harness switch requested")
	end
	owner.queue = {}
	owner.connection:send_notification("session/cancel", { sessionId = owner.sessionID })
	return true
end

function M.close(root)
	local owner = owners[canonical(root)]
	if not owner then
		return true
	end
	if M.busy(root) then
		return false
	end
	owner.closed = true
	owner.chat:close()
	owners[owner.root] = nil
	return true
end

function M.focus(owner)
	require("codecompanion.interactions.chat").open({ ui = owner.chat.ui })
end

local function select_model(connection, harness, requested)
	if not requested or requested == "" then
		return
	end
	local models = connection.get_models and connection:get_models()
	assert(models, "The adapter did not advertise model selection")
	local aliases = harness == "claude" and vim.tbl_contains({ "opus", "sonnet", "haiku" }, requested)
	local function advertised(id)
		for _, model in ipairs(models.availableModels or {}) do
			if model.modelId == id then
				return true
			end
		end
		return false
	end
	assert(aliases or advertised(requested), "Requested model is unavailable: " .. requested)
	assert(connection:set_model(requested), "The adapter rejected model: " .. requested)
	local selected = connection:get_models()
	assert(selected and advertised(selected.currentModelId), "The adapter did not confirm its selected model")
	assert(
		selected.currentModelId == requested or (aliases and selected.currentModelId:lower():find(requested, 1, true)),
		"The adapter selected a different model"
	)
end

function M.commands(provenance, timeout)
	local owner = M.resolve(provenance)
	if not owner then
		return nil, "The ACP owner is no longer live"
	end
	local observed = vim.wait(timeout or 5000, function()
		return not alive(owner) or owner.command_updates[owner.sessionID] ~= nil
	end, 20)
	if not observed or not alive(owner) then
		return nil, "The adapter has not published its commands"
	end
	return owner.command_updates[owner.sessionID]
end

function M.open(harness, root, opts)
	opts = opts or {}
	assert(packages[harness], "unsupported ACP harness")
	root = canonical(root)
	local existing = owners[root]
	if alive(existing) then
		if existing.harness ~= harness then
			return nil, "Use :AgentSwitch to change the active harness"
		end
		if opts.new then
			if not M.close(root) then
				return nil, "Finish the current turn before creating a new session"
			end
		else
			local selected, err = pcall(select_model, existing.connection, harness, opts.model)
			if not selected then
				return nil, err
			end
			if not opts.hidden then
				M.focus(existing)
			end
			return existing
		end
	end
	if opening[root] then
		return nil, "An ACP session is already opening for this worktree"
	end
	opening[root] = true
	local connection
	local ok, result = pcall(function()
		require("lazy").load({ plugins = { "codecompanion.nvim" } })
		local spec = packages[harness]
		local adapter
		if harness == "hermes" then
			adapter = require("codecompanion.adapters.acp").extend({
				name = "hermes",
				formatted_name = "Hermes",
				type = "acp",
				roles = { llm = "assistant", user = "user" },
				commands = { default = { "hermes", "acp" } },
				defaults = { timeout = 90000, mcpServers = {} },
				env = {
					HERMES_HOME = function()
						return vim.env.HERMES_HOME or vim.fn.expand("~/.hermes")
					end,
				},
				parameters = {
					protocolVersion = 1,
					clientCapabilities = { fs = { readTextFile = true, writeTextFile = true } },
					clientInfo = { name = "CodeCompanion.nvim", version = "1.0.0" },
				},
				handlers = {
					setup = function()
						return true
					end,
					form_messages = function(self, messages, capabilities)
						return require("codecompanion.adapters.acp.helpers").form_messages(self, messages, capabilities)
					end,
				},
			})
		else
			adapter = require("codecompanion.adapters").extend(spec[3], {
				commands = { default = { "bunx", "--package", spec[1], spec[2] } },
				defaults = { timeout = 90000, auth_method = harness == "codex" and "chat-gpt" or nil },
				-- Missing string env references become literal tokens in the upstream client.
				env = {
					CLAUDE_CODE_OAUTH_TOKEN = function()
						return vim.env.CLAUDE_CODE_OAUTH_TOKEN
					end,
					OPENAI_API_KEY = function()
						return vim.env.OPENAI_API_KEY
					end,
				},
				handlers = {
					auth = function()
						return true
					end,
				}, -- Native stored login; no implicit browser flow.
			})
		end
		connection = require("codecompanion.acp").new({
			adapter = adapter,
			opts = {
				job = function(command, job_opts, callback)
					job_opts.cwd = root
					return vim.system(command, job_opts, callback)
				end,
			},
		})
		assert(connection:start_agent_process() and connection:_initialize(), "ACP adapter initialization failed")
		if harness == "hermes" then
			-- This only acknowledges existing credentials; terminal setup stays out of band.
			assert(
				type(connection:send_rpc_request("authenticate", { methodId = "hermes-setup" })) == "table",
				"Hermes credentials unavailable; run hermes setup in a terminal first"
			)
		end
		connection._authenticated = true
		local command_updates = {}
		local register_commands = connection.handle_available_commands_update
		if register_commands then
			connection.handle_available_commands_update = function(self, id, commands)
				command_updates[id] = commands
				return register_commands(self, id, commands)
			end
		end
		local file = session_file(root, harness)
		local saved
		if not opts.new and vim.fn.filereadable(file) == 1 then
			saved = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
			assert(
				saved.project == root and type(saved.sessionID) == "string" and saved.sessionID ~= "",
				"Invalid saved ACP session"
			)
		end
		local args = { cwd = root, mcpServers = {} }
		local replay = {}
		connection._loading_session = saved ~= nil
		connection._on_session_update = function(update)
			replay[#replay + 1] = update
		end
		local session
		if saved then
			assert(
				connection:can_load_session(),
				"This adapter cannot resume the saved session; use :AgentOpen! for an explicit new session"
			)
			args.sessionId, connection.session_id = saved.sessionID, saved.sessionID
			session = connection:send_rpc_request("session/load", args)
			assert(
				type(session) == "table",
				"Exact ACP resume failed; nothing replaced. Use :AgentOpen! for an explicit new session"
			)
		else
			session = connection:send_rpc_request("session/new", args)
			assert(
				type(session) == "table" and type(session.sessionId) == "string" and session.sessionId ~= "",
				"ACP session creation failed; check the native harness login"
			)
			connection.session_id = session.sessionId
		end
		connection._loading_session, connection._on_session_update = nil, nil
		if session.configOptions then
			connection:_apply_config_options(session.configOptions)
		end
		select_model(connection, harness, opts.model)
		local owner = {
			root = root,
			harness = harness,
			connection = connection,
			sessionID = connection.session_id,
			generation = tostring(vim.uv.hrtime()),
			queue = {},
			command_updates = command_updates,
		}
		local function retire()
			owner.closed = true
			receipt(owner.inflight, "uncertain", "Agent disconnected; inspect its conversation before retrying")
			owner.inflight = nil
			for _, queued in ipairs(owner.queue) do
				receipt(queued, "blocked", "Agent owner retired")
			end
			owner.queue = {}
		end
		owner.chat = require("codecompanion.interactions.chat").new({
			adapter = adapter,
			hidden = true,
			title = harness .. " · " .. vim.fn.fnamemodify(root, ":t"),
			buffer_context = require("codecompanion.utils.context").get(vim.api.nvim_get_current_buf()),
			callbacks = {
				on_submitted = function()
					owner.turn_active = true
					receipt(owner.inflight, "submitted")
				end,
				on_completed = function(_, info)
					if not owner.protocol_tracking then
						owner.turn_active = false
					end
					local state = info.error and "failed"
						or (owner.stop_reason and owner.stop_reason ~= "end_turn") and "interrupted"
						or "turn_ended"
					receipt(owner.inflight, state, info.error or owner.stop_reason)
					owner.inflight = nil
					vim.schedule(function()
						drain(owner)
					end)
				end,
				on_cancelled = function()
					receipt(owner.inflight, "uncertain", "Turn cancelled; inspect before retrying")
				end,
				on_closed = retire,
			},
		})
		assert(owner.chat, "Could not create the ACP chat")
		owner.chat.acp_connection, connection.chat = connection, owner.chat
		local incoming = connection.handle_incoming_request_or_notification
		if incoming then
			connection.handle_incoming_request_or_notification = function(self, message)
				local params = message.params or {}
				if params.sessionId == owner.sessionID then
					if message.method == "session/request_permission" then
						receipt(owner.inflight, "awaiting_permission")
					elseif message.method == "session/update" then
						receipt(owner.inflight, "working")
					end
				end
				return incoming(self, message)
			end
		end
		local session_prompt = connection.session_prompt
		if session_prompt then
			owner.protocol_tracking = true
			connection.session_prompt = function(self, ...)
				local prompt = session_prompt(self, ...)
				local done, failed = prompt.handle_done, prompt.handle_error
				prompt.handle_done = function(builder, reason)
					owner.turn_active, owner.stop_reason = false, reason
					return done(builder, reason)
				end
				prompt.handle_error = function(builder, err)
					owner.turn_active = false
					return failed(builder, err)
				end
				return prompt
			end
		end
		-- An owned chat may never silently reconnect to a different conversation.
		connection.connect_and_authenticate = function(self)
			return self:is_ready() and self or nil
		end
		connection._establish_session = function()
			return false
		end
		local exited = connection.handle_process_exit
		if exited then
			connection.handle_process_exit = function(self, ...)
				retire()
				return exited(self, ...)
			end
		end
		require("codecompanion.interactions.chat.acp.commands").link_buffer_to_session(
			owner.chat.bufnr,
			owner.sessionID
		)
		for _, update in ipairs(replay) do
			local role = update.sessionUpdate == "user_message_chunk" and "user"
				or update.sessionUpdate == "agent_message_chunk" and "llm"
				or nil
			if role and update.content and update.content.text then
				owner.chat:add_message({ role = role, content = update.content.text }, { _meta = { sent = true } })
				owner.chat:add_buf_message({ role = role, content = update.content.text })
			end
		end
		local tmp = file .. "." .. vim.fn.getpid()
		assert(vim.fn.writefile({ vim.json.encode({ project = root, sessionID = owner.sessionID }) }, tmp) == 0)
		assert(vim.uv.fs_rename(tmp, file))
		owners[root] = owner
		require("config.hotreload").watch_directory(root)
		if not opts.hidden then
			M.focus(owner)
		end
		return owner
	end)
	opening[root] = nil
	if not ok then
		if connection then
			connection:disconnect()
		end
		vim.notify(tostring(result), vim.log.levels.ERROR, { title = "Agent session" })
		return nil, tostring(result)
	end
	return result
end

return M

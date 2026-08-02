-- Publish exact opencode.nvim session state to tmux through the dotfiles
-- pane-state protocol. The shared OpenCode server emits every session's
-- events, so only sessions bound by config.opencode_handoff may contribute.

local M = {}

local MAX_CACHED_SESSIONS = 256
local AUGROUP = "opencode_status_bridge"

local session_cache = {}
local cache_size = 0
local sequence = 0
local server_connected = false

local function default_helper_path()
	local configured = vim.env.OPENCODE_TMUX_STATE_HELPER
	if configured and configured ~= "" then
		return vim.fn.executable(configured) == 1 and configured or nil
	end

	local path = vim.fn.exepath("tmux-agent-state")
	return path ~= "" and path or nil
end

local defaults = {
	helper_path = default_helper_path,
	getpid = vim.fn.getpid,
	owner_nonce = function()
		local uv = vim.uv or vim.loop
		return tostring(uv.hrtime())
	end,
	jobstart = vim.fn.jobstart,
	system = vim.fn.system,
	jobstop = vim.fn.jobstop,
	jobwait = vim.fn.jobwait,
}

local hooks = vim.tbl_extend("force", {}, defaults)

local function next_sequence()
	sequence = sequence + 1
	return sequence
end

local function normalize_status(status_type)
	if status_type == "idle" then
		return "idle"
	end
	if type(status_type) == "string" and status_type ~= "" then
		return "busy"
	end
	return nil
end

local function prune_cache()
	while cache_size > MAX_CACHED_SESSIONS do
		local oldest_id
		local oldest_sequence = math.huge
		for session_id, entry in pairs(session_cache) do
			if (entry.updated_sequence or 0) < oldest_sequence then
				oldest_id = session_id
				oldest_sequence = entry.updated_sequence or 0
			end
		end
		if not oldest_id then
			return
		end
		session_cache[oldest_id] = nil
		cache_size = cache_size - 1
	end
end

local function cache_entry(session_id)
	if type(session_id) ~= "string" or session_id == "" then
		return nil
	end

	local entry = session_cache[session_id]
	if not entry then
		entry = {}
		session_cache[session_id] = entry
		cache_size = cache_size + 1
	end
	entry.updated_sequence = next_sequence()
	prune_cache()
	return entry
end

local function cache_status(session_id, status_type)
	local normalized = normalize_status(status_type)
	if not normalized then
		return
	end

	local entry = cache_entry(session_id)
	if not entry then
		return
	end
	entry.status = normalized
	entry.status_sequence = entry.updated_sequence
end

local function cache_model(session_id, provider_id, model_id)
	local entry = cache_entry(session_id)
	if not entry then
		return
	end
	if type(provider_id) == "string" then
		entry.providerID = provider_id
	end
	if type(model_id) == "string" then
		entry.modelID = model_id
	end
end

local function drop_session(session_id)
	if type(session_id) == "string" and session_cache[session_id] then
		session_cache[session_id] = nil
		cache_size = cache_size - 1
	end
end

local function clear_cache()
	session_cache = {}
	cache_size = 0
end

local function tmux_pane()
	local pane = vim.env.TMUX_PANE
	if type(pane) ~= "string" or not pane:match("^%%%d+$") then
		return nil
	end
	return pane
end

local function helper_path()
	local ok, path = pcall(hooks.helper_path)
	if not ok or type(path) ~= "string" or path == "" then
		return nil
	end
	return path
end

local function owner_token()
	if M._owner then
		return M._owner
	end

	local pid = tonumber(hooks.getpid())
	if not pid or pid <= 0 then
		return nil
	end
	local nonce = tostring(hooks.owner_nonce() or ""):gsub("[^%w_.-]", "")
	if nonce == "" then
		nonce = tostring(pid)
	end
	M._owner = string.format("nvim:%d:%s", pid, nonce)
	return M._owner
end

local function valid_job_pid(value)
	local pid = tonumber(value)
	return pid and pid > 0 and pid % 1 == 0 and pid or nil
end

local function newer(candidate, current)
	if not current then
		return true
	end
	if candidate.sequence ~= current.sequence then
		return candidate.sequence > current.sequence
	end
	return candidate.session_id < current.session_id
end

-- Aggregate every bound project in this Neovim pane. Every terminal job must
-- be live and exact. A known busy session wins even while another live bound
-- session has not reported status; idle requires every session to be idle.
function M._compute()
	local handoff_ok, handoff = pcall(require, "config.opencode_handoff")
	local terminal_ok, terminal = pcall(require, "config.opencode_terminal")
	if not handoff_ok or not terminal_ok then
		return nil
	end

	local bindings_ok, bindings = pcall(handoff.active_bindings)
	if not bindings_ok or type(bindings) ~= "table" or next(bindings) == nil then
		return nil
	end

	local job_set = {}
	local busy
	local idle
	local all_idle = true

	for project, binding in pairs(bindings) do
		if type(binding) ~= "table" or type(binding.sessionID) ~= "string" then
			return nil
		end

		local pid = valid_job_pid(terminal.job_pid_for(project, binding.generation))
		if not pid then
			return nil
		end
		job_set[pid] = true

		local cached = session_cache[binding.sessionID]
		if not cached or not cached.status then
			all_idle = false
		else
			local candidate = {
				session_id = binding.sessionID,
				sequence = cached.status_sequence or 0,
				provider = cached.providerID or "",
				model = cached.modelID or "",
			}
			if cached.status == "busy" then
				all_idle = false
				if newer(candidate, busy) then
					busy = candidate
				end
			elseif cached.status == "idle" then
				if newer(candidate, idle) then
					idle = candidate
				end
			else
				all_idle = false
			end
		end
	end

	local job_pids = {}
	for pid in pairs(job_set) do
		table.insert(job_pids, pid)
	end
	table.sort(job_pids)

	local winner
	local status
	if busy then
		winner = busy
		status = "busy"
	elseif all_idle and idle then
		winner = idle
		status = "idle"
	else
		return nil
	end

	return {
		status = status,
		provider = winner.provider,
		model = winner.model,
		job_pids = job_pids,
	}
end

local function update_lualine(computed)
	if computed then
		vim.g.opencode_status = computed.status
	elseif server_connected then
		vim.g.opencode_status = "connected"
	else
		vim.g.opencode_status = nil
	end
end

local function command_for(computed)
	local helper = helper_path()
	local pane = tmux_pane()
	local owner = owner_token()
	if not helper or not pane or not owner then
		return nil
	end

	if not computed then
		return { helper, "clear", pane, owner }
	end

	local nvim_pid = valid_job_pid(hooks.getpid())
	if not nvim_pid then
		return nil
	end
	local job_pids = {}
	for _, pid in ipairs(computed.job_pids or {}) do
		table.insert(job_pids, tostring(pid))
	end
	if #job_pids == 0 then
		return nil
	end

	return {
		helper,
		"publish",
		pane,
		"nvim",
		owner,
		computed.status,
		computed.provider or "",
		computed.model or "",
		tostring(nvim_pid),
		table.concat(job_pids, ","),
	}
end

local function operation_finished(token)
	if token ~= M._operation_token then
		return
	end
	M._inflight_job = nil
	M._recompute_inflight = false
	if M._disabled then
		M._recompute_pending = false
		return
	end
	if M._recompute_pending then
		M._recompute_pending = false
		M._recompute()
	end
end

local function run_async(argv)
	M._operation_token = (M._operation_token or 0) + 1
	local token = M._operation_token
	M._recompute_inflight = true

	local ok, job = pcall(hooks.jobstart, argv, {
		detach = false,
		on_exit = function()
			operation_finished(token)
		end,
	})
	if not ok or type(job) ~= "number" or job <= 0 then
		M._recompute_inflight = false
		M._inflight_job = nil
		return false
	end
	M._inflight_job = job
	return true
end

function M._recompute()
	if M._disabled then
		return
	end
	if M._recompute_inflight then
		M._recompute_pending = true
		return
	end

	local computed = M._compute()
	update_lualine(computed)
	local argv = command_for(computed)
	if argv then
		run_async(argv)
	end
end

function M.refresh()
	M._recompute()
end

local function clear_sync()
	local helper = helper_path()
	local pane = tmux_pane()
	local owner = owner_token()
	if helper and pane and owner then
		pcall(hooks.system, { helper, "clear", pane, owner })
	end
end

local function stop_inflight()
	M._operation_token = (M._operation_token or 0) + 1
	local job = M._inflight_job
	M._inflight_job = nil
	M._recompute_inflight = false
	M._recompute_pending = false
	if type(job) == "number" and job > 0 then
		pcall(hooks.jobstop, job)
		pcall(hooks.jobwait, { job }, 200)
	end
end

function M.disable()
	M._disabled = true
	stop_inflight()
	clear_cache()
	server_connected = false
	vim.g.opencode_status = nil
	clear_sync()
end

local function event_properties(event)
	local data = event.data
	local inner = type(data) == "table" and data.event or nil
	return type(inner) == "table" and inner.properties or nil
end

local function create_autocmds(group)
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:session.status",
		desc = "Cache exact-session OpenCode status",
		callback = function(event)
			local props = event_properties(event)
			if type(props) == "table" then
				cache_status(props.sessionID, props.status and props.status.type)
				M._recompute()
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:message.updated",
		desc = "Cache exact-session OpenCode provider and model",
		callback = function(event)
			local props = event_properties(event)
			local info = type(props) == "table" and props.info or nil
			if type(info) == "table" then
				cache_model(info.sessionID, info.providerID, info.modelID)
				M._recompute()
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:session.deleted",
		desc = "Drop deleted OpenCode session state",
		callback = function(event)
			local props = event_properties(event)
			local info = type(props) == "table" and props.info or nil
			if type(info) == "table" then
				drop_session(info.id)
			end
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:server.connected",
		desc = "Track OpenCode server connectivity without coloring tmux",
		callback = function()
			server_connected = true
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:server.instance.disposed",
		desc = "Invalidate session state when the OpenCode server disconnects",
		callback = function()
			server_connected = false
			clear_cache()
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeHandoffEvent:binding_changed",
		desc = "Recompute tmux state after an exact OpenCode bind changes",
		callback = M._recompute,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Synchronously clear this Neovim instance's tmux state",
		callback = M.disable,
	})
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
	if vim.env.OPENCODE_TMUX_STATE_DISABLE == "1" then
		M.disable()
		return
	end
	create_autocmds(group)
end

function M.__set_test_hooks(overrides)
	for name, value in pairs(overrides or {}) do
		if defaults[name] then
			hooks[name] = value
		end
	end
end

function M.__reset()
	clear_cache()
	sequence = 0
	server_connected = false
	hooks = vim.tbl_extend("force", {}, defaults)
	M._owner = nil
	M._did_setup = nil
	M._disabled = nil
	M._inflight_job = nil
	M._recompute_inflight = nil
	M._recompute_pending = nil
	M._operation_token = nil
	vim.g.opencode_status = nil
	pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
end

return M

local M = {}

local state = {
	projects = {},
}

local max_payload_bytes = 512 * 1024
local max_batch_paths = 512

local function response(status, reason, extra)
	return vim.tbl_extend("force", { status = status, reason = reason }, extra or {})
end

local function token(prefix)
	local entropy = table.concat({
		tostring(vim.uv.hrtime()),
		tostring(vim.fn.getpid()),
		tostring({}),
	}, ":")
	return prefix .. vim.fn.sha256(entropy):sub(1, 40)
end

local function canonical_project(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local absolute = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
	local resolved = vim.uv.fs_realpath(absolute)
	local stat = resolved and vim.uv.fs_stat(resolved) or nil
	if not stat or stat.type ~= "directory" then
		return nil
	end
	return resolved == "/" and resolved or resolved:gsub("/+$", "")
end

local function canonical_target(project, path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local absolute = path:sub(1, 1) == "/" and path or vim.fs.joinpath(project, path)
	absolute = vim.fs.normalize(absolute)

	local cursor = absolute
	local missing = {}
	while not vim.uv.fs_stat(cursor) do
		local parent = vim.fs.dirname(cursor)
		if not parent or parent == cursor then
			return nil
		end
		table.insert(missing, 1, vim.fs.basename(cursor))
		cursor = parent
	end

	local resolved = vim.uv.fs_realpath(cursor)
	if not resolved then
		return nil
	end
	for _, segment in ipairs(missing) do
		resolved = vim.fs.joinpath(resolved, segment)
	end
	resolved = vim.fs.normalize(resolved)
	if resolved ~= project and resolved:sub(1, #project + 1) ~= project .. "/" then
		return nil
	end
	return resolved
end

local function valid_identifier(value)
	return type(value) == "string" and value:match("^[%w_-]+$") ~= nil
end

local function ensure_server()
	if vim.v.servername == "" then
		pcall(vim.fn.serverstart)
	end
	return vim.v.servername ~= ""
end

local function authenticate(payload)
	local project = canonical_project(payload.directory)
	local project_state = project and state.projects[project] or nil
	if not project_state then
		return nil, nil, response("rejected", "unbound_project")
	end
	if not valid_identifier(payload.generation) or payload.generation ~= project_state.generation then
		return nil, nil, response("rejected", "stale_generation")
	end
	if type(payload.lease) ~= "string" or payload.lease == "" or payload.lease ~= project_state.lease then
		return nil, nil, response("rejected", "invalid_lease")
	end
	return project, project_state
end

local function emit_binding_changed()
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "OpencodeHandoffEvent:binding_changed",
		modeline = false,
	})
end

local function focus_buffer(buf)
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			if vim.api.nvim_win_get_buf(win) == buf then
				vim.api.nvim_set_current_tabpage(tab)
				vim.api.nvim_set_current_win(win)
				return
			end
		end
	end
	vim.cmd("tabnew")
	vim.api.nvim_win_set_buf(0, buf)
end

local function focus_path(path)
	if vim.fn.filereadable(path) ~= 1 then
		return
	end
	local buf = vim.fn.bufnr(path)
	if buf < 0 then
		buf = vim.fn.bufadd(path)
	end
	if not vim.api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
	end
	focus_buffer(buf)
end

local function can_interrupt_editor()
	return vim.api.nvim_get_mode().mode == "n" and not vim.bo[vim.api.nvim_get_current_buf()].modified
end

local function plan_provenance(project, project_state)
	return {
		kind = "native",
		project = project,
		sessionID = project_state.sessionID,
		generation = project_state.generation,
		routeRevision = project_state.routeRevision,
		routeToken = project_state.routeToken,
	}
end

local function process_project(project)
	local project_state = state.projects[project]
	if not project_state or not project_state.pending then
		return
	end
	project_state.process_scheduled = false

	pcall(function()
		require("config.opencode_terminal").close_generation(project, project_state.generation)
	end)
	if not can_interrupt_editor() then
		return
	end

	local pending = project_state.pending
	project_state.pending = nil

	pcall(require("config.hotreload").reload_paths, pending.paths)
	local items = {}
	for _, path in ipairs(pending.paths) do
		table.insert(items, { filename = path, lnum = 1, col = 1, text = "OpenCode changed" })
	end
	vim.fn.setqflist({}, " ", { title = "OpenCode changed files", items = items })

	if pending.latest and pending.latest ~= project .. "/.plan.md" then
		focus_path(pending.latest)
	end
	if pending.plan_changed then
		require("config.diffview_idle").open_handoff({
			project_dir = project,
			open_diff = true,
			provenance = plan_provenance(project, project_state),
		})
	end
end

local function schedule_project(project)
	local project_state = state.projects[project]
	if not project_state or project_state.process_scheduled then
		return
	end
	project_state.process_scheduled = true
	vim.schedule(function()
		process_project(project)
	end)
end

local function merge_pending(project, project_state, paths)
	local pending = project_state.pending or { paths = {}, seen = {} }
	for _, path in ipairs(paths) do
		if not pending.seen[path] then
			pending.seen[path] = true
			table.insert(pending.paths, path)
		end
		if path == project .. "/.plan.md" then
			pending.plan_changed = true
		else
			pending.latest = path
		end
	end
	project_state.pending = pending
end

local function receive_hello(payload)
	local project = canonical_project(payload.directory)
	local project_state = project and state.projects[project] or nil
	if not project_state then
		return response("rejected", "unbound_project")
	end
	if not valid_identifier(payload.generation) or payload.generation ~= project_state.generation then
		return response("rejected", "stale_generation")
	end
	project_state.lease = token("lease_")
	return response("handled", "lease_issued", {
		lease = project_state.lease,
		routeRevision = project_state.routeRevision,
		sessionID = project_state.sessionID,
	})
end

local function receive_bind(payload)
	local _, project_state, err = authenticate(payload)
	if err then
		return err
	end
	if not valid_identifier(payload.sessionID) or type(payload.routeRevision) ~= "number" or payload.routeRevision % 1 ~= 0 then
		return response("rejected", "invalid_route")
	end
	if payload.routeRevision < project_state.routeRevision then
		return response("rejected", "stale_route_revision")
	end
	if payload.routeRevision == project_state.routeRevision and payload.sessionID ~= project_state.sessionID then
		return response("rejected", "stale_route_revision")
	end
	if payload.routeRevision > project_state.routeRevision then
		project_state.sessionID = payload.sessionID
		project_state.routeRevision = payload.routeRevision
		project_state.routeToken = token("route_")
		emit_binding_changed()
	end
	return response("handled", "session_bound", { routeRevision = project_state.routeRevision })
end

local function receive_idle_batch(payload)
	local project, project_state, err = authenticate(payload)
	if err then
		return err
	end
	if payload.sessionID ~= project_state.sessionID then
		return response("rejected", "wrong_session")
	end
	if payload.routeRevision ~= project_state.routeRevision then
		return response("rejected", "stale_route_revision")
	end
	if type(payload.paths) ~= "table" or #payload.paths == 0 or #payload.paths > max_batch_paths then
		return response("rejected", "invalid_paths")
	end

	local paths = {}
	for index, path in ipairs(payload.paths) do
		if index > max_batch_paths then
			return response("rejected", "invalid_paths")
		end
		local resolved = canonical_target(project, path)
		if not resolved then
			return response("rejected", "path_outside_project")
		end
		table.insert(paths, resolved)
	end

	merge_pending(project, project_state, paths)
	schedule_project(project)
	return response("queued", "idle_batch_queued")
end

function M.receive(payload)
	if type(payload) ~= "table" or payload.version ~= 1 or type(payload.type) ~= "string" then
		return response("rejected", "invalid_payload")
	end
	if payload.type == "hello" then
		return receive_hello(payload)
	end
	if payload.type == "bind" then
		return receive_bind(payload)
	end
	if payload.type == "idle_batch" then
		return receive_idle_batch(payload)
	end
	return response("rejected", "unsupported_type")
end

function M.receive_base64(encoded)
	if type(encoded) ~= "string" or #encoded == 0 or #encoded > max_payload_bytes or not encoded:match("^[A-Za-z0-9+/=]+$") then
		return vim.json.encode(response("rejected", "invalid_encoding"))
	end
	local decoded_ok, decoded = pcall(vim.base64.decode, encoded)
	if not decoded_ok or type(decoded) ~= "string" or #decoded > max_payload_bytes then
		return vim.json.encode(response("rejected", "invalid_encoding"))
	end
	local payload_ok, payload = pcall(vim.json.decode, decoded)
	if not payload_ok then
		return vim.json.encode(response("rejected", "invalid_json"))
	end
	return vim.json.encode(M.receive(payload))
end

function M.register_terminal(project, generation)
	project = canonical_project(project)
	if not project or not valid_identifier(generation) then
		return false
	end
	local current = state.projects[project]
	if current and current.generation == generation then
		return true
	end
	state.projects[project] = {
		generation = generation,
		routeRevision = 0,
	}
	return true
end

function M.unregister_terminal(project, generation)
	project = canonical_project(project)
	local current = project and state.projects[project] or nil
	if not current or current.generation ~= generation then
		return false
	end
	local was_bound = current.sessionID ~= nil
	state.projects[project] = nil
	if was_bound then
		emit_binding_changed()
	end
	return true
end

function M.active_bindings()
	local bindings = {}
	for project, project_state in pairs(state.projects) do
		if project_state.sessionID then
			bindings[project] = {
				project = project,
				generation = project_state.generation,
				sessionID = project_state.sessionID,
				routeRevision = project_state.routeRevision,
			}
		end
	end
	return bindings
end

function M.resolve_plan_route(provenance)
	if type(provenance) ~= "table" or provenance.kind ~= "native" then
		return nil
	end
	local project = canonical_project(provenance.project)
	local current = project and state.projects[project] or nil
	if
		not current
		or current.generation ~= provenance.generation
		or current.sessionID ~= provenance.sessionID
		or current.routeRevision ~= provenance.routeRevision
		or current.routeToken ~= provenance.routeToken
	then
		return nil
	end
	return { sessionID = current.sessionID, directory = project }
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true
	ensure_server()
	local group = vim.api.nvim_create_augroup("nvim_mini_opencode_handoff", { clear = true })
	vim.api.nvim_create_autocmd({ "ModeChanged", "BufWritePost", "TermLeave" }, {
		group = group,
		callback = function()
			for project, project_state in pairs(state.projects) do
				if project_state.pending then
					schedule_project(project)
				end
			end
		end,
		desc = "Retry a deferred native OpenCode handoff when the editor is safe",
	})
end

function M.__reset()
	state = { projects = {} }
	M._did_setup = nil
	pcall(vim.api.nvim_del_augroup_by_name, "nvim_mini_opencode_handoff")
end

return M

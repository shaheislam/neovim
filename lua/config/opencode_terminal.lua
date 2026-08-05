-- Persistent OpenCode ToggleTerm adapter.
--
-- lua/plugins/opencode.lua is a lazy.nvim plugin *spec* file: it can be
-- re-executed (via :luafile, a manual `dofile`, or certain reload flows)
-- independently of ToggleTerm's own terminal registry, which lives in a
-- separate module and survives such re-sourcing. When the old design kept
-- its terminal cache as a spec-file-local variable, re-sourcing reset that
-- local while the previously-spawned ToggleTerm process kept running
-- (unreachable but alive), leaving prompt delivery silently pointed at a
-- brand new, disconnected terminal. This module owns that lifecycle as a
-- normal `require`d module instead, so its cache survives re-sourcing of the
-- plugin spec, and it actively reconciles with ToggleTerm's registry to
-- adopt/retire any pre-existing OpenCode terminals rather than trusting only
-- its own memory.

local M = {}

local state = {
	by_project = {},
}

local defaults = {
	display_name = "OpenCode",
	-- Both `[` and `?` are Lua pattern metacharacters and must be escaped to
	-- match the literal DECSET 2004h bracketed-paste-enable sequence.
	ready_pattern = "\27%[%?2004h",
	ready_timeout_ms = 8000,
	adopted_ready_timeout_ms = 500,
	notify_title = "opencode",
	launch = function(dir)
		return {
			cmd = dir,
			env = {},
			clear_env = false,
		}
	end,
	project_root = function(explicit_dir)
		return explicit_dir or vim.fn.getcwd()
	end,
	size = function()
		return math.floor(vim.o.columns * 0.5)
	end,
	generation = function()
		local entropy = table.concat({
			tostring(vim.uv.hrtime()),
			tostring(vim.fn.getpid()),
			tostring({}),
		}, ":")
		return "nvim_" .. vim.fn.sha256(entropy):sub(1, 32)
	end,
	on_create = nil,
	on_start = nil,
	on_exit = nil,
}

local opts = vim.deepcopy(defaults)

function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", defaults, user_opts or {})
end

local function resolve_size(term)
	return type(term.size) == "function" and term.size() or term.size
end

local function ensure_toggleterm_loaded()
	if package.loaded["toggleterm.terminal"] then
		return
	end
	local lazy_ok, lazy = pcall(require, "lazy")
	if lazy_ok then
		pcall(function()
			lazy.load({ plugins = { "toggleterm.nvim" } })
		end)
	end
end

local function default_terminal_live(term)
	local bufnr = term.bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local channel = vim.bo[bufnr].channel
	if not channel or channel <= 0 then
		return false
	end
	local ok, result = pcall(vim.fn.jobwait, { channel }, 0)
	return ok and type(result) == "table" and result[1] == -1
end

local function default_terminal_write(term, payload, on_result)
	local bufnr = term.bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		on_result(false, "OpenCode terminal buffer is not available")
		return
	end
	local channel = vim.bo[bufnr].channel
	if not channel or channel <= 0 then
		on_result(false, "OpenCode terminal has no active channel")
		return
	end
	local wait_ok, wait_result = pcall(vim.fn.jobwait, { channel }, 0)
	if not wait_ok or type(wait_result) ~= "table" or wait_result[1] ~= -1 then
		on_result(false, "OpenCode terminal is not running")
		return
	end
	local send_ok = pcall(vim.api.nvim_chan_send, channel, payload)
	if not send_ok then
		on_result(false, "Failed to write to OpenCode terminal")
		return
	end
	on_result(true)
end

local function default_terminal_job_pid(term)
	local bufnr = term.bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end
	local channel = vim.bo[bufnr].channel
	if not channel or channel <= 0 then
		return nil
	end
	local ok, pid = pcall(vim.fn.jobpid, channel)
	return ok and type(pid) == "number" and pid > 0 and pid or nil
end

-- The channel/job liveness probe below is the one part of this module that
-- genuinely needs a live terminal job to test realistically. Tests override
-- it (and the paired write primitive) through __set_test_hooks instead of
-- spawning real processes; everything else (reconciliation, readiness,
-- timers, dead-terminal reconstruction) exercises the real production code.
local terminal_live = default_terminal_live
local terminal_write = default_terminal_write
local terminal_job_pid = default_terminal_job_pid

function M.__set_test_hooks(hooks)
	hooks = hooks or {}
	terminal_live = hooks.terminal_live or default_terminal_live
	terminal_write = hooks.terminal_write or default_terminal_write
	terminal_job_pid = hooks.terminal_job_pid or default_terminal_job_pid
end

local function fail_pending(term, message)
	local pending = term._nvim_mini_pending or {}
	term._nvim_mini_pending = {}
	for _, request in ipairs(pending) do
		request.on_result(false, message)
	end
end

local function queue_or_write(term, payload, on_result)
	if term._nvim_mini_ready then
		terminal_write(term, payload, on_result)
		return
	end
	term._nvim_mini_pending = term._nvim_mini_pending or {}
	table.insert(term._nvim_mini_pending, { payload = payload, on_result = on_result })
end

local function stop_ready_timer(term)
	if term._nvim_mini_ready_timer then
		term._nvim_mini_ready_timer:stop()
		term._nvim_mini_ready_timer:close()
		term._nvim_mini_ready_timer = nil
	end
end

local lifecycle_group = vim.api.nvim_create_augroup("NvimMiniOpenCodeTerminalLifecycle", { clear = false })

local function owns_generation(term, dir, generation)
	local entry = state.by_project[dir]
	return entry ~= nil and entry.term == term and entry.generation == generation
end

-- State release never deletes a buffer. ToggleTerm owns natural-exit deletion,
-- while explicit adapter close paths call shutdown() only after ownership and
-- external bindings have been invalidated.
local function release_generation(term, dir, generation, message)
	stop_ready_timer(term)
	term._nvim_mini_ready = false
	fail_pending(term, message)
	if not owns_generation(term, dir, generation) then
		return false
	end
	state.by_project[dir] = nil
	return true
end

local function finalize_adapter(term, lifecycle, exit_code)
	if lifecycle.adapter_finalized then
		return
	end
	lifecycle.adapter_finalized = true
	if opts.on_exit then
		opts.on_exit(term, lifecycle.dir, lifecycle.generation, exit_code)
	end
end

local function finalize_foreign(term, lifecycle, job_id, exit_code, ...)
	if lifecycle.foreign_finalized or not lifecycle.foreign_on_exit then
		return
	end
	lifecycle.foreign_finalized = true
	lifecycle.foreign_on_exit(term, job_id, exit_code, ...)
end

local function install_buffer_lifecycle(term, created_term, lifecycle)
	local bufnr = created_term and created_term.bufnr or term.bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local binding = tostring(bufnr) .. ":" .. lifecycle.generation
	if term._nvim_mini_buffer_binding == binding then
		return
	end
	term._nvim_mini_buffer_binding = binding
	vim.bo[bufnr].bufhidden = "wipe"
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = lifecycle_group,
		buffer = bufnr,
		once = true,
		callback = function()
			release_generation(term, lifecycle.dir, lifecycle.generation, "OpenCode terminal closed")
		end,
	})
end

local function run_on_create(term, created_term, lifecycle)
	term._nvim_mini_started = true
	install_buffer_lifecycle(term, created_term, lifecycle)
	if lifecycle.created then
		return
	end
	lifecycle.created = true
	if opts.on_create then
		opts.on_create(created_term or term, lifecycle.dir, lifecycle.generation)
	end
end

local function bind_terminal_lifecycle(term, dir, generation, adopted)
	local previous_lifecycle = term._nvim_mini_lifecycle
	local foreign_on_exit = term.on_exit
	if foreign_on_exit and foreign_on_exit == term._nvim_mini_adapter_on_exit then
		foreign_on_exit = previous_lifecycle and previous_lifecycle.foreign_on_exit or nil
	end

	local lifecycle = {
		dir = dir,
		generation = generation,
		foreign_on_exit = foreign_on_exit,
	}
	term._nvim_mini_lifecycle = lifecycle
	term._nvim_mini_generation = generation
	term.close_on_exit = true

	local adapter_on_exit = function(exit_term, job_id, exit_code, ...)
		if lifecycle.exit_seen then
			return
		end
		lifecycle.exit_seen = true
		if exit_code ~= 0 then
			vim.notify(
				"OpenCode terminal exited with code " .. exit_code,
				vim.log.levels.ERROR,
				{ title = opts.notify_title }
			)
		end
		release_generation(exit_term, dir, generation, "OpenCode terminal exited")
		finalize_adapter(exit_term, lifecycle, exit_code)
		finalize_foreign(exit_term, lifecycle, job_id, exit_code, ...)
	end
	term._nvim_mini_adapter_on_exit = adapter_on_exit
	term.on_exit = adapter_on_exit

	install_buffer_lifecycle(term, term, lifecycle)
	if adopted then
		term._nvim_mini_started = true
		run_on_create(term, term, lifecycle)
	end
	return lifecycle
end

local function retire_generation(term, dir, generation)
	if not owns_generation(term, dir, generation) then
		return false
	end
	local lifecycle = term._nvim_mini_lifecycle
	release_generation(term, dir, generation, "OpenCode terminal closed")
	if lifecycle then
		finalize_adapter(term, lifecycle, 0)
	end
	if not term._nvim_mini_shutdown then
		term._nvim_mini_shutdown = true
		pcall(function()
			term:shutdown()
		end)
	end
	return true
end

-- One-shot: whichever of "readiness observed" / "timeout elapsed" happens
-- first wins; the other is a no-op, so pending writes are never delivered
-- twice and never delivered after a timeout has already failed them closed.
local function mark_terminal_ready(term)
	if term._nvim_mini_ready then
		return
	end
	term._nvim_mini_ready = true
	stop_ready_timer(term)
	local pending = term._nvim_mini_pending or {}
	term._nvim_mini_pending = {}
	for _, request in ipairs(pending) do
		terminal_write(term, request.payload, request.on_result)
	end
end

-- Fresh spawns must genuinely wait for the DECSET 2004h marker before we
-- know the composer can accept pasted text, so this fails closed rather than
-- assuming readiness.
local function start_ready_timeout(term)
	if term._nvim_mini_ready_timer then
		return
	end
	local timer = vim.uv.new_timer()
	term._nvim_mini_ready_timer = timer
	timer:start(
		opts.ready_timeout_ms,
		0,
		vim.schedule_wrap(function()
			if term._nvim_mini_ready_timer ~= timer then
				return
			end
			term._nvim_mini_ready_timer = nil
			timer:stop()
			timer:close()
			if not term._nvim_mini_ready then
				fail_pending(term, "Timed out waiting for OpenCode terminal to become ready")
			end
		end)
	)
end

-- A terminal adopted from ToggleTerm's registry (rather than spawned by this
-- adapter generation) already emitted its ready marker, if any, long before
-- we attached -- it will never repeat it, and its on_stdout callback was
-- captured by ToggleTerm at spawn time so it can't be replaced. If it's
-- still running, assume it's ready after a short grace period instead of
-- hanging forever; if it's not running, fail closed like any other dead
-- terminal.
local function start_adopted_fallback(term)
	if term._nvim_mini_ready_timer or term._nvim_mini_ready then
		return
	end
	local timer = vim.uv.new_timer()
	term._nvim_mini_ready_timer = timer
	timer:start(
		opts.adopted_ready_timeout_ms,
		0,
		vim.schedule_wrap(function()
			if term._nvim_mini_ready_timer ~= timer then
				return
			end
			term._nvim_mini_ready_timer = nil
			timer:stop()
			timer:close()
			if term._nvim_mini_ready then
				return
			end
			if terminal_live(term) then
				mark_terminal_ready(term)
			else
				fail_pending(term, "OpenCode terminal is not running")
			end
		end)
	)
end

-- The ready marker can arrive split across separate on_stdout invocations;
-- carry a short tail across calls so a split escape sequence is still
-- detected once the remainder arrives.
local function scan_ready(term, data)
	if term._nvim_mini_ready then
		return
	end
	local tail = term._nvim_mini_stdout_tail or ""
	local chunk = tail .. table.concat(data or {}, "\n")
	if chunk:find(opts.ready_pattern) then
		term._nvim_mini_stdout_tail = nil
		mark_terminal_ready(term)
		return
	end
	local keep = 16
	term._nvim_mini_stdout_tail = #chunk > keep and chunk:sub(-keep) or chunk
end

local function normalize_dir(dir)
	if type(dir) ~= "string" or dir == "" then
		return nil
	end
	return vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
end

local function new_generation()
	local generation = opts.generation()
	if type(generation) ~= "string" or not generation:match("^[%w_-]+$") then
		error("OpenCode terminal generation must contain only letters, digits, underscores, or hyphens")
	end
	return generation
end

local function ensure_rpc_server()
	if vim.v.servername == "" then
		pcall(vim.fn.serverstart)
	end
	if vim.v.servername == "" then
		error("OpenCode terminal requires a Neovim RPC server")
	end
	return vim.v.servername
end

local function resolve_launch(dir, generation, launch_context)
	local launch = opts.launch(dir, generation, launch_context)
	if type(launch) ~= "table" or type(launch.cmd) ~= "string" or launch.cmd == "" then
		error("OpenCode terminal launch must provide a non-empty cmd")
	end
	if launch.env ~= nil and type(launch.env) ~= "table" then
		error("OpenCode terminal launch env must be a table")
	end
	local env = vim.deepcopy(launch.env or {})
	env.OPENCODE_NVIM_GENERATION = generation
	return {
		cmd = launch.cmd,
		env = env,
		clear_env = launch.clear_env == true,
	}
end

local function launch_matches(term, launch)
	return term.cmd == launch.cmd
		and vim.deep_equal(term.env or {}, launch.env)
		and term.clear_env == launch.clear_env
end

local function terminal_owned_by_project(term, dir)
	return term.display_name == opts.display_name
		and term.hidden == true
		and normalize_dir(term.dir) == normalize_dir(dir)
end

local function discover_candidates(dir)
	local ok, toggleterm = pcall(require, "toggleterm.terminal")
	if not ok or type(toggleterm.get_all) ~= "function" then
		return {}
	end
	local all = toggleterm.get_all(true) -- include hidden
	local matches = {}
	for _, term in ipairs(all) do
		if terminal_owned_by_project(term, dir) then
			table.insert(matches, term)
		end
	end
	return matches
end

local function candidate_rank(term)
	if term:is_open() then
		return 1
	end
	if term._nvim_mini_ready then
		return 2
	end
	if terminal_live(term) then
		return 3
	end
	return 4 -- dead: never chosen as the winner
end

local function choose_candidate(candidates)
	local best, best_rank
	for _, term in ipairs(candidates) do
		local rank = candidate_rank(term)
		if rank < 4 and (not best or rank < best_rank or (rank == best_rank and term.id < best.id)) then
			best = term
			best_rank = rank
		end
	end
	return best
end

-- Retires every non-selected candidate that isn't a live, UI-open terminal
-- (dead husks, and live-but-hidden duplicates from a prior adapter
-- generation) while leaving any other visible terminal untouched.
local function reconcile(dir, launch)
	local candidates = discover_candidates(dir)
	local exact = {}
	for _, term in ipairs(candidates) do
		if launch_matches(term, launch) then
			table.insert(exact, term)
		end
	end
	local selected = choose_candidate(exact)
	for _, term in ipairs(candidates) do
		if term ~= selected then
			local live = terminal_live(term)
			if not live or not term:is_open() then
				pcall(function()
					term:shutdown()
				end)
			end
		end
	end
	return selected
end

local function new_terminal(dir, launch, generation)
	ensure_toggleterm_loaded()
	local Terminal = require("toggleterm.terminal").Terminal
	local term
	term = Terminal:new({
		cmd = launch.cmd,
		env = vim.deepcopy(launch.env),
		clear_env = launch.clear_env,
		direction = "vertical",
		dir = dir,
		display_name = opts.display_name,
		hidden = true,
		close_on_exit = true,
		on_create = function(created_term)
			run_on_create(term, created_term, term._nvim_mini_lifecycle)
		end,
		on_stdout = function(term, _, data)
			scan_ready(term, data)
		end,
		size = opts.size,
	})
	bind_terminal_lifecycle(term, dir, generation, false)
	return term
end

-- Passive ownership check for consumers that must distinguish this adapter's
-- terminal from unrelated ToggleTerm buffers without parsing terminal names.
function M.is_buffer(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	for _, entry in pairs(state.by_project) do
		if entry.term and entry.term.bufnr == bufnr then
			return true
		end
	end
	return false
end

-- Returns the cached/adopted terminal for `dir` (canonicalized via
-- opts.project_root), trusting an exact launch snapshot match. Liveness is
-- not re-checked here on every call -- only at the two points where it
-- actually matters: first resolution (cold cache or changed launch, via
-- reconcile()) and right
-- before spawning/opening (via ensure_live() below), where a dead terminal
-- must be explicitly replaced rather than reopened.
function M.get_terminal(dir)
	dir = opts.project_root(dir)
	local entry = state.by_project[dir]
	if not entry then
		entry = { dir = dir, generation = new_generation() }
		state.by_project[dir] = entry
	end
	local launch = resolve_launch(dir, entry.generation, entry.launch_context)

	if entry and entry.term and launch_matches(entry.launch, launch) then
		return entry.term
	end

	if entry and entry.term then
		-- Launch changed (e.g. an auth/env revision): retire the old
		-- generation before adopting/creating the new target.
		local launch_context = vim.deepcopy(entry.launch_context)
		retire_generation(entry.term, dir, entry.generation)
		entry = { dir = dir, generation = new_generation(), launch_context = launch_context }
		state.by_project[dir] = entry
		launch = resolve_launch(dir, entry.generation, entry.launch_context)
	end

	entry.launch = launch

	ensure_toggleterm_loaded()
	local adopted = reconcile(dir, launch)
	local term
	if adopted then
		term = adopted
		entry.term = term
		bind_terminal_lifecycle(term, dir, entry.generation, true)
		if not term._nvim_mini_ready then
			start_adopted_fallback(term)
		end
	else
		term = new_terminal(dir, launch, entry.generation)
	end

	entry.term = term
	return term
end

-- If `term`'s job has died but its buffer is still valid, ToggleTerm's
-- open()/toggle() will just redisplay the stale dead buffer instead of
-- respawning -- shut it down and replace the cached entry with a fresh
-- terminal for the same project so reopening actually restarts the process.
local function ensure_live(dir, term)
	if terminal_live(term) then
		return term
	end
	if not term._nvim_mini_started then
		return term
	end
	local entry = state.by_project[dir]
	if not entry or entry.term ~= term or not entry.launch then
		return M.get_terminal(dir)
	end
	local launch = vim.deepcopy(entry.launch)
	local launch_context = vim.deepcopy(entry.launch_context)
	retire_generation(term, dir, entry.generation)
	entry = { dir = dir, generation = new_generation(), launch = launch, launch_context = launch_context }
	entry.launch.env.OPENCODE_NVIM_GENERATION = entry.generation
	state.by_project[dir] = entry
	term = new_terminal(dir, entry.launch, entry.generation)
	entry.term = term
	return term
end

local function ensure_spawned(term)
	if terminal_live(term) then
		return
	end
	term._nvim_mini_ready = false
	term:spawn()
	term._nvim_mini_started = true
	start_ready_timeout(term)
end

function M.start(dir)
	dir = opts.project_root(dir)
	ensure_rpc_server()
	local term = ensure_live(dir, M.get_terminal(dir))
	local entry = state.by_project[dir]
	if opts.on_start then
		opts.on_start(term, dir, entry.generation)
	end
	ensure_spawned(term)
	return term
end

-- Idempotent: ToggleTerm's real Terminal:open() unconditionally resets its
-- remembered origin window, even when the terminal is already visible.
-- Calling open() again on an already-open terminal must therefore focus it
-- instead, or the coordinated worktree-startup layout's split placement
-- would be silently disturbed by a later reopen.
function M.open(dir)
	local term = M.start(dir)
	if term:is_open() then
		term:focus()
	else
		term:open(resolve_size(term))
	end
	return term
end

function M.toggle(dir)
	dir = opts.project_root(dir)
	local entry = state.by_project[dir]
	if entry and entry.term and terminal_live(entry.term) and entry.term:is_open() then
		retire_generation(entry.term, dir, entry.generation)
		return entry.term
	end
	local term = M.start(dir)
	term:toggle(resolve_size(term))
	return term
end

function M.close(dir)
	dir = opts.project_root(dir)
	local entry = state.by_project[dir]
	if entry and entry.term then
		retire_generation(entry.term, dir, entry.generation)
	end
end

function M.close_generation(dir, generation)
	dir = opts.project_root(dir)
	local entry = state.by_project[dir]
	if not entry or entry.generation ~= generation or not entry.term then
		return false
	end
	return retire_generation(entry.term, dir, generation)
end

local function restart_failure(message, owner_retired)
	return {
		ok = false,
		error = message,
		owner_retired = owner_retired == true,
	}
end

-- Replaces only the live terminal owned by this adapter instance. Unlike
-- get_terminal(), this never discovers, adopts, or creates a fallback owner.
function M.restart_owned(dir, launch_context)
	dir = opts.project_root(dir)
	local current = state.by_project[dir]
	if not current or not current.term or not terminal_live(current.term) then
		return restart_failure("No running OpenCode terminal is owned by this Neovim for this route", false)
	end

	local prepared, generation, launch = pcall(function()
		ensure_rpc_server()
		local next_generation = new_generation()
		return next_generation, resolve_launch(dir, next_generation, launch_context)
	end)
	if not prepared then
		return restart_failure(generation, false)
	end

	local was_open = current.term:is_open()
	retire_generation(current.term, dir, current.generation)
	local owner_retired = true
	if terminal_live(current.term) then
		return restart_failure("Could not stop the existing OpenCode terminal", owner_retired)
	end

	local entry = {
		dir = dir,
		generation = generation,
		launch = launch,
		launch_context = vim.deepcopy(launch_context),
	}
	state.by_project[dir] = entry

	local replacement
	local restarted, restart_err = pcall(function()
		replacement = new_terminal(dir, launch, generation)
		entry.term = replacement
		if opts.on_start then
			opts.on_start(replacement, dir, generation)
		end
		ensure_spawned(replacement)
		if type(replacement.job_id) ~= "number" or replacement.job_id <= 0 or not terminal_live(replacement) then
			error("OpenCode replacement terminal did not start")
		end
		if was_open then
			replacement:open(resolve_size(replacement))
			if not replacement:is_open() or not terminal_live(replacement) then
				error("OpenCode replacement terminal did not reopen")
			end
		end
	end)

	if not restarted then
		if replacement then
			retire_generation(replacement, dir, generation)
		elseif state.by_project[dir] == entry then
			state.by_project[dir] = nil
		end
		return restart_failure(restart_err, owner_retired)
	end

	return {
		ok = true,
		term = replacement,
		owner_retired = owner_retired,
	}
end

function M.generation_for(dir)
	dir = opts.project_root(dir)
	local entry = state.by_project[dir]
	return entry and entry.generation or nil
end

function M.job_pid_for(dir, generation)
	dir = opts.project_root(dir)
	local entry = state.by_project[dir]
	if not entry or entry.generation ~= generation or not entry.term or not terminal_live(entry.term) then
		return nil
	end
	return terminal_job_pid(entry.term)
end

-- Sink for config.opencode_prompt: writes raw bytes (bracketed paste, plus a
-- trailing \r only when submitting) directly into the OpenCode terminal PTY
-- owned by this Neovim process. Never broadcasts.
function M.send(text, send_opts)
	send_opts = send_opts or {}
	local ok, term = pcall(M.start, send_opts.dir)
	if not ok or not term then
		if send_opts.on_failure then
			send_opts.on_failure("Could not create the OpenCode terminal")
		end
		return
	end
	local payload
	if text == "" then
		payload = send_opts.submit and "\r" or ""
	else
		payload = "\27[200~" .. text .. "\27[201~" .. (send_opts.submit and "\r" or "")
	end
	queue_or_write(term, payload, function(success, message)
		if success then
			if send_opts.on_success then
				send_opts.on_success()
			end
		elseif send_opts.on_failure then
			send_opts.on_failure(message)
		end
	end)
end

-- Test-only: clears cached state and options between test sections.
function M.__reset()
	state = { by_project = {} }
	opts = vim.deepcopy(defaults)
end

return M

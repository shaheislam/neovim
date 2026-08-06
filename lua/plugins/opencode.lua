-- opencode.nvim - AI coding agent integration
-- Connects to the launchd-managed OpenCode server via HTTP + SSE
-- Shares editor context (buffers, selections, diagnostics) with the agent

local opencode_port = 4096
local opencode_ready_delay = 500
local opencode_startup_timeout = 30000
local opencode_startup_poll = 500
local opencode_service = "com.dotfiles.opencode-serve"
local terminal_adapter = require("config.opencode_terminal")

local function opencode_username()
	return vim.env.OPENCODE_SERVER_USERNAME or "opencode"
end

local function opencode_password()
	if vim.env.OPENCODE_SERVER_PASSWORD and vim.env.OPENCODE_SERVER_PASSWORD ~= "" then
		return vim.env.OPENCODE_SERVER_PASSWORD
	end

	local state_home = vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")
	local password_file = state_home .. "/opencode/server.password"
	if vim.fn.filereadable(password_file) == 1 then
		return table.concat(vim.fn.readfile(password_file), "")
	end

	return nil
end

local function current_opencode_auth()
	return {
		username = opencode_username(),
		password = opencode_password(),
	}
end

local function assign_server_auth(options, auth)
	options.server = options.server or {}
	options.server.username = auth.username
	options.server.password = nil
	if auth.password and auth.password ~= "" then
		options.server.password = auth.password
	end
	return options
end

local function sync_opencode_auth(auth)
	local global_opts = vim.g.opencode_opts or {}
	assign_server_auth(global_opts, auth)
	vim.g.opencode_opts = global_opts

	local config = package.loaded["opencode.config"]
	if type(config) == "table" and type(config.opts) == "table" then
		assign_server_auth(config.opts, auth)
	end
end

local function opencode_launch(dir, _, launch_context)
	-- The dotfiles opencode shim reroutes `attach` through tmux when $TMUX is set.
	-- This terminal already owns the split, so bypass that wrapper and run ocv directly.
	-- Clear multiplexer markers so ocv emits bare OSC52 for Neovim to forward.
	-- OPENTUI_GRAPHICS=0: suppress Kitty graphics probing which segfaults in nvim :terminal.
	local auth = current_opencode_auth()
	sync_opencode_auth(auth)
	local env = {
		OPENCODE_TMUX_WRAPPER_ACTIVE = "1",
		OPENTUI_GRAPHICS = "0",
		OPENCODE_SERVER_USERNAME = auth.username,
		TMUX = "",
		STY = "",
	}
	if auth.password and auth.password ~= "" then
		env.OPENCODE_SERVER_PASSWORD = auth.password
	end

	local command = "ocv attach http://127.0.0.1:" .. opencode_port .. " --dir " .. vim.fn.shellescape(dir)
	if launch_context and launch_context.session_id then
		command = command .. " --session " .. vim.fn.shellescape(launch_context.session_id)
	end

	return {
		cmd = command,
		env = env,
		clear_env = false,
	}
end

-- Resolves the canonical project root a terminal/prompt-write should target:
-- an explicit dir if given, otherwise this Neovim's git root (falling back to
-- cwd). Using the project root rather than raw cwd keeps Oil/subdirectory
-- navigation from spawning a second terminal for the same project.
local function project_root(explicit_dir)
	local ok, http = pcall(require, "config.opencode_http")
	local canonical = ok and type(http.canonical) == "function" and http.canonical or nil
	if explicit_dir and explicit_dir ~= "" then
		return (canonical and canonical(explicit_dir)) or explicit_dir
	end
	local cwd = vim.fn.getcwd()
	local git_dir = vim.fs.find(".git", { path = cwd, upward = true })[1]
	local root = git_dir and vim.fn.fnamemodify(git_dir, ":h") or cwd
	return (canonical and canonical(root)) or root
end

local function bind_opencode_terminal_picker(term, dir)
	local bufnr = term and term.bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local function restore_terminal()
		local wins = vim.fn.win_findbuf(bufnr)
		if wins[1] and vim.api.nvim_win_is_valid(wins[1]) then
			vim.api.nvim_set_current_win(wins[1])
			vim.cmd("startinsert")
		end
	end
	-- Keep the single-Escape transition local to OCV; other terminal TUIs still
	-- receive Escape and use the global double-Escape fallback.
	vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], {
		buffer = bufnr,
		nowait = true,
		desc = "Enter Normal mode from OpenCode",
	})
	-- Bind the shared picker catalog in Neovim's Normal mode so OCV prompt text
	-- remains untouched and the usual leader sequences work after Escape.
	require("config.fzf_prompt").bind(bufnr, {
		mode = "n",
		source = function()
			return require("config.return_target").last()
		end,
		insert = function(text)
			require("config.opencode_prompt").append(text, {
				title = "opencode",
				notify_success = false,
				fallback_clipboard = true,
				dir = dir,
			})
			restore_terminal()
		end,
		restore = restore_terminal,
	})
end

terminal_adapter.setup({
	display_name = "OpenCode",
	launch = opencode_launch,
	project_root = project_root,
	size = function()
		return math.floor(vim.o.columns * 0.5)
	end,
	notify_title = "opencode",
	on_create = function(term, dir, generation)
		bind_opencode_terminal_picker(term, dir)
		require("config.opencode_attach_registry").register(term, dir, generation)
	end,
	on_start = function(term, dir, generation)
		bind_opencode_terminal_picker(term, dir)
		require("config.opencode_handoff").register_terminal(dir, generation)
	end,
	on_exit = function(_, dir, generation)
		require("config.opencode_handoff").unregister_terminal(dir, generation)
		require("config.opencode_attach_registry").unregister(generation)
	end,
})

local function check_opencode_ready(callback)
	local curl_args = {
		"curl",
		"-fsS",
		"--max-time",
		"1",
	}
	local auth = current_opencode_auth()
	if auth.password and auth.password ~= "" then
		vim.list_extend(curl_args, { "-u", auth.username .. ":" .. auth.password })
	end
	table.insert(curl_args, "http://127.0.0.1:" .. opencode_port .. "/path")

	local job = vim.fn.jobstart(curl_args, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_exit = function(_, code)
			vim.schedule(function()
				callback(code == 0)
			end)
		end,
	})

	if job <= 0 then
		vim.schedule(function()
			callback(false)
		end)
	end
end

local function start_opencode_terminal(dir)
	terminal_adapter.start(dir)
end

local function open_opencode_terminal(dir)
	return terminal_adapter.open(dir)
end

-- Coordinated worktree-startup layout: editor upper-left, ordinary project
-- shell lower-left, OCV full-height right, with typing left ready in OCV's
-- composer. ToggleTerm's real Terminal:open() unconditionally resets its
-- remembered "origin window" (the window a new split is placed relative to),
-- so the shell terminal MUST be opened only after focus has been explicitly
-- restored to the editor window - opening it while OCV is still current
-- would otherwise split off of OCV instead of the editor. terminal_adapter's
-- open() is idempotent (see lua/config/opencode_terminal.lua), so the final
-- re-focus of OCV below does not disturb this placement a second time.
local function open_worktree_layout(dir)
	dir = project_root(dir)
	local editor_win = vim.api.nvim_get_current_win()

	local ocv_term = terminal_adapter.open(dir)

	if vim.api.nvim_win_is_valid(editor_win) then
		vim.api.nvim_set_current_win(editor_win)
	end

	require("config.project_terminal").open(dir)

	terminal_adapter.open(dir)
	if vim.bo.buftype == "terminal" then
		vim.cmd("startinsert")
	end

	return ocv_term
end

do
	local prompt_ok, prompt_module = pcall(require, "config.opencode_prompt")
	if prompt_ok and type(prompt_module.set_sink) == "function" then
		prompt_module.set_sink(terminal_adapter.send)
	end
end

local function toggle_opencode_terminal()
	terminal_adapter.toggle()
end

local function close_opencode_terminal()
	terminal_adapter.close()
end

local function patch_opencode_server_disconnect()
	local server = require("opencode.server")
	if server._nvim_mini_disconnect_patched then
		return
	end

	local disconnect = server.disconnect
	function server:disconnect()
		if self == nil then
			if server.connected then
				return disconnect(server.connected)
			end
			return
		end

		return disconnect(self)
	end

	server._nvim_mini_disconnect_patched = true
end

-- opencode.nvim's own owned prompt flows (<leader>aoB/aoV/aoQ, go/goo, the
-- <leader>aox action picker's prompt entries) all funnel through
-- opencode.api.prompt.prompt(), which delivers via
-- context.server:tui_append_prompt()/tui_execute_command("prompt.submit").
-- Both POST to /tui/publish, which OpenCode's TUI broadcasts to every client
-- attached to the same project directory -- the same multi-tmux-window
-- broadcast bug as <leader>aoS/<leader>aos. Patching these two Server methods
-- (rather than reimplementing prompt.lua's ask/render/clear/resume chain)
-- reroutes delivery through the local composer facade for every one of those
-- callers at once, without touching their existing Promise-chain semantics
-- (context:clear() on success, context:resume()+reject on failure, trailing-
-- space "append only" detection all remain opencode.nvim's own code).
local function patch_opencode_server_prompt_delivery()
	local server = require("opencode.server")
	if server._nvim_mini_prompt_delivery_patched then
		return
	end

	function server:tui_append_prompt(text)
		return require("opencode.promise").new(function(resolve, reject)
			require("config.opencode_prompt").append(text, {
				title = "opencode",
				fallback_clipboard = false,
				silent = true,
				on_success = resolve,
				on_error = reject,
			})
		end)
	end

	local original_tui_execute_command = server.tui_execute_command
	function server:tui_execute_command(command)
		if command ~= "prompt.submit" then
			return original_tui_execute_command(self, command)
		end

		return require("opencode.promise").new(function(resolve, reject)
			require("config.opencode_prompt").submit({
				title = "opencode",
				fallback_clipboard = false,
				silent = true,
				on_success = resolve,
				on_error = reject,
			})
		end)
	end

	server._nvim_mini_prompt_delivery_patched = true
end

local function kickstart_opencode_service()
	if vim.fn.has("macunix") ~= 1 then
		return
	end

	vim.fn.jobstart({
		"launchctl",
		"kickstart",
		"gui/" .. vim.fn.system({ "id", "-u" }):gsub("%s+", "") .. "/" .. opencode_service,
	}, {
		stdout_buffered = true,
		stderr_buffered = true,
	})
end

local function resolve_opencode_url(callback)
	local kicked = false
	local deadline = vim.uv.now() + opencode_startup_timeout

	local function poll()
		check_opencode_ready(function(ready)
			if ready then
				callback("http://127.0.0.1:" .. opencode_port)
				return
			end

			if not kicked then
				kicked = true
				kickstart_opencode_service()
			end

			if vim.uv.now() >= deadline then
				vim.notify(
					"Timed out waiting for OpenCode on port " .. opencode_port,
					vim.log.levels.ERROR,
					{ title = "opencode" }
				)
				callback(nil)
				return
			end

			vim.defer_fn(poll, opencode_startup_poll)
		end)
	end

	poll()
end

local function opencode_opts(auth)
	auth = auth or current_opencode_auth()
	return assign_server_auth({
		server = {
			url = resolve_opencode_url,
			start = start_opencode_terminal,
			toggle = toggle_opencode_terminal,
			stop = close_opencode_terminal,
		},
		events = {
			enabled = true,
			reload = false,
			permissions = {
				enabled = true,
				idle_delay_ms = 1000,
			},
		},
		lsp = {
			enabled = true,
		},
	}, auth)
end

local function apply_opencode_opts()
	local auth = current_opencode_auth()
	local resolved = opencode_opts(auth)
	local global_opts = vim.tbl_deep_extend("force", vim.g.opencode_opts or {}, resolved)
	assign_server_auth(global_opts, auth)
	vim.g.opencode_opts = global_opts

	local config = package.loaded["opencode.config"]
	if type(config) == "table" and type(config.opts) == "table" then
		config.opts = vim.tbl_deep_extend("force", config.opts, resolved)
		assign_server_auth(config.opts, auth)
	end
end

local function with_opencode_ready(action, on_error)
	local ok, ready = pcall(function()
		return require("opencode.server.discovery").get()
	end)

	if not ok then
		if on_error then
			on_error()
		end
		vim.notify("Failed to check OpenCode server: " .. ready, vim.log.levels.ERROR, { title = "opencode" })
		return
	end

	ready
		:next(function(server)
			vim.defer_fn(function()
				local action_ok, err = pcall(action, server)
				if not action_ok then
					vim.notify("OpenCode action failed: " .. err, vim.log.levels.ERROR, { title = "opencode" })
				end
			end, opencode_ready_delay)
		end)
		:catch(function(err)
			if on_error then
				on_error()
			end
			if err then
				vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
			end
		end)
end

local function notify_opencode_error(err)
	if err then
		vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
	end
end

local function prompt_text(value)
	if type(value) == "string" then
		return value
	end
	if type(value) == "table" then
		return value.prompt or value[1]
	end
	return nil
end

local function ask_with_context(prefix)
	return function()
		with_opencode_ready(function(server)
			local context = require("opencode.context").new(server)
			require("opencode.ui.ask")
				.ask(prefix, context)
				:next(function(input)
					local text = (input or ""):gsub("%s+$", "")
					if text == "" then
						context:clear()
						return
					end

					require("opencode.api.prompt").prompt(text .. " ", context):catch(notify_opencode_error)
				end)
				:catch(notify_opencode_error)
		end)
	end
end

local function strip_vcs_prefix(bufname)
	return bufname
		:gsub("^diffview://", "")
		:gsub("^[a-f0-9]+:", "")
		:gsub("^%.git/[a-f0-9]+/", "")
end

local function prompt_filepath(bufnr)
	bufnr = bufnr or 0
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname == "" then
		return nil
	end

	local is_diffview = bufname:find("diffview://", 1, true) == 1
	if not is_diffview then
		if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then
			return nil
		end
		if bufname:match("^[%a][%w+.-]*://") then
			return nil
		end
	end

	local filepath = vim.fn.fnamemodify(strip_vcs_prefix(bufname), ":.")
	if filepath == "" or filepath == "." or filepath:match("^%[") then
		return nil
	end
	return filepath
end

local function open_ask_prompt(opts)
	opts = opts or {}
	local return_target = require("config.return_target")
	local source = return_target.capture({ force = true }) or return_target.last()
	local Input = require("nui.input")
	local input
	input = Input({
		relative = "editor",
		position = {
			row = "90%",
			col = "50%",
		},
		size = {
			width = math.min(70, math.max(20, vim.o.columns - 4)),
		},
		border = {
			style = "rounded",
			text = {
				top = " Ask OpenCode ",
				top_align = "center",
			},
		},
		win_options = {
			winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
		},
	}, {
		prompt = "> ",
		default_value = opts.default_value or "",
		on_submit = opts.on_submit,
		on_close = opts.on_close,
	})

	local function close()
		input:unmount()
	end

	input:map("n", "<Esc>", close, { noremap = true, nowait = true, desc = "Close opencode prompt" })
	input:map("n", "q", close, { noremap = true, nowait = true, desc = "Close opencode prompt" })
	-- Plain <leader> (Space) is prompt text in Insert mode, so mirror the
	-- terminal-mode bridge: exit to Normal mode, then replay Space so it
	-- recursively resolves as the leader trigger for Normal-mode maps.
	input:map("i", "<C-Space>", [[<Esc><Space>]], { remap = true, nowait = true, desc = "Start leader from prompt" })

	input:mount()
	require("config.fzf_prompt").bind(input.bufnr, {
		mode = "n",
		source = source,
		insert = function(text)
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(input.bufnr) or not vim.api.nvim_win_is_valid(input.winid) then
					return
				end
				local line = vim.api.nvim_buf_get_lines(input.bufnr, 0, 1, false)[1] or ""
				local separator = line:match("%s$") and "" or " "
				vim.api.nvim_buf_set_text(input.bufnr, 0, #line, 0, #line, { separator .. text })
				vim.api.nvim_set_current_win(input.winid)
				vim.cmd("startinsert!")
			end)
		end,
		restore = function()
			if vim.api.nvim_win_is_valid(input.winid) then
				vim.api.nvim_set_current_win(input.winid)
				vim.cmd("startinsert!")
			end
		end,
	})
	if opts.opencode_completion then
		vim.bo[input.bufnr].filetype = "opencode_ask"
		pcall(vim.lsp.start, require("opencode.ui.ask.cmp"), { bufnr = input.bufnr })
	end

	return input
end

local function setup_opencode_prompt_input()
	local ui = require("opencode.promise.ui")
	if ui._nvim_mini_nui_input then
		return
	end

	ui.input = function(opts)
		opts = opts or {}
		return require("opencode.promise").new(function(resolve, reject)
			open_ask_prompt({
				default_value = opts.default,
				on_submit = resolve,
				on_close = reject,
				opencode_completion = true,
			})
		end)
	end
	ui._nvim_mini_nui_input = true
end

-- Visual-mode Lua keymaps run their callback *before* Neovim commits '< '>
-- for the current selection, so reading those marks here would return the
-- previous selection's range. Read the live visual anchor/cursor instead
-- while still in Visual mode, falling back to '< '> outside of it (e.g. gv).
local function get_visual_range()
	local mode = vim.fn.mode()
	local start_pos, end_pos
	if mode == "v" or mode == "V" or mode == "\22" then
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")
	else
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
	end
	local sl, el = start_pos[2], end_pos[2]
	if sl == 0 or el == 0 then
		return nil, nil
	end
	if sl > el then
		sl, el = el, sl
	end
	return sl, el
end

local function submit_prompt_locally(text, opts)
	opts = opts or {}
	require("config.opencode_prompt").append_and_submit(text, {
		title = "opencode",
		success = opts.success or "Sent to OpenCode",
		fallback_clipboard = false,
		dir = opts.dir,
	})
end

local function ask_locally()
	return function()
		local filepath = prompt_filepath()
		local line_number = vim.api.nvim_win_get_cursor(0)[1]
		local line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1] or ""
		local file_ctx = filepath and ("[file: " .. filepath .. ", line " .. line_number .. "]\n" .. line .. "\n") or ""

		open_ask_prompt({
			on_submit = function(input)
				if not input or input == "" then
					return
				end
				submit_prompt_locally(file_ctx .. input)
			end,
		})
	end
end

local function ask_locally_visual()
	local filepath = prompt_filepath()
	local sl, el = get_visual_range()
	if not sl then
		vim.notify("No selection", vim.log.levels.WARN, { title = "opencode" })
		return
	end
	local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
	if #lines == 0 then
		vim.notify("No selection", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local header = filepath and ("[file: " .. filepath .. ", lines " .. sl .. "-" .. el .. "]\n") or ""
	local selection_text = header .. table.concat(lines, "\n") .. "\n"

	open_ask_prompt({
		on_submit = function(input)
			if not input or input == "" then
				return
			end
			submit_prompt_locally(selection_text .. input)
		end,
	})
end

local function run_named_prompt_locally(name, opts)
	opts = opts or {}
	return function()
		local filepath = prompt_filepath()
		local file_ctx = filepath and ("[file: " .. filepath .. "]\n") or ""

		local selection_ctx = ""
		if opts.with_selection then
			local sl, el = get_visual_range()
			if sl then
				local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
				if #lines > 0 then
					selection_ctx = "```\n" .. table.concat(lines, "\n") .. "\n```\n"
				end
			end
		end

		local ok, config = pcall(function()
			return require("opencode.config").opts
		end)
		local prompt = ok and config
			and ((config.prompts and config.prompts[name]) or (config.select and config.select.prompts and config.select.prompts[name]))
		local text = prompt_text(prompt) or name
		local function send(final_text)
			submit_prompt_locally(file_ctx .. selection_ctx .. final_text)
		end

		if type(prompt) == "table" and prompt.ask then
			open_ask_prompt({
				on_submit = function(input)
					if not input or input == "" then
						return
					end
					send(text .. input)
				end,
			})
		else
			send(text)
		end
	end
end

local function run_command(command)
	return function()
		with_opencode_ready(function(server)
			require("opencode.api.command").command(command, server):catch(notify_opencode_error)
		end)
	end
end

local function select_opencode_session()
	require("config.opencode_pickers").sessions("all", { session_scope = "local" })
end


local function send_visual_selection()
	local start_line, end_line = get_visual_range()
	if not start_line then
		vim.notify("No selection to send", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	if #lines == 0 then
		vim.notify("No selection to send", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local filepath = prompt_filepath()
	local header = filepath and ("[file: " .. filepath .. ", lines " .. start_line .. "-" .. end_line .. "]\n") or ""

	require("config.opencode_prompt").append(header .. table.concat(lines, "\n"), {
		title = "opencode",
		success = "Sent selection to OpenCode",
		fallback_clipboard = true,
	})
end

return {
	{
		"nickjvandyke/opencode.nvim",
		version = "*",
		dependencies = {
			"akinsho/toggleterm.nvim",
			"MunifTanjim/nui.nvim",
		},
		lazy = vim.env.NVIM_OPEN_OPENCODE ~= "1",
		cmd = { "Opencode" },
		init = apply_opencode_opts,
		keys = {
			-- Toggle opencode terminal
			{
				"<leader>aoc",
				function()
					toggle_opencode_terminal()
				end,
				mode = { "n", "t" },
				desc = "Toggle opencode",
			},
			-- Quick toggle (global shortcut)
			{
				"<C-.>",
				function()
					toggle_opencode_terminal()
				end,
				mode = { "n", "t" },
				desc = "Toggle opencode",
			},
			-- Ask opencode with current file context in this Neovim's local terminal
			{
				"<leader>aoa",
				ask_locally(),
				mode = "n",
				desc = "Ask opencode",
			},
			{
				"<leader>aoa",
				ask_locally_visual,
				mode = "x",
				desc = "Ask opencode (with selection)",
			},
			{
				"<leader>aos",
				ask_locally(),
				mode = "n",
				desc = "Ask opencode (append to prompt)",
			},
			{
				"<leader>aos",
				ask_locally_visual,
				mode = "x",
				desc = "Ask opencode (append selection to prompt)",
			},
			{
				"<leader>aoS",
				send_visual_selection,
				mode = "x",
				desc = "Send selection to OpenCode prompt",
			},
			{
				"<leader>aoB",
				ask_with_context("@buffer: "),
				mode = "n",
				desc = "Ask current buffer",
			},
			{
				"<leader>aoV",
				ask_with_context("@visible: "),
				mode = "n",
				desc = "Ask visible windows",
			},
			{
				"<leader>aoQ",
				ask_with_context("@quickfix: "),
				mode = "n",
				desc = "Ask quickfix list",
			},
			-- Action picker
			{
				"<leader>aox",
				function()
					require("opencode").select()
				end,
				mode = { "n", "x" },
				desc = "opencode actions",
			},
			-- Operator-pending mode (select range then type prompt)
			{
				"go",
				function()
					return require("opencode").operator("@this ")
				end,
				mode = { "n", "x" },
				desc = "Add range to opencode",
				expr = true,
			},
			{
				"goo",
				function()
					return require("opencode").operator("@this ") .. "_"
				end,
				mode = "n",
				desc = "Add line to opencode",
				expr = true,
			},
		-- Named prompts
		{
			"<leader>aoe",
			run_named_prompt_locally("explain"),
			mode = "n",
			desc = "Explain (opencode)",
		},
		{
			"<leader>aoe",
			run_named_prompt_locally("explain", { with_selection = true }),
			mode = "x",
			desc = "Explain (opencode)",
		},
		{
			"<leader>aof",
			run_named_prompt_locally("fix"),
			mode = "n",
			desc = "Fix diagnostics (opencode)",
		},
		{
			"<leader>aof",
			run_named_prompt_locally("fix", { with_selection = true }),
			mode = "x",
			desc = "Fix diagnostics (opencode)",
		},
		{
			"<leader>aor",
			run_named_prompt_locally("review"),
			mode = "n",
			desc = "Review (opencode)",
		},
		{
			"<leader>aor",
			run_named_prompt_locally("review", { with_selection = true }),
			mode = "x",
			desc = "Review (opencode)",
		},
		{
			"<leader>aot",
			run_named_prompt_locally("test"),
			mode = "n",
			desc = "Add tests (opencode)",
		},
		{
			"<leader>aot",
			run_named_prompt_locally("test", { with_selection = true }),
			mode = "x",
			desc = "Add tests (opencode)",
		},
		{
			"<leader>aod",
			run_named_prompt_locally("document"),
			mode = "n",
			desc = "Document (opencode)",
		},
		{
			"<leader>aod",
			run_named_prompt_locally("document", { with_selection = true }),
			mode = "x",
			desc = "Document (opencode)",
		},
		{
			"<leader>aoo",
			run_named_prompt_locally("optimize"),
			mode = "n",
			desc = "Optimize (opencode)",
		},
		{
			"<leader>aoo",
			run_named_prompt_locally("optimize", { with_selection = true }),
			mode = "x",
			desc = "Optimize (opencode)",
		},
		{
			"<leader>aoi",
			run_named_prompt_locally("implement"),
			mode = "n",
			desc = "Implement (opencode)",
		},
		{
			"<leader>aoi",
			run_named_prompt_locally("implement", { with_selection = true }),
			mode = "x",
			desc = "Implement (opencode)",
		},
		{
			"<leader>aoE",
			run_named_prompt_locally("diagnostics"),
			mode = "n",
			desc = "Explain diagnostics (opencode)",
		},
		{
			"<leader>aoE",
			run_named_prompt_locally("diagnostics", { with_selection = true }),
			mode = "x",
			desc = "Explain diagnostics (opencode)",
		},
			-- Session and agent controls
			{
				"<leader>aon",
				run_command("session.new"),
				mode = "n",
				desc = "New opencode session",
			},
			{
				"<leader>aop",
				select_opencode_session,
				mode = "n",
				desc = "Pick opencode session",
			},
			{
				"<leader>aom",
				run_command("session.compact"),
				mode = "n",
				desc = "Compact opencode session",
			},
			{
				"<leader>aou",
				run_command("session.undo"),
				mode = "n",
				desc = "Undo opencode action",
			},
			{
				"<leader>aoU",
				run_command("session.redo"),
				mode = "n",
				desc = "Redo opencode action",
			},
			{
				"<leader>aoA",
				run_command("agent.cycle"),
				mode = "n",
				desc = "Cycle opencode agent",
			},
			-- Conversation pickers
			{
				"<leader>ao/",
				function()
					require("config.opencode_pickers").all()
				end,
				mode = "n",
				desc = "Search opencode messages",
			},
			{
				"<leader>aoP",
				function()
					require("config.opencode_pickers").prompts()
				end,
				mode = "n",
				desc = "Search opencode prompts",
			},
			{
				"<leader>aoL",
				function()
					require("config.opencode_pickers").assistant()
				end,
				mode = "n",
				desc = "Search opencode assistant output",
			},
			{
				"<leader>aoT",
				function()
					require("config.opencode_pickers").tools()
				end,
				mode = "n",
				desc = "Search opencode tool calls",
			},
			{
				"<leader>aoR",
				function()
					require("config.opencode_pickers").reasoning()
				end,
				mode = "n",
				desc = "Search opencode reasoning",
			},
			{
				"<leader>aoO",
				function()
					require("config.opencode_pickers").tool_output()
				end,
				mode = "n",
				desc = "Search opencode tool output",
			},
			{
				"<leader>aoG",
				function()
					require("config.opencode_pickers").all_sessions("all", { session_scope = "local" })
				end,
				mode = "n",
				desc = "Search local opencode messages across sessions",
			},
		{
			"<leader>aoH",
			function()
				require("config.opencode_pickers").sessions("all", { session_scope = "local" })
			end,
			mode = "n",
			desc = "Browse local opencode session history",
		},
		{
			"<leader>aoF",
			function()
				require("config.opencode_pickers").forkpane()
			end,
			mode = "n",
			desc = "Fork opencode session into new pane",
		},
		{
			"<leader>aoW",
			function()
				require("config.opencode_pickers").gwtfork()
			end,
			mode = "n",
			desc = "Fork opencode session into new worktree",
		},
			{
				"<leader>aog",
				function()
					require("config.opencode_pickers").grep()
				end,
				mode = "n",
				desc = "Grep opencode messages (live rg)",
			},
		},
		config = function()
			apply_opencode_opts()
			local config_ok, config = pcall(require, "opencode.config")
			local commands = config_ok
				and type(config) == "table"
				and type(config.opts) == "table"
				and config.opts.select
				and config.opts.select.commands
			if commands then
				commands["session.select"] = nil
			end
			patch_opencode_server_disconnect()
			patch_opencode_server_prompt_delivery()
			setup_opencode_prompt_input()
			require("config.opencode_status").setup()

			-- Required for auto-reload when opencode edits files
			vim.o.autoread = true

			-- Worktree launchers (gwtt, worktrunk-open-window.sh) set this to land
			-- directly in the editor + opencode split instead of a bare buffer.
			-- NVIM_OPEN_TOGGLETERM additionally opens the ordinary project shell
			-- alongside it in the coordinated editor+shell+OCV layout; without it,
			-- OCV-only callers keep their existing bare-split behavior unchanged.
			if vim.env.NVIM_OPEN_OPENCODE == "1" then
				vim.api.nvim_create_autocmd("VimEnter", {
					once = true,
					callback = function()
						vim.defer_fn(function()
							if vim.env.NVIM_OPEN_TOGGLETERM == "1" then
								open_worktree_layout()
							else
								open_opencode_terminal()
							end
						end, 0)
					end,
				})
			end

			vim.api.nvim_create_user_command("OpenCodeFocus", function()
				local dir = project_root()
				terminal_adapter.open(dir)
				if vim.bo.buftype == "terminal" then
					vim.cmd("startinsert")
				end
			end, { force = true, desc = "Focus (or open) this worktree's OpenCode terminal" })

			vim.api.nvim_create_user_command("OpenCodeWorktreeLayout", function()
				open_worktree_layout()
			end, { force = true, desc = "Build the coordinated editor+shell+OCV worktree layout" })
		end,
	},
}

-- opencode.nvim - AI coding agent integration
-- Connects to the launchd-managed OpenCode server via HTTP + SSE
-- Shares editor context (buffers, selections, diagnostics) with the agent

local opencode_port = 4096
local opencode_ready_delay = 500
local opencode_startup_timeout = 30000
local opencode_startup_poll = 500
local opencode_service = "com.dotfiles.opencode-serve"
local opencode_username = vim.env.OPENCODE_SERVER_USERNAME or "opencode"
local opencode_terminal
local opencode_terminal_cmd
local opencode_ask_model = { provider = "anthropic", model = "claude-sonnet-5" }

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

local function opencode_env_prefix()
	-- The dotfiles opencode shim reroutes `attach` through tmux when $TMUX is set.
	-- This terminal already owns the split, so bypass that wrapper and run ocv directly.
	-- OPENTUI_GRAPHICS=0: suppress Kitty graphics probing which segfaults in nvim :terminal.
	local base = "OPENCODE_TMUX_WRAPPER_ACTIVE=1 OPENTUI_GRAPHICS=0 OPENCODE_SERVER_USERNAME="
		.. vim.fn.shellescape(opencode_username)
	local password = opencode_password()
	if not password or password == "" then
		return base .. " "
	end

	return base
		.. " OPENCODE_SERVER_PASSWORD="
		.. vim.fn.shellescape(password)
		.. " "
end

local function opencode_command()
	return opencode_env_prefix()
		.. "ocv attach http://127.0.0.1:"
		.. opencode_port
		.. " --dir "
		.. vim.fn.shellescape(vim.fn.getcwd())
end

local function get_opencode_terminal()
	local cmd = opencode_command()
	if opencode_terminal and opencode_terminal_cmd == cmd then
		return opencode_terminal
	end

	local Terminal = require("toggleterm.terminal").Terminal
	opencode_terminal_cmd = cmd
	opencode_terminal = Terminal:new({
		cmd = cmd,
		direction = "vertical",
		dir = vim.fn.getcwd(),
		display_name = "OpenCode",
		hidden = true,
		close_on_exit = false,
		on_exit = function(_, _, exit_code)
			if exit_code ~= 0 then
				vim.notify("OpenCode terminal exited with code " .. exit_code, vim.log.levels.ERROR, { title = "opencode" })
			end
		end,
		size = function()
			return math.floor(vim.o.columns * 0.5)
		end,
	})
	return opencode_terminal
end

local function check_opencode_ready(callback)
	local curl_args = {
		"curl",
		"-fsS",
		"--max-time",
		"1",
	}
	local password = opencode_password()
	if password and password ~= "" then
		vim.list_extend(curl_args, { "-u", opencode_username .. ":" .. password })
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

local function start_opencode_terminal()
	get_opencode_terminal():open()
end

local function toggle_opencode_terminal()
	get_opencode_terminal():toggle()
end

local function close_opencode_terminal()
	if opencode_terminal then
		opencode_terminal:close()
	end
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

local function resolve_opencode_port(callback)
	local kicked = false
	local deadline = vim.uv.now() + opencode_startup_timeout

	local function poll()
		check_opencode_ready(function(ready)
			if ready then
				callback(opencode_port)
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

local function opencode_opts()
	return {
		server = {
			port = resolve_opencode_port,
			username = opencode_username,
			password = opencode_password(),
			start = start_opencode_terminal,
			toggle = toggle_opencode_terminal,
			stop = close_opencode_terminal,
		},
		events = {
			enabled = true,
			reload = true,
			permissions = {
				enabled = true,
				idle_delay_ms = 1000,
			},
		},
		lsp = {
			enabled = true,
		},
	}
end

local function apply_opencode_opts()
	vim.g.opencode_opts = vim.tbl_deep_extend("force", vim.g.opencode_opts or {}, opencode_opts())

	local config = package.loaded["opencode.config"]
	if config and config.opts then
		config.opts = vim.tbl_deep_extend("force", config.opts, opencode_opts())
	end
end

local function with_opencode_ready(action, on_error)
	local ok, ready = pcall(function()
		return require("opencode.server").get()
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

local function submit_prompt(text, server, context)
	text = (text or ""):gsub("%s+$", "")
	if text == "" then
		context:clear()
		return
	end

	require("opencode.api.prompt").prompt(text, server, context):catch(notify_opencode_error)
end

local function append_prompt(text, server, context)
	text = (text or ""):gsub("%s+$", "")
	if text == "" then
		context:clear()
		return
	end

	require("opencode.api.prompt").prompt(text .. " ", server, context):catch(notify_opencode_error)
end

local function ask_with_context(prefix, submit)
	return function()
		local context = require("opencode.context").new()
		with_opencode_ready(function(server)
			require("opencode.ui.ask")
				.ask(prefix, server, context)
				:next(function(input)
					if submit then
						submit_prompt(input, server, context)
					else
						append_prompt(input, server, context)
					end
				end)
				:catch(function(err)
					context:resume()
					notify_opencode_error(err)
				end)
		end, function()
			context:clear()
		end)
	end
end

local function strip_vcs_prefix(bufname)
	return bufname
		:gsub("^diffview://", "")
		:gsub("^[a-f0-9]+:", "")
		:gsub("^%.git/[a-f0-9]+/", "")
end

local function ask_via_http(opts)
	opts = opts or {}
	return function()
		local bufname = vim.api.nvim_buf_get_name(0)
		local filepath = vim.fn.fnamemodify(strip_vcs_prefix(bufname), ":.")
		local file_ctx = (filepath ~= "" and filepath ~= "." and not filepath:match("^%["))
			and ("[file: " .. filepath .. "]\n")
			or ""

		vim.ui.input({ prompt = "Ask OpenCode: " }, function(input)
			if not input or input == "" then
				return
			end
			local http = require("config.opencode_http")
			local text = file_ctx .. input

			if opts.model then
				http.send_with_model(text, opts.model.provider, opts.model.model, {
					title = "opencode",
					success = "Sent to OpenCode",
				})
			else
				http.append_prompt(text, {
					title = "opencode",
					success = "Sent to OpenCode",
					fallback_clipboard = false,
					on_success = function()
						http.publish_command("prompt.submit", function(ok, out)
							if not ok then
								vim.notify(
									"OpenCode submit failed: " .. (out or ""),
									vim.log.levels.WARN,
									{ title = "opencode" }
								)
							end
						end)
					end,
				})
			end
		end)
	end
end

local function ask_via_http_visual()
	local bufname = vim.api.nvim_buf_get_name(0)
	local filepath = vim.fn.fnamemodify(strip_vcs_prefix(bufname), ":.")
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local sl, el = start_pos[2], end_pos[2]
	if sl == 0 or el == 0 then
		vim.notify("No selection", vim.log.levels.WARN, { title = "opencode" })
		return
	end
	if sl > el then
		sl, el = el, sl
	end
	local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
	if #lines == 0 then
		vim.notify("No selection", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local header = (filepath ~= "" and filepath ~= "." and not filepath:match("^%["))
		and ("[file: " .. filepath .. ", lines " .. sl .. "-" .. el .. "]\n")
		or ""
	local selection_text = header .. table.concat(lines, "\n") .. "\n"

	vim.ui.input({ prompt = "Ask OpenCode: " }, function(input)
		if not input or input == "" then
			return
		end
		local http = require("config.opencode_http")
		http.send_with_model(selection_text .. input, opencode_ask_model.provider, opencode_ask_model.model, {
			title = "opencode",
			success = "Sent to OpenCode",
		})
	end)
end

local function run_prompt_via_http(name, opts)
	opts = opts or {}
	return function()
		local bufname = vim.api.nvim_buf_get_name(0)
		local filepath = vim.fn.fnamemodify(strip_vcs_prefix(bufname), ":.")
		local file_ctx = (filepath ~= "" and filepath ~= "." and not filepath:match("^%["))
			and ("[file: " .. filepath .. "]\n")
			or ""

		local selection_ctx = ""
		if opts.with_selection then
			local start_pos = vim.fn.getpos("'<")
			local end_pos = vim.fn.getpos("'>")
			local sl, el = start_pos[2], end_pos[2]
			if sl > 0 and el > 0 then
				if sl > el then
					sl, el = el, sl
				end
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

		local http = require("config.opencode_http")
		local function send(final_text)
			http.send_with_model(
				file_ctx .. selection_ctx .. final_text,
				opencode_ask_model.provider,
				opencode_ask_model.model,
				{ title = "opencode", success = "Sent to OpenCode" }
			)
		end

		if type(prompt) == "table" and prompt.ask then
			vim.ui.input({ prompt = text }, function(input)
				if not input or input == "" then
					return
				end
				send(text .. input)
			end)
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
	with_opencode_ready(function(server)
		require("opencode.ui.select_session")
			.select_session(server)
			:next(function(session)
				return server:select_session(session.id)
			end)
			:catch(notify_opencode_error)
	end)
end


local function send_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local start_line = start_pos[2]
	local end_line = end_pos[2]
	if start_line == 0 or end_line == 0 then
		vim.notify("No selection to send", vim.log.levels.WARN, { title = "opencode" })
		return
	end
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	if #lines == 0 then
		vim.notify("No selection to send", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local bufname = vim.api.nvim_buf_get_name(0)
	local filepath = vim.fn.fnamemodify(strip_vcs_prefix(bufname), ":.")
	local header = (filepath ~= "" and filepath ~= "." and not filepath:match("^%["))
		and ("[file: " .. filepath .. ", lines " .. start_line .. "-" .. end_line .. "]\n")
		or ""

	require("config.opencode_tmux").append_prompt(header .. table.concat(lines, "\n"), {
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
		},
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
		-- Ask opencode with current file context via HTTP (no plugin server required)
			{
				"<leader>aoa",
				ask_via_http({ model = opencode_ask_model }),
				mode = "n",
				desc = "Ask opencode",
			},
			{
				"<leader>aoa",
				ask_via_http_visual,
				mode = "x",
				desc = "Ask opencode (with selection)",
			},
			{
				"<leader>aos",
				ask_via_http(),
				mode = { "n", "x" },
				desc = "Ask opencode (append to prompt)",
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
			{
				"<leader>aoM",
				function()
					local http = require("config.opencode_http")
					http.get_models(function(models, err)
						if not models or #models == 0 then
							vim.notify(err or "No models found", vim.log.levels.ERROR, { title = "opencode" })
							return
						end
						vim.ui.select(models, {
							prompt = "Ask model:",
							format_item = function(item)
								return item.label
							end,
						}, function(choice)
							if not choice then
								return
							end
							opencode_ask_model = { provider = choice.provider, model = choice.model }
							vim.notify("Ask model → " .. choice.label, vim.log.levels.INFO, { title = "opencode" })
						end)
					end)
				end,
				mode = { "n", "x" },
				desc = "Select opencode ask model",
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
			run_prompt_via_http("explain"),
			mode = "n",
			desc = "Explain (opencode)",
		},
		{
			"<leader>aoe",
			run_prompt_via_http("explain", { with_selection = true }),
			mode = "x",
			desc = "Explain (opencode)",
		},
		{
			"<leader>aof",
			run_prompt_via_http("fix"),
			mode = "n",
			desc = "Fix diagnostics (opencode)",
		},
		{
			"<leader>aof",
			run_prompt_via_http("fix", { with_selection = true }),
			mode = "x",
			desc = "Fix diagnostics (opencode)",
		},
		{
			"<leader>aor",
			run_prompt_via_http("review"),
			mode = "n",
			desc = "Review (opencode)",
		},
		{
			"<leader>aor",
			run_prompt_via_http("review", { with_selection = true }),
			mode = "x",
			desc = "Review (opencode)",
		},
		{
			"<leader>aot",
			run_prompt_via_http("test"),
			mode = "n",
			desc = "Add tests (opencode)",
		},
		{
			"<leader>aot",
			run_prompt_via_http("test", { with_selection = true }),
			mode = "x",
			desc = "Add tests (opencode)",
		},
		{
			"<leader>aod",
			run_prompt_via_http("document"),
			mode = "n",
			desc = "Document (opencode)",
		},
		{
			"<leader>aod",
			run_prompt_via_http("document", { with_selection = true }),
			mode = "x",
			desc = "Document (opencode)",
		},
		{
			"<leader>aoo",
			run_prompt_via_http("optimize"),
			mode = "n",
			desc = "Optimize (opencode)",
		},
		{
			"<leader>aoo",
			run_prompt_via_http("optimize", { with_selection = true }),
			mode = "x",
			desc = "Optimize (opencode)",
		},
		{
			"<leader>aoi",
			run_prompt_via_http("implement"),
			mode = "n",
			desc = "Implement (opencode)",
		},
		{
			"<leader>aoi",
			run_prompt_via_http("implement", { with_selection = true }),
			mode = "x",
			desc = "Implement (opencode)",
		},
		{
			"<leader>aoE",
			run_prompt_via_http("diagnostics"),
			mode = "n",
			desc = "Explain diagnostics (opencode)",
		},
		{
			"<leader>aoE",
			run_prompt_via_http("diagnostics", { with_selection = true }),
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
					require("config.opencode_pickers").all_sessions("all")
				end,
				mode = "n",
				desc = "Search all opencode sessions",
			},
		{
			"<leader>aoH",
			function()
				require("config.opencode_pickers").sessions("all")
			end,
			mode = "n",
			desc = "Search opencode session history",
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
			patch_opencode_server_disconnect()

			-- Required for auto-reload when opencode edits files
			vim.o.autoread = true

			-- Track opencode status for statusline via OpencodeEvent autocmds
			vim.api.nvim_create_autocmd("User", {
				pattern = "OpencodeEvent:session.status",
				callback = function(args)
					local event = args.data and args.data.event
					vim.g.opencode_status = event and event.properties and event.properties.status.type or nil
				end,
			})
			vim.api.nvim_create_autocmd("User", {
				pattern = "OpencodeEvent:file.edited",
				callback = function()
					vim.cmd("checktime")
				end,
			})
			vim.api.nvim_create_autocmd("User", {
				pattern = "OpencodeEvent:server.connected",
				callback = function()
					vim.g.opencode_status = "connected"
				end,
			})
			vim.api.nvim_create_autocmd("User", {
				pattern = "OpencodeEvent:server.instance.disposed",
				callback = function()
					vim.g.opencode_status = nil
				end,
			})
		end,
	},
}

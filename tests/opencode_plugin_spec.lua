package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function mode_includes(mode, target)
	if type(mode) == "string" then
		return mode == target
	end
	if type(mode) == "table" then
		return vim.tbl_contains(mode, target)
	end
	return false
end

local original_auth_env = {
	username = vim.env.OPENCODE_SERVER_USERNAME,
	password = vim.env.OPENCODE_SERVER_PASSWORD,
	state_home = vim.env.XDG_STATE_HOME,
	open_opencode = vim.env.NVIM_OPEN_OPENCODE,
}
vim.env.OPENCODE_SERVER_USERNAME = "opencode-spec-user-1"
vim.env.OPENCODE_SERVER_PASSWORD = "opencode-spec-password-1"
vim.env.XDG_STATE_HOME = "/tmp/opencode-plugin-spec-missing-state"
vim.env.NVIM_OPEN_OPENCODE = nil

-- ===== Section 1: toggleterm resize-on-reopen fix =====

local recorded_terminal_calls = {}
local opencode_terminal_opts
local record_auth_lifecycle = false
local auth_lifecycle = {}

package.loaded["toggleterm.terminal"] = {
	Terminal = {
		new = function(_, term)
			if record_auth_lifecycle then
				table.insert(auth_lifecycle, "create-new")
			end
			opencode_terminal_opts = term
			term.__is_open = false
			term.__alive = false
			term.is_open = function(self)
				return self.__is_open
			end
			term.spawn = function(self)
				table.insert(recorded_terminal_calls, { action = "spawn" })
				self.job_id = self.job_id or 1001
				self.__alive = true
			end
			term.open = function(self, size)
				table.insert(recorded_terminal_calls, { action = "open", size = size })
				self.__is_open = true
			end
			term.toggle = function(self, size)
				if self.__is_open then
					table.insert(recorded_terminal_calls, { action = "close" })
					self.__is_open = false
				else
					table.insert(recorded_terminal_calls, { action = "open_via_toggle", size = size })
					self.__is_open = true
				end
			end
			term.close = function(self)
				self.__is_open = false
			end
			term.shutdown = function(self)
				table.insert(recorded_terminal_calls, { action = "shutdown" })
				if record_auth_lifecycle then
					table.insert(auth_lifecycle, "shutdown-old")
				end
				self.__is_open = false
				self.__alive = false
			end
			return term
		end,
	},
}

package.loaded["config.opencode_terminal"] = dofile("lua/config/opencode_terminal.lua")
local original_status_bridge = package.loaded["config.opencode_status"]
local status_setup_calls = 0
package.loaded["config.opencode_status"] = {
	setup = function()
		status_setup_calls = status_setup_calls + 1
	end,
}
local plugin_specs = dofile("lua/plugins/opencode.lua")
eq(plugin_specs[1].lazy, true, "ordinary editor startup keeps opencode.nvim lazy-loaded")
local terminal_adapter = require("config.opencode_terminal")
terminal_adapter.__set_test_hooks({
	terminal_live = function(term)
		return term.__alive == true
	end,
})

local toggle_terminal
for _, key in ipairs(plugin_specs[1].keys) do
	if key[1] == "<leader>aoc" and mode_includes(key.mode, "n") then
		toggle_terminal = key[2]
		break
	end
end
assert(toggle_terminal, "<leader>aoc toggle mapping is present")

local history_mapping
local aggregate_mapping
local select_session_mapping
local history_desc
local aggregate_desc
for _, key in ipairs(plugin_specs[1].keys) do
	if key[1] == "<leader>aoH" and mode_includes(key.mode, "n") then
		history_mapping = key[2]
		history_desc = key.desc
	elseif key[1] == "<leader>aoG" and mode_includes(key.mode, "n") then
		aggregate_mapping = key[2]
		aggregate_desc = key.desc
	elseif key[1] == "<leader>aop" and mode_includes(key.mode, "n") then
		select_session_mapping = key[2]
	end
end
assert(history_mapping and aggregate_mapping and select_session_mapping, "OpenCode history and session mappings are present")
local picker_dispatches = {}
local original_pickers = package.loaded["config.opencode_pickers"]
package.loaded["config.opencode_pickers"] = {
	sessions = function(scope, opts)
		table.insert(picker_dispatches, { kind = "history", scope = scope, opts = opts })
	end,
	all_sessions = function(scope, opts)
		table.insert(picker_dispatches, { kind = "aggregate", scope = scope, opts = opts })
	end,
}
local original_discovery_for_session_mapping = package.loaded["opencode.server.discovery"]
package.loaded["opencode.server.discovery"] = {
	get = function() error("the custom session mapping must not use upstream discovery") end,
}
history_mapping()
aggregate_mapping()
select_session_mapping()
eq(picker_dispatches[1], { kind = "history", scope = "all", opts = { session_scope = "local" } }, "session history starts in Local scope")
eq(picker_dispatches[2], { kind = "aggregate", scope = "all", opts = { session_scope = "local" } }, "aggregate message search starts in Local scope")
eq(picker_dispatches[3], { kind = "history", scope = "all", opts = { session_scope = "local" } }, "session selection uses the guarded Local history picker")
assert(history_desc:match("local"), "session history description documents its Local default")
assert(aggregate_desc:match("local"), "aggregate search description documents its Local default")
package.loaded["config.opencode_pickers"] = original_pickers
package.loaded["opencode.server.discovery"] = original_discovery_for_session_mapping

vim.o.columns = 200
toggle_terminal() -- starts closed -> opens
eq(#recorded_terminal_calls, 2, "first <leader>aoc press spawns once and performs one visible terminal action")
eq(recorded_terminal_calls[1], { action = "spawn" }, "first manual open starts the terminal process")
eq(recorded_terminal_calls[2], { action = "open_via_toggle", size = 100 }, "first open resolves a fresh explicit size (50%% of columns), not toggleterm's global/persisted default")

toggle_terminal() -- closes
eq(recorded_terminal_calls[3], { action = "shutdown" }, "second press destructively shuts down the visible terminal")
local first_toggle_terminal = opencode_terminal_opts
eq(first_toggle_terminal.__alive, false, "destructive toggle stops the old terminal process")

vim.o.columns = 140 -- simulate the user resizing Neovim while opencode was closed
toggle_terminal() -- creates and opens a fresh terminal
assert(opencode_terminal_opts ~= first_toggle_terminal, "reopening after a destructive toggle creates a fresh terminal")
eq(
	recorded_terminal_calls[5],
	{ action = "open_via_toggle", size = 70 },
	"fresh reopen recomputes size from the current column count instead of reusing stale width"
)
eq(recorded_terminal_calls[4], { action = "spawn" }, "fresh reopen starts a new terminal process")

plugin_specs[1].init()
assert(type(vim.g.opencode_opts.server.start) == "function", "server.start is wired to start_opencode_terminal")
assert(type(vim.g.opencode_opts.server.url) == "function", "server.url resolves the launchd-managed OpenCode endpoint")
eq(vim.g.opencode_opts.server.port, nil, "the obsolete server.port option is not configured")
eq(vim.g.opencode_opts.events.reload, false, "session-blind SSE reload stays disabled in favor of native targeted batches")
local default_server_terminal = opencode_terminal_opts
local before_stop_calls = #recorded_terminal_calls
vim.g.opencode_opts.server.stop()
eq(
	recorded_terminal_calls[before_stop_calls + 1],
	{ action = "shutdown" },
	"server.stop destructively shuts down the project terminal"
)
eq(default_server_terminal.__alive, false, "server.stop terminates the project terminal process")
vim.g.opencode_opts.server.start()
assert(opencode_terminal_opts ~= default_server_terminal, "server.start after stop creates a fresh project terminal")
eq(recorded_terminal_calls[before_stop_calls + 2], { action = "spawn" }, "server restart starts the fresh terminal process")

local original_jobstart = vim.fn.jobstart
local original_url_schedule = vim.schedule
local resolved_url
vim.fn.jobstart = function(_, opts)
	opts.on_exit(1, 0)
	return 1
end
vim.schedule = function(callback)
	callback()
end
vim.g.opencode_opts.server.url(function(url)
	resolved_url = url
end)
vim.fn.jobstart = original_jobstart
vim.schedule = original_url_schedule
eq(resolved_url, "http://127.0.0.1:4096", "server.url resolves the configured launchd endpoint after readiness succeeds")
local before_explicit_start_calls = #recorded_terminal_calls
vim.g.opencode_opts.server.start("/tmp/opencode-plugin-spec/server-start")
eq(
	recorded_terminal_calls[before_explicit_start_calls + 1],
	{ action = "spawn" },
	"server.start (used by opencode.nvim discovery) starts the terminal without opening a split"
)
eq(#recorded_terminal_calls, before_explicit_start_calls + 1, "server.start performs no visible terminal action")

local first_auth_terminal = opencode_terminal_opts
eq(first_auth_terminal.display_name, "OpenCode", "the terminal keeps its semantic display name")
eq(first_auth_terminal.clear_env, false, "the terminal inherits the editor environment")
local first_auth_env = vim.deepcopy(first_auth_terminal.env)
local first_generation = first_auth_env.OPENCODE_NVIM_GENERATION
first_auth_env.OPENCODE_NVIM_GENERATION = nil
assert(type(first_generation) == "string" and first_generation:match("^nvim_"), "the terminal receives a native handoff generation")
eq(first_auth_env, {
	OPENCODE_TMUX_WRAPPER_ACTIVE = "1",
	OPENTUI_GRAPHICS = "0",
	OPENCODE_SERVER_USERNAME = "opencode-spec-user-1",
	OPENCODE_SERVER_PASSWORD = "opencode-spec-password-1",
	TMUX = "",
	STY = "",
}, "launch credentials and terminal flags are passed as raw environment values")
assert(not first_auth_terminal.cmd:find("opencode-spec-user-1", 1, true), "the username is absent from the terminal command")
assert(not first_auth_terminal.cmd:find("opencode-spec-password-1", 1, true), "the password is absent from the terminal command")
eq(
	first_auth_terminal.cmd,
	"ocv attach http://127.0.0.1:4096 --dir " .. vim.fn.shellescape(first_auth_terminal.dir),
	"the terminal command contains only the attach invocation"
)

local original_auth_config = package.loaded["opencode.config"]
local loaded_auth_config = {
	opts = {
		server = {
			username = "stale-user",
			password = "stale-password",
		},
	},
}
package.loaded["opencode.config"] = loaded_auth_config

vim.env.OPENCODE_SERVER_USERNAME = "opencode-spec-user-2"
vim.env.OPENCODE_SERVER_PASSWORD = "opencode-spec-password-2"
record_auth_lifecycle = true
auth_lifecycle = {}
local revised_auth_terminal = terminal_adapter.get_terminal(first_auth_terminal.dir)
record_auth_lifecycle = false

assert(revised_auth_terminal ~= first_auth_terminal, "changing launch auth replaces the terminal generation")
eq(auth_lifecycle, { "shutdown-old", "create-new" }, "auth replacement shuts down the old terminal before creation")
eq(revised_auth_terminal.env.OPENCODE_SERVER_USERNAME, "opencode-spec-user-2", "replacement receives the new username")
eq(revised_auth_terminal.env.OPENCODE_SERVER_PASSWORD, "opencode-spec-password-2", "replacement receives the new password")
eq(vim.g.opencode_opts.server.username, "opencode-spec-user-2", "global opencode options receive the launch username")
eq(vim.g.opencode_opts.server.password, "opencode-spec-password-2", "global opencode options receive the launch password")
eq(loaded_auth_config.opts.server.username, "opencode-spec-user-2", "loaded config receives the launch username")
eq(loaded_auth_config.opts.server.password, "opencode-spec-password-2", "loaded config receives the launch password")

vim.env.OPENCODE_SERVER_PASSWORD = nil
auth_lifecycle = {}
record_auth_lifecycle = true
local passwordless_terminal = terminal_adapter.get_terminal(first_auth_terminal.dir)
record_auth_lifecycle = false

assert(passwordless_terminal ~= revised_auth_terminal, "clearing the password replaces the authenticated terminal")
eq(auth_lifecycle, { "shutdown-old", "create-new" }, "password clearing retires before replacement")
eq(passwordless_terminal.env.OPENCODE_SERVER_PASSWORD, nil, "the cleared password is omitted from the launch environment")
eq(vim.g.opencode_opts.server.password, nil, "the cleared password is removed from global opencode options")
eq(loaded_auth_config.opts.server.password, nil, "the cleared password is removed from loaded opencode options")

local selected_session_id = "ses_'quoted value'"
local selected_terminal = terminal_adapter.start(first_auth_terminal.dir)
local selected_restart = terminal_adapter.restart_owned(first_auth_terminal.dir, { session_id = selected_session_id })
assert(selected_restart.ok, "plugin launch supports restarting the exact owned terminal into a selected session")
assert(selected_restart.term ~= selected_terminal, "selected-session launch replaces the prior owned terminal")
eq(
	selected_restart.term.cmd,
	"ocv attach http://127.0.0.1:4096 --dir "
		.. vim.fn.shellescape(first_auth_terminal.dir)
		.. " --session "
		.. vim.fn.shellescape(selected_session_id),
	"selected-session launch shell-escapes both route and session ID"
)
assert(not selected_restart.term.cmd:find("opencode-spec-user-2", 1, true), "selected-session command still excludes the username")
assert(not selected_restart.term.cmd:find("opencode-spec-password-2", 1, true), "selected-session command still excludes the password")

package.loaded["opencode.config"] = original_auth_config

print("PASS opencode terminal resize-on-reopen always resolves a fresh explicit size")
print("PASS opencode terminal launch keeps auth out of commands and synchronizes auth revisions")

-- ===== Section 2: current OpenCode API mocks and prompt adapter setup =====

package.loaded["opencode.server"] = {
	disconnect = function(_) end,
}

local function promise_new(executor)
	local promise = {
		status = "pending",
		next_callbacks = {},
		catch_callbacks = {},
	}

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

local Promise = {}
Promise.new = promise_new
Promise.resolve = function(value)
	return promise_new(function(resolve)
		resolve(value)
	end)
end
Promise.reject = function(reason)
	return promise_new(function(_, reject)
		reject(reason)
	end)
end

local server = { id = "server" }
local discovery_calls = 0
package.loaded["opencode.promise"] = Promise
package.loaded["opencode.promise.ui"] = {
	input = function()
		error("opencode.promise.ui.input must be replaced with the NUI adapter")
	end,
}
local native_plugin_input = package.loaded["opencode.promise.ui"].input
package.loaded["opencode.server.discovery"] = {
	get = function()
		discovery_calls = discovery_calls + 1
		return Promise.resolve(server)
	end,
}

local original_action_config = package.loaded["opencode.config"]
local action_config = {
	opts = {
		select = {
			commands = {
				["session.select"] = "Select session",
				["session.new"] = "New session",
			},
		},
	},
}
package.loaded["opencode.config"] = action_config
plugin_specs[1].config()
eq(status_setup_calls, 1, "opencode config delegates status ownership to the exact-session bridge")
eq(action_config.opts.select.commands["session.select"], nil, "plugin config removes the upstream broadcast session selector")
eq(action_config.opts.select.commands["session.new"], "New session", "plugin config preserves unrelated safe action commands")

eq(
	vim.fn.maparg("<leader>ff", "c"),
	"",
	"config does not install the obsolete global command-line picker workaround"
)

local promise_ui = package.loaded["opencode.promise.ui"]
local adapted_input = promise_ui.input
assert(type(adapted_input) == "function", "config replaces opencode.promise.ui.input with a NUI adapter")
assert(adapted_input ~= native_plugin_input, "the plugin Promise input function is replaced")
plugin_specs[1].config()
eq(promise_ui.input, adapted_input, "config is idempotent and does not wrap the Promise input adapter twice")
eq(status_setup_calls, 2, "repeated config delegates to the bridge's idempotent setup instead of adding raw autocmds")
package.loaded["opencode.config"] = original_action_config

assert(
	vim.fn.exists(":OpenCodeFocus") == 2,
	"repeated config() calls leave the OpenCodeFocus command registered without erroring"
)
assert(
	vim.fn.exists(":OpenCodeWorktreeLayout") == 2,
	"repeated config() calls leave the OpenCodeWorktreeLayout command registered without erroring"
)

print("PASS opencode config installs one plugin-local NUI input adapter and no global cmdline workaround")

-- ===== Section 3: worktree startup opens the local OpenCode split =====

vim.env.NVIM_OPEN_OPENCODE = "1"
local startup_plugin_specs = dofile("lua/plugins/opencode.lua")
eq(startup_plugin_specs[1].lazy, false, "worktree startup eagerly loads opencode.nvim before VimEnter")

local startup_terminal_actions = {}
local startup_defer_delays = {}
local original_terminal_open = terminal_adapter.open
local original_terminal_toggle = terminal_adapter.toggle
local original_startup_defer_fn = vim.defer_fn
terminal_adapter.open = function()
	table.insert(startup_terminal_actions, "open")
end
terminal_adapter.toggle = function()
	table.insert(startup_terminal_actions, "toggle")
end
vim.defer_fn = function(callback, delay)
	table.insert(startup_defer_delays, delay)
	callback()
end

startup_plugin_specs[1].config()
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })

terminal_adapter.open = original_terminal_open
terminal_adapter.toggle = original_terminal_toggle
vim.defer_fn = original_startup_defer_fn
vim.env.NVIM_OPEN_OPENCODE = nil

eq(startup_defer_delays, { 0 }, "worktree startup defers the terminal open by one event-loop turn")
eq(startup_terminal_actions, { "open" }, "worktree startup opens the split exactly once without toggling it")

print("PASS worktree startup eagerly loads opencode.nvim and opens its split exactly once")

-- ===== Section 3b: NVIM_OPEN_TOGGLETERM=1 builds the coordinated layout =====
--
-- ToggleTerm's real Terminal:open() unconditionally resets its remembered
-- origin window, so opening the ordinary project shell while OCV is still
-- current would split off of OCV instead of the editor. The startup callback
-- must therefore: open OCV, explicitly restore focus to the editor window,
-- open the shell (so it splits relative to the editor), then re-focus OCV.

vim.env.NVIM_OPEN_OPENCODE = "1"
vim.env.NVIM_OPEN_TOGGLETERM = "1"
local layout_plugin_specs = dofile("lua/plugins/opencode.lua")

local layout_actions = {}
local original_layout_terminal_open = terminal_adapter.open
local original_layout_defer_fn = vim.defer_fn
local original_layout_set_current_win = vim.api.nvim_set_current_win
local layout_defer_delays = {}

terminal_adapter.open = function(dir)
	table.insert(layout_actions, { action = "ocv_open", dir = dir })
end
package.loaded["config.project_terminal"] = {
	open = function(dir)
		table.insert(layout_actions, { action = "shell_open", dir = dir })
	end,
}
vim.api.nvim_set_current_win = function(win)
	table.insert(layout_actions, { action = "focus_editor" })
	return original_layout_set_current_win(win)
end
vim.defer_fn = function(callback, delay)
	table.insert(layout_defer_delays, delay)
	callback()
end

layout_plugin_specs[1].config()
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })

terminal_adapter.open = original_layout_terminal_open
vim.defer_fn = original_layout_defer_fn
vim.api.nvim_set_current_win = original_layout_set_current_win
package.loaded["config.project_terminal"] = nil
vim.env.NVIM_OPEN_OPENCODE = nil
vim.env.NVIM_OPEN_TOGGLETERM = nil

eq(layout_defer_delays, { 0 }, "the coordinated layout also defers by exactly one event-loop turn")
eq(#layout_actions, 4, "the coordinated layout performs exactly four ordered actions")
eq(layout_actions[1].action, "ocv_open", "OCV is opened first")
eq(layout_actions[2].action, "focus_editor", "focus is explicitly restored to the editor window before opening the shell")
eq(layout_actions[3].action, "shell_open", "the ordinary project shell is opened only after the editor is refocused")
eq(layout_actions[4].action, "ocv_open", "OCV is re-focused last (open() is idempotent, so this focuses rather than reopens)")
assert(type(layout_actions[1].dir) == "string" and layout_actions[1].dir ~= "", "OCV opens against a resolved project directory")
eq(layout_actions[3].dir, layout_actions[1].dir, "the shell opens against the same resolved project directory as OCV")
eq(layout_actions[4].dir, layout_actions[1].dir, "the final OCV re-focus targets the same resolved project directory")

print("PASS NVIM_OPEN_TOGGLETERM=1 builds the coordinated editor+shell+OCV layout on worktree startup")

-- ===== Section 3c: OpenCodeFocus and OpenCodeWorktreeLayout commands =====

local command_actions = {}
local original_command_terminal_open = terminal_adapter.open
terminal_adapter.open = function(dir)
	table.insert(command_actions, { action = "ocv_open", dir = dir })
end
package.loaded["config.project_terminal"] = {
	open = function(dir)
		table.insert(command_actions, { action = "shell_open", dir = dir })
	end,
}

vim.cmd("OpenCodeFocus")
eq(command_actions, { { action = "ocv_open", dir = command_actions[1].dir } }, "OpenCodeFocus only focuses/opens OCV")

command_actions = {}
vim.cmd("OpenCodeWorktreeLayout")
eq(#command_actions, 3, "OpenCodeWorktreeLayout builds the full editor+shell+OCV layout")
eq(command_actions[1].action, "ocv_open", "OpenCodeWorktreeLayout opens OCV first")
eq(command_actions[2].action, "shell_open", "OpenCodeWorktreeLayout opens the shell second")
eq(command_actions[3].action, "ocv_open", "OpenCodeWorktreeLayout re-focuses OCV last")

terminal_adapter.open = original_command_terminal_open
package.loaded["config.project_terminal"] = nil

print("PASS OpenCodeFocus and OpenCodeWorktreeLayout commands dispatch to the expected terminal actions")

-- ===== Section 4: shared picker catalog inside the OCV terminal composer =====

local prompt_bindings = {}
package.loaded["config.fzf_prompt"] = {
	bind = function(buf, owner)
		table.insert(prompt_bindings, { buf = buf, owner = owner })
	end,
}

assert(type(opencode_terminal_opts.on_create) == "function", "the OpenCode terminal configures a one-time on_create hook")

local terminal_buf = vim.api.nvim_create_buf(false, true)
opencode_terminal_opts.on_create({ bufnr = terminal_buf })

eq(#prompt_bindings, 1, "the OCV composer binds the shared prompt picker catalog")
eq(prompt_bindings[1].buf, terminal_buf, "the OCV picker catalog is local to its terminal buffer")
eq(
	prompt_bindings[1].owner.mode,
	"t",
	"the OCV picker catalog uses direct terminal mappings instead of an outer Normal-mode transition"
)
eq(
	prompt_bindings[1].owner.prefix,
	"<C-Space>",
	"the OCV picker catalog requires an explicit Ctrl-Space prefix so ordinary prompt text cannot trigger pickers"
)

local appended
package.loaded["config.opencode_prompt"] = {
	append = function(text, opts)
		appended = { text = text, opts = opts }
	end,
}

prompt_bindings[1].owner.insert("main abc123 lua/plugins/opencode.lua ")
assert(appended, "the shared picker sink appends selections through the local composer facade")
eq(appended.text, "main abc123 lua/plugins/opencode.lua ", "the picker selection text is forwarded unchanged")
eq(appended.opts.title, "opencode", "the picker append keeps its title")
eq(appended.opts.notify_success, false, "the picker append suppresses its success notification")
eq(appended.opts.fallback_clipboard, true, "the picker append keeps its clipboard fallback")
assert(type(appended.opts.dir) == "string" and appended.opts.dir ~= "", "the picker append pins its owning project directory")

-- A real opencode_pickers Enter action (not a direct owner.insert call)
-- must reach the same terminal-bound owner, proving the full picker ->
-- facade chain, not just the facade wiring in isolation.
local fzf_calls = {}
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, fzf_opts)
		table.insert(fzf_calls, { entries = entries, opts = fzf_opts })
	end,
}
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value)
		return value
	end,
}
package.loaded["config.opencode_messages"] = {
	latest_session = function(callback)
		callback({ id = "session-1", title = "Picker Enter session", agent = "build", time = { created = 1, updated = 2 } })
	end,
	sessions = function(callback)
		callback({})
	end,
	messages = function(_, callback)
		callback({
			{
				info = { id = "message-1", role = "user", time = { created = 3 } },
				parts = { { id = "part-1", type = "text", text = "picker enter payload" } },
			},
		})
	end,
	notify_error = function(err)
		error(err or "unexpected OpenCode API error")
	end,
}

appended = nil
require("config.opencode_pickers").all({ prompt = { owner = prompt_bindings[1].owner } })
eq(#fzf_calls, 1, "a real opencode_pickers.all() call opens exactly one message picker")
local picker_enter = fzf_calls[1].opts.actions.enter
assert(type(picker_enter) == "function", "the real message picker exposes an Enter action")
picker_enter({ fzf_calls[1].entries[1] })
assert(appended, "the real picker Enter reaches the terminal-bound owner and the composer facade")
assert(appended.text:match("picker enter payload"), "the real picker Enter forwards its selected message payload")

vim.api.nvim_buf_delete(terminal_buf, { force = true })

print("PASS the OCV terminal binds the shared picker catalog and appends its selections through the local composer facade")

-- ===== Section 4: shared modal NUI prompt =====

local ask_mapping
for _, key in ipairs(plugin_specs[1].keys) do
	if key[1] == "<leader>aoa" and key.mode == "n" then
		ask_mapping = key[2]
		break
	end
end
assert(ask_mapping, "normal <leader>aoa mapping is present")

local original_input = vim.ui.input
vim.ui.input = function()
	error("<leader>aoa must use the modal NUI prompt instead of vim.ui.input")
end

local modal_buf = vim.api.nvim_create_buf(false, true)
local modal_maps = {}
local modal
local modals = {}
package.loaded["nui.input"] = function(popup_opts, input_opts)
	modal = {
		bufnr = modal_buf,
		winid = vim.api.nvim_get_current_win(),
		popup_opts = popup_opts,
		input_opts = input_opts,
		mounted = false,
		unmounted = false,
	}
	function modal:map(mode, lhs, callback, opts)
		table.insert(modal_maps, { mode = mode, lhs = lhs, callback = callback, opts = opts })
	end
	function modal:mount()
		self.mounted = true
		vim.api.nvim_set_current_buf(self.bufnr)
		vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { "> explain this" })
	end
	function modal:unmount()
		self.unmounted = true
	end
	table.insert(modals, modal)
	return modal
end

local function modal_map(mode, lhs)
	for _, item in ipairs(modal_maps) do
		if item.mode == mode and item.lhs == lhs then
			return item
		end
	end
end

local source_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(source_buf)
ask_mapping()

assert(modal and modal.mounted, "<leader>aoa mounts a NUI input prompt")
eq(modal.popup_opts.relative, "editor", "the modal prompt is positioned relative to the editor")
eq(modal.popup_opts.position.row, "90%", "the modal prompt is positioned near the bottom of the editor")
eq(modal.popup_opts.position.col, "50%", "the modal prompt remains horizontally centered")
eq(modal.popup_opts.border.style, "rounded", "the modal prompt uses the existing rounded-float visual language")
assert(modal_map("n", "<Esc>"), "the modal prompt can be closed from Normal mode with <Esc>")
assert(modal_map("n", "q"), "the modal prompt can be closed from Normal mode with q")
local insert_leader_bridge = modal_map("i", "<C-Space>")
assert(insert_leader_bridge, "<C-Space> starts a leader sequence from Insert mode in the modal prompt")
eq(insert_leader_bridge.callback, [[<Esc><Space>]], "Insert mode exits to Normal then replays Space")
eq(insert_leader_bridge.opts.remap, true, "the replayed Space is recursively resolved as the Normal-mode leader trigger")
eq(#prompt_bindings, 2, "the NUI prompt binds the shared prompt picker catalog")
eq(prompt_bindings[2].buf, modal_buf, "the NUI picker catalog is local to its prompt buffer")
eq(prompt_bindings[2].owner.mode, "n", "the NUI picker catalog is available only from Normal mode")

local modal_scheduled = {}
local original_schedule = vim.schedule
vim.schedule = function(fn)
	table.insert(modal_scheduled, fn)
end
prompt_bindings[2].owner.insert("main abc123 lua/plugins/opencode.lua ")
vim.schedule = original_schedule
eq(#modal_scheduled, 1, "the picker selection is deferred until fzf-lua restores the modal prompt window")
modal_scheduled[1]()
eq(
	vim.api.nvim_buf_get_lines(modal_buf, 0, 1, false)[1],
	"> explain this main abc123 lua/plugins/opencode.lua ",
	"arbitrary picker output is appended to the modal prompt"
)

modal_map("n", "<Esc>").callback()
assert(modal.unmounted, "Normal-mode <Esc> unmounts the modal prompt")

vim.ui.input = original_input
vim.api.nvim_set_current_buf(source_buf)
vim.api.nvim_buf_delete(source_buf, { force = true })

print("PASS <leader>aoa opens a modal NUI prompt with the shared Normal-mode picker catalog")

-- ===== Section 5: plugin-owned asks use the shared NUI prompt =====

local lsp_starts = {}
local original_lsp_start = vim.lsp.start
vim.lsp.start = function(config, opts)
	table.insert(lsp_starts, { config = config, opts = opts })
	return 1
end
package.loaded["opencode.ui.ask.cmp"] = { name = "opencode_ask_cmp" }

local resolved_input
local rejected_input = false
local adapted_promise = promise_ui.input({ default = "@buffer: " })
adapted_promise:next(function(value)
	resolved_input = value
end):catch(function()
	rejected_input = true
end)

modal = modals[#modals]
eq(modal.input_opts.default_value, "@buffer: ", "the adapter forwards opencode.nvim's default prompt text")
eq(vim.bo[modal.bufnr].filetype, "opencode_ask", "the adapter marks the prompt for OpenCode completion")
eq(#lsp_starts, 1, "the adapter starts OpenCode completion exactly once for the prompt")
eq(lsp_starts[1].opts.bufnr, modal.bufnr, "completion is attached to the NUI prompt buffer")
modal.input_opts.on_submit("@buffer: explain this")
eq(resolved_input, "@buffer: explain this", "submitting the NUI prompt resolves the plugin Promise")
assert(not rejected_input, "submitting the NUI prompt does not reject the plugin Promise")

local cancelled = false
promise_ui.input({ default = "@visible: " }):catch(function()
	cancelled = true
end)
modal = modals[#modals]
modal.input_opts.on_close()
assert(cancelled, "closing the NUI prompt rejects the plugin Promise")

local contexts = {}
local prompted = {}
package.loaded["opencode.context"] = {
	new = function(context_server)
		local context = {
			server = context_server,
			clear_count = 0,
			resume_count = 0,
		}
		function context:clear()
			self.clear_count = self.clear_count + 1
		end
		function context:resume()
			self.resume_count = self.resume_count + 1
		end
		table.insert(contexts, context)
		return context
	end,
}
package.loaded["opencode.ui.ask"] = {
	ask = function(default, context)
		assert(context.server == server, "ask receives the context constructed for the discovered server")
		return promise_ui.input({ default = default })
	end,
}
package.loaded["opencode.api.prompt"] = {
	prompt = function(text, context)
		table.insert(prompted, { text = text, context = context })
		return Promise.resolve()
	end,
}

local function key_callback(lhs, mode)
	for _, key in ipairs(plugin_specs[1].keys) do
		if key[1] == lhs and mode_includes(key.mode, mode) then
			return key[2]
		end
	end
end

local original_defer_fn = vim.defer_fn
vim.defer_fn = function(callback)
	callback()
end

for _, expected in ipairs({
	{ lhs = "<leader>aoB", prefix = "@buffer: " },
	{ lhs = "<leader>aoV", prefix = "@visible: " },
	{ lhs = "<leader>aoQ", prefix = "@quickfix: " },
}) do
	local callback = key_callback(expected.lhs, "n")
	assert(callback, expected.lhs .. " mapping is present")
	callback()
	modal = modals[#modals]
	eq(modal.input_opts.default_value, expected.prefix, expected.lhs .. " pre-fills its context placeholder")
	modal.input_opts.on_submit(expected.prefix .. "question")
	eq(prompted[#prompted].text, expected.prefix .. "question ", expected.lhs .. " appends without submitting")
	eq(prompted[#prompted].context.server, server, expected.lhs .. " uses the discovered server context")
end

vim.defer_fn = original_defer_fn
eq(discovery_calls, 3, "each context ask resolves the server through opencode.server.discovery")
vim.lsp.start = original_lsp_start

print("PASS plugin-owned context asks use discovery, current APIs, and the shared NUI prompt")

-- ===== Section 6: local prompt routing uses append_and_submit without terminal focus =====

local original_config = package.loaded["opencode.config"]
local original_prompt = package.loaded["config.opencode_prompt"]
local terminal_module = require("config.opencode_terminal")
local original_focus = terminal_module.focus
local local_prompt_calls = {}
local local_append_calls = {}
local visibility_calls = {}

package.loaded["opencode.config"] = {
	opts = {
		prompts = {
			explain = { prompt = "Explain: ", ask = true },
			fix = "Fix diagnostics",
			review = { prompt = "Review this" },
			test = "Add tests",
			document = "Document this",
			optimize = "Optimize this",
			implement = "Implement this",
		},
		select = {
			prompts = {
				diagnostics = "Explain diagnostics",
			},
		},
	},
}
package.loaded["config.opencode_prompt"] = {
	append_and_submit = function(text, opts)
		table.insert(local_prompt_calls, { text = text, opts = opts })
	end,
	append = function(text, opts)
		table.insert(local_append_calls, { text = text, opts = opts })
	end,
	submit = function() end,
	set_sink = function() end,
}
terminal_module.focus = function(dir)
	table.insert(visibility_calls, { action = "focus", dir = dir })
	return true
end

local original_getcwd = vim.fn.getcwd
vim.fn.getcwd = function()
	return "/Users/shaheislam/neovim"
end

local function last_local_prompt(label, expected_text)
	local call = local_prompt_calls[#local_prompt_calls]
	assert(call, label .. " routes through config.opencode_prompt.append_and_submit")
	eq(call.text, expected_text, label .. " forwards the expected prompt text")
	eq(call.opts, {
		title = "opencode",
		success = "Sent to OpenCode",
		fallback_clipboard = false,
		dir = nil,
	}, label .. " preserves exact local facade options")
	eq(#visibility_calls, 0, label .. " does not reveal or focus the local OpenCode terminal")
end

local function reset_local_prompt_calls()
	local_prompt_calls = {}
	local_append_calls = {}
	visibility_calls = {}
end

local ask_calls_before = #modals
local ask_normal = key_callback("<leader>aoa", "n")
local ask_visual = key_callback("<leader>aoa", "x")
assert(ask_normal, "normal <leader>aoa mapping is present")
assert(ask_visual, "visual <leader>aoa mapping is present")
assert(key_callback("<leader>aoM", "n") == nil, "obsolete <leader>aoM mapping is removed")

local ask_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(ask_buffer)
vim.api.nvim_buf_set_name(ask_buffer, "diffview://deadbeef:lua/example.lua")
vim.api.nvim_buf_set_lines(ask_buffer, 0, -1, false, { "local answer = 42", "return answer" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })

reset_local_prompt_calls()
ask_normal()
modal = modals[#modals]
assert(#modals == ask_calls_before + 1, "normal <leader>aoa reuses the shared modal NUI prompt")
modal.input_opts.on_submit("what does this do")
last_local_prompt("normal <leader>aoa", "[file: lua/example.lua, line 2]\nreturn answer\nwhat does this do")

vim.api.nvim_set_current_buf(ask_buffer)
vim.fn.setpos("'<", { 0, 1, 1, 0 })
vim.fn.setpos("'>", { 0, 2, 13, 0 })

reset_local_prompt_calls()
ask_visual()
modal = modals[#modals]
modal.input_opts.on_submit("why")
last_local_prompt("visual <leader>aoa", "[file: lua/example.lua, lines 1-2]\nlocal answer = 42\nreturn answer\nwhy")

local ask_submit_normal = key_callback("<leader>aos", "n")
local ask_submit_visual = key_callback("<leader>aos", "x")
assert(ask_submit_normal, "normal <leader>aos mapping is present")
assert(ask_submit_visual, "visual <leader>aos mapping is present")

reset_local_prompt_calls()
vim.api.nvim_set_current_buf(ask_buffer)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
ask_submit_normal()
modal = modals[#modals]
modal.input_opts.on_submit("explain")
last_local_prompt("normal <leader>aos", "[file: lua/example.lua, line 2]\nreturn answer\nexplain")

reset_local_prompt_calls()
vim.api.nvim_set_current_buf(ask_buffer)
ask_submit_visual()
modal = modals[#modals]
modal.input_opts.on_submit("explain")
last_local_prompt(
	"visual <leader>aos",
	"[file: lua/example.lua, lines 1-2]\nlocal answer = 42\nreturn answer\nexplain"
)

vim.api.nvim_set_current_buf(ask_buffer)
vim.fn.setpos("'>", { 0, 1, 17, 0 })

local named_expectations = {
	{ lhs = "<leader>aof", mode = "n", text = "[file: lua/example.lua]\nFix diagnostics" },
	{ lhs = "<leader>aor", mode = "n", text = "[file: lua/example.lua]\nReview this" },
	{ lhs = "<leader>aot", mode = "n", text = "[file: lua/example.lua]\nAdd tests" },
	{ lhs = "<leader>aod", mode = "n", text = "[file: lua/example.lua]\nDocument this" },
	{ lhs = "<leader>aoo", mode = "n", text = "[file: lua/example.lua]\nOptimize this" },
	{ lhs = "<leader>aoi", mode = "n", text = "[file: lua/example.lua]\nImplement this" },
	{ lhs = "<leader>aoE", mode = "n", text = "[file: lua/example.lua]\nExplain diagnostics" },
	{ lhs = "<leader>aof", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nFix diagnostics" },
	{ lhs = "<leader>aor", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nReview this" },
	{ lhs = "<leader>aot", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nAdd tests" },
	{ lhs = "<leader>aod", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nDocument this" },
	{ lhs = "<leader>aoo", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nOptimize this" },
	{ lhs = "<leader>aoi", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nImplement this" },
	{ lhs = "<leader>aoE", mode = "x", text = "[file: lua/example.lua]\n```\nlocal answer = 42\n```\nExplain diagnostics" },
}

for _, expected in ipairs(named_expectations) do
	vim.api.nvim_set_current_buf(ask_buffer)
	reset_local_prompt_calls()
	local callback = key_callback(expected.lhs, expected.mode)
	assert(callback, expected.lhs .. " " .. expected.mode .. " mapping is present")
	callback()
	last_local_prompt(expected.lhs .. " " .. expected.mode, expected.text)
end

vim.api.nvim_set_current_buf(ask_buffer)
reset_local_prompt_calls()
local explain = key_callback("<leader>aoe", "n")
assert(explain, "normal <leader>aoe mapping is present")
explain()
modal = modals[#modals]
eq(modal.input_opts.default_value, "", "custom ask=true prompts open an empty shared NUI input")
modal.input_opts.on_submit("focus on errors")
last_local_prompt("custom ask=true named prompt", "[file: lua/example.lua]\nExplain: focus on errors")

vim.api.nvim_set_current_buf(ask_buffer)
reset_local_prompt_calls()
local explain_visual = key_callback("<leader>aoe", "x")
assert(explain_visual, "visual <leader>aoe mapping is present")
explain_visual()
modal = modals[#modals]
modal.input_opts.on_submit("focus on selection")
last_local_prompt(
	"visual custom ask=true named prompt",
	"[file: lua/example.lua]\n```\nlocal answer = 42\n```\nExplain: focus on selection"
)

local terminal_like_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(
	terminal_like_buf,
	"term://project//123:OPENCODE_SERVER_PASSWORD=prompt-context-secret ocv attach"
)
vim.api.nvim_buf_set_lines(terminal_like_buf, 0, -1, false, { "terminal output one", "terminal output two" })
vim.api.nvim_set_current_buf(terminal_like_buf)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.fn.setpos("'<", { 0, 1, 1, 0 })
vim.fn.setpos("'>", { 0, 2, 19, 0 })

reset_local_prompt_calls()
ask_normal()
modal = modals[#modals]
modal.input_opts.on_submit("question")
last_local_prompt("terminal normal ask", "question")

reset_local_prompt_calls()
vim.api.nvim_set_current_buf(terminal_like_buf)
ask_visual()
modal = modals[#modals]
modal.input_opts.on_submit("question")
last_local_prompt("terminal visual ask", "terminal output one\nterminal output two\nquestion")

reset_local_prompt_calls()
vim.api.nvim_set_current_buf(terminal_like_buf)
key_callback("<leader>aof", "n")()
last_local_prompt("terminal named prompt", "Fix diagnostics")

reset_local_prompt_calls()
vim.api.nvim_set_current_buf(terminal_like_buf)
key_callback("<leader>aof", "x")()
last_local_prompt("terminal visual named prompt", "```\nterminal output one\nterminal output two\n```\nFix diagnostics")

reset_local_prompt_calls()
vim.api.nvim_set_current_buf(terminal_like_buf)
key_callback("<leader>aoS", "x")()
eq(#local_append_calls, 1, "terminal selection routes through the local append facade")
eq(local_append_calls[1].text, "terminal output one\nterminal output two", "terminal selections omit pseudo-file context")
eq(local_append_calls[1].opts, {
	title = "opencode",
	success = "Sent selection to OpenCode",
	fallback_clipboard = true,
}, "terminal selection preserves local append options")
assert(
	not local_append_calls[1].text:find("prompt-context-secret", 1, true),
	"terminal credentials never reach selection prompt text"
)

local uri_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(uri_buf, "https://example.test/prompt-context-secret")
vim.api.nvim_buf_set_lines(uri_buf, 0, -1, false, { "remote content" })
vim.api.nvim_set_current_buf(uri_buf)

reset_local_prompt_calls()
key_callback("<leader>aor", "n")()
last_local_prompt("URI named prompt", "Review this")

local nonfile_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(nonfile_buf, "/virtual/prompt-context-secret")
vim.api.nvim_buf_set_lines(nonfile_buf, 0, -1, false, { "generated content" })
vim.api.nvim_set_current_buf(nonfile_buf)

reset_local_prompt_calls()
key_callback("<leader>aot", "n")()
last_local_prompt("non-file named prompt", "Add tests")

package.loaded["opencode.config"] = original_config
package.loaded["config.opencode_prompt"] = original_prompt
package.loaded["config.opencode_status"] = original_status_bridge
terminal_module.focus = original_focus
vim.fn.getcwd = original_getcwd
vim.api.nvim_buf_delete(ask_buffer, { force = true })
vim.api.nvim_buf_delete(terminal_like_buf, { force = true })
vim.api.nvim_buf_delete(uri_buf, { force = true })
vim.api.nvim_buf_delete(nonfile_buf, { force = true })
vim.api.nvim_buf_delete(modal_buf, { force = true })

vim.env.OPENCODE_SERVER_USERNAME = original_auth_env.username
vim.env.OPENCODE_SERVER_PASSWORD = original_auth_env.password
vim.env.XDG_STATE_HOME = original_auth_env.state_home
vim.env.NVIM_OPEN_OPENCODE = original_auth_env.open_opencode

print("PASS local OpenCode prompt mappings route through the shared prompt facade and no longer expose aoM")

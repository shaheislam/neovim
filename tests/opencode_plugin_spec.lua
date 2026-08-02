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

-- ===== Section 1: toggleterm resize-on-reopen fix =====

local recorded_terminal_calls = {}
local opencode_terminal_opts

package.loaded["toggleterm.terminal"] = {
	Terminal = {
		new = function(_, term)
			opencode_terminal_opts = term
			term.__is_open = false
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
			return term
		end,
	},
}

local plugin_specs = dofile("lua/plugins/opencode.lua")

local toggle_terminal
for _, key in ipairs(plugin_specs[1].keys) do
	if key[1] == "<leader>aoc" and mode_includes(key.mode, "n") then
		toggle_terminal = key[2]
		break
	end
end
assert(toggle_terminal, "<leader>aoc toggle mapping is present")

vim.o.columns = 200
toggle_terminal() -- starts closed -> opens
eq(#recorded_terminal_calls, 1, "first <leader>aoc press performs exactly one terminal action")
eq(recorded_terminal_calls[1], { action = "open_via_toggle", size = 100 }, "first open resolves a fresh explicit size (50%% of columns), not toggleterm's global/persisted default")

toggle_terminal() -- closes
eq(recorded_terminal_calls[2], { action = "close" }, "second press closes")

vim.o.columns = 140 -- simulate the user resizing Neovim while opencode was closed
toggle_terminal() -- reopens
eq(
	recorded_terminal_calls[3],
	{ action = "open_via_toggle", size = 70 },
	"reopening after a close recomputes size fresh from the current column count instead of reusing a stale/persisted width"
)

plugin_specs[1].init()
assert(type(vim.g.opencode_opts.server.start) == "function", "server.start is wired to start_opencode_terminal")
assert(type(vim.g.opencode_opts.server.url) == "function", "server.url resolves the launchd-managed OpenCode endpoint")
eq(vim.g.opencode_opts.server.port, nil, "the obsolete server.port option is not configured")
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
vim.o.columns = 90
vim.g.opencode_opts.server.start()
eq(
	recorded_terminal_calls[4],
	{ action = "open", size = 45 },
	"server.start (used by opencode.nvim's own startup path) resolves a fresh explicit size the same way as the toggle mapping"
)

print("PASS opencode terminal resize-on-reopen always resolves a fresh explicit size")

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

plugin_specs[1].config()

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

print("PASS opencode config installs one plugin-local NUI input adapter and no global cmdline workaround")

-- ===== Section 3: shared picker catalog inside the OCV terminal composer =====

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
	"n",
	"the OCV picker catalog uses terminal-normal-mode mappings so composer typing is never intercepted"
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
eq(appended.opts.success, "Sent picker selection to OpenCode", "the picker append keeps its success message")
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

-- ===== Section 6: custom ask=true named prompts use NUI =====

local original_config = package.loaded["opencode.config"]
local original_http = package.loaded["config.opencode_http"]
local custom_prompt_calls = {}
package.loaded["opencode.config"] = {
	opts = {
		prompts = {
			explain = { prompt = "Explain: ", ask = true },
		},
	},
}
package.loaded["config.opencode_http"] = {
	send_with_model = function(text, provider, model, opts)
		table.insert(custom_prompt_calls, { text = text, provider = provider, model = model, opts = opts })
	end,
}

local explain = key_callback("<leader>aoe", "n")
assert(explain, "normal <leader>aoe mapping is present")
explain()
modal = modals[#modals]
eq(modal.input_opts.default_value, "", "custom ask=true prompts open an empty shared NUI input")
modal.input_opts.on_submit("focus on errors")
eq(custom_prompt_calls[1].text, "Explain: focus on errors", "custom ask input is combined with its prompt template")

package.loaded["opencode.config"] = original_config
package.loaded["config.opencode_http"] = original_http
vim.api.nvim_buf_delete(modal_buf, { force = true })

print("PASS custom ask=true named prompts use the shared NUI prompt")

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

-- ===== Section 3: <leader>ff fzf-lua picker inside the OCV terminal composer =====

local recorded_files_opts
package.loaded["fzf-lua"] = {
	files = function(opts)
		recorded_files_opts = opts
	end,
}
package.loaded["fzf-lua.path"] = {
	entry_to_file = function(entry, _)
		return { path = vim.fn.getcwd() .. "/" .. entry }
	end,
}
assert(type(opencode_terminal_opts.on_create) == "function", "the OpenCode terminal configures a one-time on_create hook")

local terminal_buf = vim.api.nvim_create_buf(false, true)
opencode_terminal_opts.on_create({ bufnr = terminal_buf })

local terminal_mapping
vim.api.nvim_buf_call(terminal_buf, function()
	terminal_mapping = vim.fn.maparg("<leader>ff", "t", false, true)
end)
assert(type(terminal_mapping.callback) == "function", "<leader>ff is registered in terminal mode with a Lua callback")
eq(terminal_mapping.buffer, 1, "the OCV picker mapping is local to the OpenCode terminal buffer")
eq(terminal_mapping.desc, "Pick file into opencode prompt", "the OCV picker mapping has a discoverable description")

recorded_files_opts = nil
terminal_mapping.callback()
assert(type(recorded_files_opts) == "table", "the OCV terminal mapping opens the fzf-lua files picker")

local appended
package.loaded["config.opencode_http"] = {
	append_prompt = function(text, opts)
		appended = { text = text, opts = opts }
	end,
}

recorded_files_opts.actions.default({ "lua/plugins/opencode.lua" }, {})
eq(appended, {
	text = "lua/plugins/opencode.lua ",
	opts = {
		title = "opencode",
		success = "Sent path to OpenCode",
		fallback_clipboard = true,
	},
}, "selecting a file appends its clean path to the live OCV composer through the HTTP bridge")

vim.api.nvim_buf_delete(terminal_buf, { force = true })

print("PASS <leader>ff in the OCV terminal opens fzf-lua and appends the picked path to its live composer")

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
assert(modal_map("n", "<leader>ff"), "the modal prompt exposes the file picker only in Normal mode")
assert(modal_map("n", "<Esc>"), "the modal prompt can be closed from Normal mode with <Esc>")
assert(modal_map("n", "q"), "the modal prompt can be closed from Normal mode with q")

recorded_files_opts = nil
modal_map("n", "<leader>ff").callback()
assert(type(recorded_files_opts) == "table", "Normal-mode <leader>ff opens the fzf-lua files picker")

local modal_scheduled = {}
local original_schedule = vim.schedule
vim.schedule = function(fn)
	table.insert(modal_scheduled, fn)
end
recorded_files_opts.actions.default({ "lua/plugins/opencode.lua" }, {})
vim.schedule = original_schedule
eq(#modal_scheduled, 1, "the picked path is deferred until fzf-lua restores the modal prompt window")
modal_scheduled[1]()
eq(
	vim.api.nvim_buf_get_lines(modal_buf, 0, 1, false)[1],
	"> explain this lua/plugins/opencode.lua ",
	"the picked project-relative path is appended to the modal prompt"
)

modal_map("n", "<Esc>").callback()
assert(modal.unmounted, "Normal-mode <Esc> unmounts the modal prompt")

vim.ui.input = original_input
vim.api.nvim_set_current_buf(source_buf)
vim.api.nvim_buf_delete(source_buf, { force = true })

print("PASS <leader>aoa opens a modal NUI prompt with Normal-mode <leader>ff file insertion")

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

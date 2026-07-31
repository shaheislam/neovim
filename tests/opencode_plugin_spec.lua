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
vim.o.columns = 90
vim.g.opencode_opts.server.start()
eq(
	recorded_terminal_calls[4],
	{ action = "open", size = 45 },
	"server.start (used by opencode.nvim's own startup path) resolves a fresh explicit size the same way as the toggle mapping"
)

print("PASS opencode terminal resize-on-reopen always resolves a fresh explicit size")

-- ===== Section 2: <leader>ff fzf-lua picker inside the "Ask OpenCode: " prompt =====

package.loaded["opencode.server"] = {
	disconnect = function(_) end,
}

eq(vim.fn.getcmdtype(), "", "sanity check: not inside any cmdline context before config() runs")
eq(vim.fn.maparg("<leader>ff", "c"), "", "sanity check: no pre-existing <leader>ff cmdline mapping before config() runs")

plugin_specs[1].config()

local mapping = vim.fn.maparg("<leader>ff", "c", false, true)
assert(type(mapping.callback) == "function", "<leader>ff is registered in cmdline mode with a Lua callback")
assert(mapping.expr == 1, "<leader>ff is registered as an expr mapping so the fallback branch can pass through as text")

-- Outside the "Ask OpenCode: " prompt: must fall through as literal leader text,
-- not swallow the key or trigger the picker.
local scheduled = {}
local original_schedule = vim.schedule
vim.schedule = function(fn)
	table.insert(scheduled, fn)
end

local fallback_result = mapping.callback()
vim.schedule = original_schedule

eq(scheduled, {}, "outside the Ask OpenCode prompt, the picker must not be scheduled")
eq(
	fallback_result,
	(vim.g.mapleader or "\\") .. "ff",
	"outside the Ask OpenCode prompt, <leader>ff returns the literal key sequence as command-line text"
)

-- Inside the "Ask OpenCode: " prompt: must consume the key and defer to the picker.
local original_getcmdtype = vim.fn.getcmdtype
local original_getcmdprompt = vim.fn.getcmdprompt
vim.fn.getcmdtype = function()
	return "@"
end
vim.fn.getcmdprompt = function()
	return "Ask OpenCode: "
end

scheduled = {}
vim.schedule = function(fn)
	table.insert(scheduled, fn)
end
local guarded_result = mapping.callback()
vim.schedule = original_schedule
vim.fn.getcmdtype = original_getcmdtype
vim.fn.getcmdprompt = original_getcmdprompt

eq(guarded_result, "", "inside the Ask OpenCode prompt, <leader>ff is fully consumed (returns empty expr result)")
eq(#scheduled, 1, "inside the Ask OpenCode prompt, exactly one picker call is scheduled")

print("PASS <leader>ff falls through as literal text outside the Ask OpenCode prompt")

-- Run the scheduled picker call with fzf-lua mocked, and verify the selection action
-- feeds the clean picked path (plus a trailing space) back via noremap feedkeys.
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

scheduled[1]()

assert(type(recorded_files_opts) == "table", "the deferred call opens the fzf-lua files picker")
assert(type(recorded_files_opts.actions.default) == "function", "the picker has a custom default action")

local fed = {}
local original_feedkeys = vim.fn.feedkeys
vim.fn.feedkeys = function(keys, mode)
	table.insert(fed, { keys = keys, mode = mode })
end
recorded_files_opts.actions.default({ "lua/plugins/opencode.lua" }, {})
vim.fn.feedkeys = original_feedkeys

eq(
	fed,
	{ { keys = "lua/plugins/opencode.lua ", mode = "n" } },
	"selecting a file feeds its clean path plus a trailing space back into the still-open prompt, unescaped and unmapped"
)

print("PASS <leader>ff inside the Ask OpenCode prompt opens an fzf-lua picker wired to feed the pick back via feedkeys")

-- ===== Section 3: <leader>ff fzf-lua picker inside the OCV terminal composer =====

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

-- ===== Section 4: modal NUI prompt for <leader>aoa =====

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
vim.api.nvim_buf_delete(modal_buf, { force = true })
vim.api.nvim_buf_delete(source_buf, { force = true })

print("PASS <leader>aoa opens a modal NUI prompt with Normal-mode <leader>ff file insertion")

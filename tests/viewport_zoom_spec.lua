package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

package.loaded["viewport"] = {
	setup = function() end,
	start_resize_mode = function() end,
	start_navigate_mode = function() end,
	start_select_mode = function() end,
}
package.loaded["viewport.actions"] = {
	toggle_maximize = function() end,
}

-- Mirrors mini.misc.zoom(): opens the current buffer in a new floating
-- window on the first call, and closes that floating window on the next.
local zoom_win = nil
package.loaded["mini.misc"] = {
	zoom = function(buf_id, _)
		if zoom_win and vim.api.nvim_win_is_valid(zoom_win) then
			vim.api.nvim_win_close(zoom_win, true)
			zoom_win = nil
			return false
		end
		zoom_win = vim.api.nvim_open_win(buf_id or 0, true, {
			relative = "editor",
			row = 0,
			col = 0,
			width = 40,
			height = 10,
		})
		return true
	end,
}

local captured = {}
local original_keymap_set = vim.keymap.set
vim.keymap.set = function(mode, lhs, rhs, opts)
	if lhs == "<C-z>" then
		captured[mode] = rhs
	end
	return original_keymap_set(mode, lhs, rhs, opts)
end

local plugin_specs = dofile("lua/plugins/viewport.lua")
plugin_specs[1].config()
vim.keymap.set = original_keymap_set

local terminal_toggle = captured.t
assert(terminal_toggle, "terminal-mode <C-z> mapping is registered")

-- A real terminal buffer so 'buftype' matches production (headless Neovim
-- has no UI attached, so mode() can't actually reach Terminal-mode here --
-- spy on vim.cmd instead to observe whether startinsert is issued).
local term_win = vim.api.nvim_get_current_win()
vim.fn.jobstart(vim.o.shell, { term = true })
local term_buf = vim.api.nvim_get_current_buf()
eq(vim.bo[term_buf].buftype, "terminal", "test buffer is a real terminal buffer")

local commands = {}
local original_vim_cmd = vim.cmd
vim.cmd = function(cmd)
	table.insert(commands, cmd)
	return original_vim_cmd(cmd)
end

local original_schedule = vim.schedule
vim.schedule = function(cb)
	cb()
end

-- Zoom in: the base window is temporarily covered by a new floating window.
terminal_toggle()
local zoomed_win = vim.api.nvim_get_current_win()
assert(zoomed_win ~= term_win, "zooming in opens a new floating window")
eq(vim.api.nvim_get_current_buf(), term_buf, "zoomed window still shows the terminal buffer")
eq(commands, { "stopinsert", "startinsert" }, "zooming in re-enters insert mode")

-- Zoom out: the floating window is closed and focus returns to the base window.
commands = {}
terminal_toggle()
eq(vim.api.nvim_get_current_win(), term_win, "zooming out returns focus to the original window")
eq(vim.api.nvim_get_current_buf(), term_buf, "zooming out returns focus to the original terminal buffer")
eq(
	commands,
	{ "stopinsert", "startinsert" },
	"zooming out re-enters insert mode instead of stranding the cursor in Normal mode"
)

vim.cmd = original_vim_cmd
vim.schedule = original_schedule

print("PASS terminal-mode <C-z> re-enters insert mode after both zoom-in and zoom-out")

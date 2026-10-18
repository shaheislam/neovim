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

local captured, panes = {}, {}
local collective, collective_calls = false, 0
package.loaded["config.diffview_region"] = {
	toggle_zoom = function()
		collective_calls = collective_calls + 1
		return collective
	end,
}
local original_keymap_set = vim.keymap.set
vim.keymap.set = function(mode, lhs, rhs, opts)
	if lhs == "<C-z>" then
		captured[mode] = rhs
	elseif lhs == "<C-g>" then
		panes[mode] = rhs
	end
	return original_keymap_set(mode, lhs, rhs, opts)
end

local plugin_specs = dofile("lua/plugins/viewport.lua")
plugin_specs[1].config()
vim.keymap.set = original_keymap_set

local terminal_toggle = captured.t
assert(terminal_toggle, "terminal-mode <C-z> mapping is registered")
collective = true
captured.n()
eq(collective_calls, 1, "normal zoom checks for a collective Diffview region")
eq(zoom_win, nil, "collective zoom must not also zoom the focused buffer")
assert(panes.n and not panes.t, "Ctrl-G must be mapped only in Normal mode")
eq(vim.fn.maparg("<C-S-z>", "n"), "", "shifted zoom mapping must be removed")
panes.n()
assert(zoom_win, "Ctrl-G did not zoom an individual pane")
eq(collective_calls, 1, "pane zoom must bypass collective zoom")
panes.n()
eq(zoom_win, nil, "Ctrl-G did not restore the individual pane")
collective = false

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

eq(vim.fn.maparg("<C-g>", "t"), "", "Ctrl-G must reach terminal applications unchanged")
eq(vim.fn.maparg("<C-S-z>", "t"), "", "shifted terminal zoom mapping must be removed")
vim.cmd = original_vim_cmd
vim.schedule = original_schedule

print("PASS workspace and individual-pane zoom shortcuts, terminal insert mode, and restore")

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message or (vim.inspect(actual) .. " ~= " .. vim.inspect(expected)))
end

local commands = {}
local maps = {}
local cursor_moved
local handled = true

vim.cmd = function(command)
	table.insert(commands, type(command) == "string" and command or tostring(command))
end
vim.fn.line = function()
	return 1
end
vim.api.nvim_create_autocmd = function(event, opts)
	if event == "CursorMoved" then
		cursor_moved = opts.callback
	end
	return 1
end
vim.keymap.set = function(_, lhs, callback)
	maps[lhs] = callback
end
package.loaded["git.codecompanion_review"] = {
	follow_current = function()
		return handled
	end,
}

local spec = dofile("lua/plugins/quickfix.lua")[1]
spec.opts.on_qf(17)
assert(type(cursor_moved) == "function", "quickfix installs its movement preview")
assert(type(maps["<CR>"]) == "function", "quickfix installs its open mapping")

commands = {}
cursor_moved()
maps["<CR>"]()
eq(commands, {}, "review movement is delegated without replacing a Diffview pane")

handled = false
commands = {}
maps["<CR>"]()
eq(commands, { "wincmd k", "1cc", "normal! zz" }, "ordinary quickfix entry opening is unchanged")

print("PASS quickfix delegates only CodeCompanion review navigation")

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local original_expand = vim.fn.expand
local original_systemlist = vim.fn.systemlist
local original_input = vim.ui.input
local original_setreg = vim.fn.setreg
local original_notify = vim.notify
local original_cmd = vim.cmd
local original_win_set_cursor = vim.api.nvim_win_set_cursor
local original_buf_line_count = vim.api.nvim_buf_line_count

vim.fn.expand = function(value)
	if value == "%:p" then return "/vault/Folder/current.md" end
	if value == "~/obsidian" then return "/vault" end
	if value:match("^~/dotfiles/") then return "/scripts/" .. vim.fn.fnamemodify(value, ":t") end
	return original_expand(value)
end
vim.fn.systemlist = function()
	return {
		"Folder/first.md:12\t0.91\tFirst note\tFirst preview",
		"Folder with spaces/../Notes  with spaces/second note.md:27\t0.82\tSecond note\tSecond preview",
	}
end
vim.ui.input = function(_, callback) callback("semantic query") end

local clipboard = {}
vim.fn.setreg = function(register, value)
	if register == "+" then
		table.insert(clipboard, value)
		return
	end
	return original_setreg(register, value)
end
vim.notify = function() end

local commands = {}
local cursors = {}
vim.cmd = function(command) table.insert(commands, command) end
vim.api.nvim_win_set_cursor = function(window, position)
	table.insert(cursors, { window, position })
end
vim.api.nvim_buf_line_count = function() return 20 end

local picker_calls = {}
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, opts)
		table.insert(picker_calls, { entries = entries, opts = opts })
	end,
}
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value) return value end,
}

package.loaded["config.fzf_yank"] = dofile("lua/config/fzf_yank.lua")
local obsidian = dofile("lua/plugins/obsidian.lua")
local handlers = {}
for _, mapping in ipairs(obsidian.keys or {}) do
	handlers[mapping.desc] = mapping[2]
end

for _, description in ipairs({
	"Related notes (semantic)",
	"Semantic search (query)",
	"Related notes (same folder)",
}) do
	assert(type(handlers[description]) == "function", description .. " exposes its picker mapping")
	handlers[description]()
	local picker = picker_calls[#picker_calls]
	assert(picker and picker.opts.actions["ctrl-y"], description .. " exposes Ctrl-y")
	picker.opts.actions["default"]({ picker.entries[2] })
	eq(
		commands[#commands],
		"edit /vault/Notes\\ \\ with\\ spaces/second\\ note.md",
		description .. " opens the normalized absolute note path without collapsing spaces"
	)
	eq(cursors[#cursors], { 0, { 20, 0 } }, description .. "clamps stale indexed lines to the current note")
	picker.opts.actions["ctrl-y"]({ picker.entries[2] })
	eq(
		clipboard[#clipboard],
		"/vault/Notes  with spaces/second note.md:27",
		description .. " yanks the normalized absolute note location"
	)
end

local octo_source = table.concat(vim.fn.readfile("lua/plugins/octo.lua"), "\n")
local notification_copy = octo_source:match("%-%- Copy URL action(.-)%-%- Mark as read action") or ""
assert(notification_copy:find("copy_notification_url", 1, true), "notification Ctrl-y retains URL-copy semantics")
assert(not notification_copy:match("reload%s*=%s*true"), "notification Ctrl-y closes instead of reloading")

local item_copy = octo_source:match("%-%- Copy the selected item URL(.-)if entity == \"pr\" then") or ""
assert(item_copy:find('["ctrl-y"]', 1, true), "PR and issue picker retains Ctrl-y URL copying")
assert(not item_copy:match("reload%s*=%s*true"), "PR and issue Ctrl-y closes instead of reloading")

local checks_copy = octo_source:match('%["ctrl%-y"%]%s*=%s*function%(selected%)(.-)%s*end,') or ""
assert(checks_copy:find('setreg("+", c.link)', 1, true), "checks Ctrl-y copies the selected job URL and closes")

vim.fn.expand = original_expand
vim.fn.systemlist = original_systemlist
vim.ui.input = original_input
vim.fn.setreg = original_setreg
vim.notify = original_notify
vim.cmd = original_cmd
vim.api.nvim_win_set_cursor = original_win_set_cursor
vim.api.nvim_buf_line_count = original_buf_line_count

print("PASS custom Obsidian and Octo FZF pickers yank semantic values and close")

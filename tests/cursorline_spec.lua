package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

require("config.autocmds")
vim.opt.cursorline = true
vim.o.hidden, vim.o.swapfile = true, false

local api = vim.api
local editor = api.nvim_get_current_win()
vim.cmd("vsplit")
local other = api.nvim_get_current_win()
assert(api.nvim_win_get_buf(editor) == api.nvim_win_get_buf(other), "fixture must share a buffer")
assert(not vim.wo[editor].cursorline, "inactive window must hide its cursorline")
assert(vim.wo[other].cursorline, "newly focused split must keep its cursorline")

api.nvim_set_current_win(editor)
assert(vim.wo[editor].cursorline, "returning to a window must restore its cursorline")
assert(not vim.wo[other].cursorline, "shared buffers must have independent window highlights")

api.nvim_set_current_win(other)
vim.cmd("enew")
assert(api.nvim_win_get_buf(editor) ~= api.nvim_win_get_buf(other), "fixture must use different buffers")
api.nvim_set_current_win(editor)
assert(not vim.wo[other].cursorline, "different-buffer window must hide its cursorline")

vim.wo.cursorline = false
api.nvim_set_current_win(other)
api.nvim_set_current_win(editor)
assert(not vim.wo.cursorline, "deliberately disabled cursorline must stay disabled")
vim.wo.cursorline = true

api.nvim_set_current_win(other)
local job = vim.fn.jobstart({ "cat" }, { term = true })
assert(job > 0, "terminal fixture must start")
vim.wo.cursorline = true
api.nvim_set_current_win(editor)
assert(not vim.wo[other].cursorline, "inactive terminal must hide its cursorline")
api.nvim_set_current_win(other)
assert(vim.wo.cursorline, "terminal roundtrip must restore its cursorline preference")
api.nvim_set_current_win(editor)
assert(vim.wo.cursorline, "editor roundtrip from terminal must restore its cursorline")
vim.fn.jobstop(job)

vim.cmd("tabnew")
local tab = api.nvim_get_current_tabpage()
assert(vim.wo.cursorline, "new focused tab must inherit the enabled cursorline")
assert(not vim.wo[editor].cursorline, "windows in inactive tabs must hide their cursorline")
vim.cmd("tabprevious")
assert(vim.wo[editor].cursorline, "returning to a tab must restore the focused cursorline")
vim.cmd("tabclose " .. api.nvim_tabpage_get_number(tab))

local cursorline = require("config.cursorline")
cursorline.set(other, true)
assert(not vim.wo[other].cursorline, "background restoration must not highlight an inactive window")
cursorline.setup()
api.nvim_set_current_win(other)
assert(vim.wo.cursorline, "setup reload must preserve a pending cursorline restoration")
cursorline.set(editor, false)
api.nvim_set_current_win(editor)
assert(not vim.wo.cursorline, "background disabling must replace a pending restoration")
vim.cmd("tabnew")
assert(not vim.wo.cursorline, "new focused tab must inherit a disabled cursorline")
vim.cmd("tabclose")

print("PASS cursorline: per-window focus, disabled preferences, terminal, tabs and background restoration")

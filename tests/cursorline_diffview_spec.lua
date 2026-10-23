package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
for _, plugin in ipairs({ "plenary.nvim", "diffview.nvim" }) do
  vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.cmd("runtime plugin/diffview.lua")
require("config.cursorline").setup()
vim.opt.cursorline = true
vim.o.hidden, vim.o.swapfile = true, false
dofile("lua/plugins/git/diffview.lua").config()

local api = vim.api
local file = vim.fn.tempname()
vim.fn.writefile({ "one", "two" }, file)
vim.cmd.edit(file)
local editor = api.nvim_get_current_win()
vim.cmd("vsplit")
local disabled = api.nvim_get_current_win()
vim.wo.cursorline = false
vim.cmd("vnew")
local foreground = api.nvim_get_current_win()
vim.wo.cursorline = true

local hooks = require("diffview.config").get_config().hooks
api.nvim_set_current_win(editor)
hooks.diff_buf_read(api.nvim_get_current_buf())
assert(not vim.wo.cursorline, "diff buffer must disable cursorline while open")
hooks.diff_buf_read(api.nvim_get_current_buf())
api.nvim_set_current_win(foreground)
hooks.view_closed({ region = true })
local restored = false
vim.schedule(function()
  restored = true
end)
assert(
  vim.wait(1000, function()
    return restored
  end),
  "scheduled Diffview cleanup did not finish"
)
assert(not vim.wo[editor].cursorline, "Diffview cleanup must not highlight an inactive file window")
assert(not vim.wo[disabled].cursorline, "Diffview cleanup must preserve inactive nocursorline windows")
assert(vim.wo[foreground].cursorline, "Diffview cleanup must preserve the focused window")

api.nvim_set_current_win(editor)
assert(vim.wo.cursorline, "Diffview must restore the file window's original preference on focus")
api.nvim_set_current_win(disabled)
assert(not vim.wo.cursorline, "Diffview must preserve an explicitly disabled cursorline on focus")
vim.fn.delete(file)

print("PASS cursorline Diffview: deferred cleanup, repeated reads and per-window preference restoration")

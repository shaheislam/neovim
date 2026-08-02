local function eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
  )
end

local spec = dofile("lua/plugins/navigation.lua")

local terminal_mappings = {}
for _, mapping in ipairs(spec.keys) do
  if mapping.mode == "t" then
    table.insert(terminal_mappings, { mapping[1], mapping[2] })
  end
end

eq(terminal_mappings, {
  { "<c-h>", "<cmd>TmuxNavigateLeft<cr>" },
  { "<c-j>", "<cmd>TmuxNavigateDown<cr>" },
  { "<c-k>", "<cmd>TmuxNavigateUp<cr>" },
  { "<c-l>", "<cmd>TmuxNavigateRight<cr>" },
  { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>" },
}, "terminal navigation executes commands without leaving terminal-job mode")

pcall(vim.api.nvim_del_augroup_by_name, "nvim_mini_terminal_navigation")

local created_group = nil
local autocmds = {}
local original_create_augroup = vim.api.nvim_create_augroup
local original_create_autocmd = vim.api.nvim_create_autocmd

vim.api.nvim_create_augroup = function(name, opts)
  created_group = { name = name, opts = opts }
  return 42
end

vim.api.nvim_create_autocmd = function(event, opts)
  autocmds[event] = opts
  return 1
end

local init_ok, init_err = pcall(spec.init)
vim.api.nvim_create_augroup = original_create_augroup
vim.api.nvim_create_autocmd = original_create_autocmd
assert(init_ok, init_err)

eq(created_group, {
  name = "nvim_mini_terminal_navigation",
  opts = { clear = true },
}, "terminal navigation autocmds use a clear project-prefixed group")

local win_leave = assert(autocmds.WinLeave, "WinLeave callback is registered")
local win_enter = assert(autocmds.WinEnter, "WinEnter callback is registered")
eq(win_leave.group, 42, "WinLeave belongs to the terminal navigation group")
eq(win_enter.group, 42, "WinEnter belongs to the terminal navigation group")
assert(win_leave.desc and win_leave.desc ~= "", "WinLeave has a description")
assert(win_enter.desc and win_enter.desc ~= "", "WinEnter has a description")

vim.cmd("enew")
local normal_win = vim.api.nvim_get_current_win()
local normal_buf = vim.api.nvim_get_current_buf()
vim.cmd("vsplit")
local terminal_win = vim.api.nvim_get_current_win()
vim.fn.jobstart(vim.o.shell, { term = true })
local terminal_buf = vim.api.nvim_get_current_buf()
eq(vim.bo[terminal_buf].buftype, "terminal", "test buffer is a real terminal buffer")

local current_mode = "t"
local commands = {}
local original_mode = vim.fn.mode
local original_vim_cmd = vim.cmd
vim.fn.mode = function()
  return current_mode
end
vim.cmd = function(command)
  table.insert(commands, command)
end

win_leave.callback({ buf = terminal_buf })
vim.api.nvim_set_current_win(normal_win)
win_enter.callback({ buf = normal_buf })
eq(commands, {}, "entering another window does not resume its terminal mode")

vim.api.nvim_set_current_win(terminal_win)
commands = {}
win_enter.callback({ buf = terminal_buf })
eq(commands, { "startinsert" }, "returning to the terminal resumes terminal-job mode")
win_enter.callback({ buf = terminal_buf })
eq(commands, { "startinsert" }, "the terminal resume marker is consumed once")

commands = {}
current_mode = "n"
win_leave.callback({ buf = terminal_buf })
vim.api.nvim_set_current_win(normal_win)
win_enter.callback({ buf = normal_buf })
vim.api.nvim_set_current_win(terminal_win)
commands = {}
win_enter.callback({ buf = terminal_buf })
eq(commands, {}, "terminal-normal mode is preserved when returning to the terminal")

current_mode = "t"
win_leave.callback({ buf = terminal_buf })
vim.api.nvim_set_current_win(normal_win)
vim.api.nvim_win_set_buf(terminal_win, normal_buf)
vim.api.nvim_set_current_win(terminal_win)
win_enter.callback({ buf = normal_buf })
vim.api.nvim_win_set_buf(terminal_win, terminal_buf)
commands = {}
win_enter.callback({ buf = terminal_buf })
eq(commands, {}, "a stale marker cannot resume a different or replaced buffer")

vim.api.nvim_set_current_win(normal_win)
win_leave.callback({ buf = terminal_buf })
vim.api.nvim_set_current_win(terminal_win)
commands = {}
win_enter.callback({ buf = terminal_buf })
eq(commands, {}, "WinLeave only records the terminal in the window being left")

vim.fn.mode = original_mode
vim.cmd = original_vim_cmd

print("PASS terminal navigation mappings and focus restoration")

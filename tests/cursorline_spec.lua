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
vim.wo.cursorline = true
local job = vim.fn.jobstart({ "cat" }, { term = true })
assert(job > 0, "terminal fixture must start")
assert(not vim.wo.cursorline, "new terminal must not inherit the editor's cursorline")
api.nvim_set_current_win(editor)
assert(not vim.wo[other].cursorline, "inactive terminal must hide its cursorline")
api.nvim_set_current_win(other)
assert(not vim.wo.cursorline, "focused terminal must keep its cursorline disabled")
require("config.cursorline").set(other, true)
assert(not vim.wo.cursorline, "restoring a preference must not highlight a terminal")
vim.cmd("enew")
assert(vim.wo.cursorline, "replacing a terminal with an editor must restore its cursorline preference")
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

local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
assert(child > 0, "isolated Neovim must start")
local function lua(code, ...)
  return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
end
local function wait_for_mode(mode)
  assert(vim.wait(1500, function()
    return lua("return vim.fn.mode()") == mode
  end, 10), "terminal must enter mode " .. mode)
end
local function check_terminal(label)
  assert(not lua("return vim.wo.cursorline"), label .. " must not enable cursorline")
  assert(lua([[
    vim.cmd.redraw()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local pos = vim.fn.screenpos(0, cursor[1], 1)
    local cell = vim.api.nvim__inspect_cell(1, pos.row - 1, pos.col + 15)
    return cell[2].background ~= 0xff00ff
  ]]), label .. " must not render a full-width cursor band")
end

local ok, err = xpcall(function()
  vim.rpcrequest(child, "nvim_ui_attach", 80, 24, { rgb = true })
  lua([[
    vim.opt.rtp:prepend(...)
    vim.opt.cursorline = true
    require("config.cursorline").setup()
    vim.api.nvim_set_hl(0, "CursorLine", { bg = "#ff00ff" })
    vim.g.editor = vim.api.nvim_get_current_win()
    vim.cmd.vnew()
    vim.g.terminal = vim.api.nvim_get_current_win()
    assert(vim.fn.jobstart({ "cat" }, { term = true }) > 0)
  ]], vim.fn.getcwd())
  check_terminal("Terminal creation")
  lua("vim.cmd.startinsert()")
  wait_for_mode("t")
  check_terminal("Terminal-input mode")
  vim.rpcrequest(child, "nvim_input", "<C-\\><C-n>")
  wait_for_mode("n")
  check_terminal("Terminal Normal mode")
  lua("vim.api.nvim_set_current_win(vim.g.editor)")
  assert(lua("return vim.wo.cursorline"), "focused editor must retain its cursorline")
  assert(not lua("return vim.wo[vim.g.terminal].cursorline"), "inactive terminal must remain unhighlighted")
  lua("vim.api.nvim_set_current_win(vim.g.terminal)")
  check_terminal("Terminal refocus")
  lua("vim.cmd.startinsert()")
  wait_for_mode("t")
  check_terminal("Terminal-input re-entry")
end, debug.traceback)
vim.fn.jobstop(child)
vim.fn.jobwait({ child }, 1000)
assert(ok, err)
print("PASS cursorline: real terminal mode transitions and rendered cursor rows")

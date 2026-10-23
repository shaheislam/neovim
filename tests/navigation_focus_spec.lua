-- Exercise real key input and mode transitions in an isolated Neovim UI.
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--clean" }, { rpc = true })
local function request(method, ...)
  return vim.rpcrequest(child, method, ...)
end
local function lua(code, ...)
  return request("nvim_exec_lua", code, { ... })
end
local function wait_for(code, message)
  assert(vim.wait(2000, function() return lua(code) end, 10), message .. ": " ..
    lua("return vim.inspect({mode=vim.fn.mode(), buf=vim.api.nvim_get_current_buf()})"))
end

local ok, err = pcall(function()
  request("nvim_ui_attach", 80, 24, { rgb = true })
  lua([[
    local root = ...
    local spec = dofile(root .. "/lua/plugins/navigation.lua")
    spec.init()
    vim.api.nvim_create_user_command("TmuxNavigateRight", "wincmd l", {})
    vim.api.nvim_create_user_command("TmuxNavigateLeft", "wincmd h", {})
    for _, mapping in ipairs(spec.keys) do
      vim.keymap.set(mapping.mode or "n", mapping[1], mapping[2])
    end
    vim.cmd("rightbelow vsplit")
    vim.cmd("enew")
    vim.fn.jobstart({ "cat" }, { term = true })
    _G.terminal_buf = vim.api.nvim_get_current_buf()
    -- Ownership is the only stand-in: input, navigation and terminal are real.
    package.loaded["config.opencode_terminal"] = {
      is_buffer = function(buf) return buf == _G.terminal_buf end,
    }
    vim.cmd("wincmd h")
  ]], vim.fn.getcwd())
  request("nvim_input", "<C-l>")
  wait_for("return vim.api.nvim_get_current_buf() == _G.terminal_buf", "Ctrl-l enters OpenCode window")
  wait_for("return vim.fn.mode() == 't'", "Ctrl-l must activate OpenCode input without a resume marker")
  request("nvim_input", "focus-regression")
  wait_for([[return table.concat(vim.api.nvim_buf_get_lines(_G.terminal_buf, 0, -1, false), '\n'):find('focus%-regression') ~= nil]],
    "typing after navigation must reach the terminal job")
  lua("vim.cmd.stopinsert()")
  wait_for("return vim.fn.mode() == 'n'", "stopinsert enters terminal-normal mode")
  request("nvim_input", "<C-h>")
  wait_for("return vim.api.nvim_get_current_buf() ~= _G.terminal_buf",
    "leaving terminal-normal mode reaches the editor")
  request("nvim_input", "<C-l>")
  wait_for("return vim.api.nvim_get_current_buf() == _G.terminal_buf and vim.fn.mode() == 't'",
    "OpenCode resumes input even after leaving terminal-normal mode")
end)
vim.fn.jobstop(child)
assert(ok, err)
print("PASS Ctrl-l activates OpenCode terminal input")

-- Scroll Performance Diagnostic Script
-- Usage: :luafile lua/scroll-diagnose.lua
-- Then scroll through scroll-test.txt and observe which disable helps.
-- Re-run to cycle through tests, or :lua ScrollDiag.restore() to undo all.

_G.ScrollDiag = _G.ScrollDiag or {}
local tests = {
  { name = "neoscroll",    desc = "Disable smooth scroll animation (neoscroll.nvim)" },
  { name = "incline",      desc = "Disable floating filename bar (incline.nvim)" },
  { name = "blink_indent", desc = "Disable indent scope guides (blink.indent)" },
  { name = "blink_pairs",  desc = "Disable rainbow matchparen (blink.pairs)" },
  { name = "cursorline",   desc = "Disable cursor line highlight" },
  { name = "relativenumber", desc = "Disable relative line numbers" },
  { name = "lualine_aerial", desc = "Remove aerial breadcrumb from statusline" },
}

local state = _G.ScrollDiag
if not state.idx then state.idx = 0 end
if not state.saved then state.saved = {} end

-- Restore everything
function ScrollDiag.restore()
  -- Re-enable plugins
  pcall(function() require("neoscroll").setup({ mappings = { "<C-b>", "zt", "zz", "zb" } }) end)
  pcall(function() require("incline").enable() end)
  pcall(function() require("blink.indent").setup({ scope = { enabled = true } }) end)
  vim.opt.cursorline = true
  vim.opt.relativenumber = true
  state.idx = 0
  state.saved = {}
  vim.notify("ScrollDiag: ALL RESTORED", vim.log.levels.INFO)
end

-- Apply a single test
local function apply_test(name)
  if name == "neoscroll" then
    -- Unmap neoscroll keybindings and disable
    pcall(vim.keymap.del, "n", "<C-d>")
    pcall(vim.keymap.del, "n", "<C-f>")
    pcall(vim.keymap.del, "n", "<C-b>")
    -- Restore native scrolling
    vim.keymap.set("n", "<C-d>", "<C-u>", { desc = "Native scroll up" })
    vim.keymap.set("n", "<C-f>", "<C-d>", { desc = "Native scroll down" })
  elseif name == "incline" then
    pcall(function() require("incline").disable() end)
  elseif name == "blink_indent" then
    pcall(function() require("blink.indent").setup({ scope = { enabled = false }, static = { enabled = false } }) end)
  elseif name == "blink_pairs" then
    -- Disable matchparen autocmd
    pcall(function() vim.api.nvim_del_augroup_by_name("BlinkPairsMatchparen") end)
  elseif name == "cursorline" then
    vim.opt.cursorline = false
  elseif name == "relativenumber" then
    vim.opt.relativenumber = false
  elseif name == "lualine_aerial" then
    pcall(function()
      require("lualine").setup({
        sections = {
          lualine_c = {
            { "diagnostics" },
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            { "filename" },
          },
        },
      })
    end)
  end
end

-- Cycle through tests
state.idx = state.idx + 1
if state.idx > #tests then
  ScrollDiag.restore()
  return
end

local test = tests[state.idx]
apply_test(test.name)
vim.notify(
  string.format("ScrollDiag [%d/%d]: %s\n%s\nScroll now. Run again to try next, or :lua ScrollDiag.restore()",
    state.idx, #tests, test.name, test.desc),
  vim.log.levels.WARN
)

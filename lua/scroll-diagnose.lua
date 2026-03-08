-- Scroll Performance Diagnostic Script
-- Usage: :luafile lua/scroll-diagnose.lua
-- Then scroll through scroll-test.txt and observe which disable helps.
-- Re-run to cycle through tests, or :lua ScrollDiag.restore() to undo all.

_G.ScrollDiag = _G.ScrollDiag or {}
local tests = {
  { name = "incline",      desc = "Disable floating filename bar (incline.nvim) [auto-disabled in DiffView]" },
  { name = "blink_indent", desc = "Disable indent scope guides (blink.indent) [auto-disabled in DiffView]" },
  { name = "blink_pairs",  desc = "Disable rainbow matchparen (blink.pairs) [auto-disabled in DiffView]" },
  { name = "cursorline",   desc = "Disable cursor line highlight [auto-disabled in DiffView]" },
  { name = "relativenumber", desc = "Disable relative line numbers [auto-disabled in DiffView]" },
  { name = "inlay_hints",  desc = "Disable LSP inlay hints [auto-disabled in DiffView]" },
  { name = "symbol_usage", desc = "Disable symbol-usage ref/impl extmarks [auto-disabled in DiffView]" },
  { name = "lualine_aerial", desc = "Remove aerial breadcrumb from statusline" },
}

local state = _G.ScrollDiag
if not state.idx then state.idx = 0 end
if not state.saved then state.saved = {} end

-- Restore everything
function ScrollDiag.restore()
  -- Re-enable plugins
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
  if name == "incline" then
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
  elseif name == "inlay_hints" then
    if vim.lsp.inlay_hint then
      pcall(vim.lsp.inlay_hint.enable, false)
    end
  elseif name == "symbol_usage" then
    if package.loaded["symbol-usage"] then
      pcall(function() require("symbol-usage").toggle_globally() end)
    end
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

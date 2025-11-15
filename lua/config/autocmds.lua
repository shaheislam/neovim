-- Autocmd Configuration
-- Essential autocmds for nvim-mini

-- Load styling system
require("config.autocmds.styling").setup()

-- Load LSP autocmds
require("config.autocmds.lsp").setup()

-- Helper function to create augroups
local function augroup(name)
  return vim.api.nvim_create_augroup("nvim_mini_" .. name, { clear = true })
end

-- ============================================================================
-- Automatic Cleanup
-- ============================================================================

-- Remove trailing whitespace on save (excludes markdown/diff)
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("trim_whitespace"),
  pattern = "*",
  callback = function()
    local ft = vim.bo.filetype
    if ft == "markdown" or ft == "diff" then
      return
    end
    -- Save cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    -- Remove trailing whitespace
    vim.cmd([[%s/\s\+$//e]])
    -- Restore cursor position
    vim.api.nvim_win_set_cursor(0, cursor)
  end,
})

-- ============================================================================
-- File Management
-- ============================================================================

-- Auto-save all buffers when switching away from Neovim
vim.api.nvim_create_autocmd("FocusLost", {
  group = augroup("auto_save"),
  callback = function()
    vim.cmd("silent! wa")
  end,
})

-- Auto-save buffer when switching to another buffer
vim.api.nvim_create_autocmd("BufLeave", {
  group = augroup("auto_save_buffer_switch"),
  callback = function()
    if vim.bo.modified and not vim.bo.readonly and vim.fn.expand("%") ~= "" then
      vim.cmd("silent! write")
    end
  end,
})

-- ============================================================================
-- UI Enhancements
-- ============================================================================

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function()
    vim.highlight.on_yank({ timeout = 200 })
  end,
})

-- Transparent floating windows for all themes
local function set_transparent_floats()
  -- Explicitly make Normal background transparent
  vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })

  -- Get the Normal highlight to use as base (should be transparent)
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal" })

  -- Make floating windows transparent by linking to Normal
  vim.api.nvim_set_hl(0, "NormalFloat", { link = "Normal" })
  vim.api.nvim_set_hl(0, "FloatBorder", { link = "Normal" })

  -- Make popup menus (completion) use transparent background
  vim.api.nvim_set_hl(0, "Pmenu", { bg = normal_hl.bg })
  vim.api.nvim_set_hl(0, "PmenuSel", { bg = normal_hl.bg, reverse = true })
  vim.api.nvim_set_hl(0, "PmenuSbar", { bg = normal_hl.bg })
  vim.api.nvim_set_hl(0, "PmenuThumb", { bg = normal_hl.bg })

  -- Make which-key popup use transparent background
  vim.api.nvim_set_hl(0, "WhichKey", { link = "Normal" })
  vim.api.nvim_set_hl(0, "WhichKeyFloat", { link = "Normal" })
  vim.api.nvim_set_hl(0, "WhichKeyBorder", { link = "Normal" })

  -- Make blink.cmp menus transparent
  vim.api.nvim_set_hl(0, "BlinkCmpMenu", { link = "Normal" })
  vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "Normal" })
  vim.api.nvim_set_hl(0, "BlinkCmpDoc", { link = "Normal" })
  vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { link = "Normal" })

  -- Optional: Make diagnostic floating windows specifically transparent
  vim.api.nvim_set_hl(0, "DiagnosticFloatingError", { link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "DiagnosticFloatingWarn", { link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "DiagnosticFloatingInfo", { link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "DiagnosticFloatingHint", { link = "DiagnosticHint" })
end

-- Apply on colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
  group = augroup("transparent_floats"),
  callback = set_transparent_floats,
})

-- Also apply on startup after colorscheme is loaded
vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup("transparent_floats_init"),
  callback = function()
    vim.defer_fn(set_transparent_floats, 100) -- Small delay to ensure theme is fully loaded
  end,
})

-- Auto-open Oil when starting nvim without arguments
vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup("oil_on_startup"),
  callback = function()
    -- Only open Oil if:
    -- 1. No files were specified on the command line
    -- 2. Not reading from stdin
    -- 3. Not in diff mode
    local should_open_oil = vim.fn.argc() == 0
      and vim.fn.line2byte("$") == -1
      and not vim.o.diff

    if should_open_oil then
      -- Open Oil immediately (no delay needed since Oil is loaded eagerly)
      vim.defer_fn(function()
        require("oil").open(vim.fn.getcwd())
      end, 0)
    end
  end,
})

-- Close certain filetypes with 'q'
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = { "qf", "help", "man", "lspinfo", "checkhealth" },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
})

-- Auto-resize splits when terminal is resized
vim.api.nvim_create_autocmd("VimResized", {
  group = augroup("resize_splits"),
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
})

-- ============================================================================
-- Restore cursor position when opening files
-- ============================================================================

vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("restore_cursor"),
  callback = function(event)
    local exclude = { "gitcommit" }
    local buf = event.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].nvim_mini_last_loc then
      return
    end
    vim.b[buf].nvim_mini_last_loc = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

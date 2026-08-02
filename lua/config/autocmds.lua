-- Autocmd Configuration
-- Essential autocmds for nvim-mini

-- Load styling system
require("config.autocmds.styling").setup()

-- Load LSP autocmds
require("config.autocmds.lsp").setup()

-- Load hot-reload for Claude Code integration
require("config.hotreload").setup()

-- Register the native OpenCode TUI RPC receiver before a terminal can start.
require("config.opencode_handoff").setup()

-- Load Claude Code bridge (writes editor state for Claude Code hooks)
require("config.claude-bridge").setup()

-- Load repo-local annotations (stored in .tmp/annotations.json)
require("config.annotations").setup()

-- Register this pane for deliberate tmux/Claude Diffview review fallback.
require("config.diffview_idle").setup()

-- Track the last real editing buffer for transient UI close/restore flows
require("config.return_target").setup()

-- Load kubectl helpers
require("config.kubectl").setup()

local bufutil = require("config.bufutil")

-- Helper function to create augroups
local function augroup(name)
  return vim.api.nvim_create_augroup("nvim_mini_" .. name, { clear = true })
end

-- Mark very large files so LSP/UI integrations can skip expensive adornments.
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  group = augroup("large_file_guard"),
  callback = function(event)
    local name = vim.api.nvim_buf_get_name(event.buf)
    local stat = name ~= "" and vim.uv.fs_stat(name) or nil
    local is_large = stat and stat.size > (vim.g.nvim_mini_large_file_bytes or 2 * 1024 * 1024)

    if not is_large then
      return
    end

    vim.b[event.buf].nvim_mini_large_file = true
    vim.b[event.buf].autoformat = false
    vim.diagnostic.enable(false, { bufnr = event.buf })

    vim.api.nvim_create_autocmd("BufReadPost", {
      group = augroup("large_file_guard_post_" .. event.buf),
      buffer = event.buf,
      once = true,
      callback = function()
        vim.opt_local.foldmethod = "manual"
        vim.opt_local.foldenable = false
        vim.cmd("silent! syntax off")
      end,
      desc = "Disable expensive features for large files",
    })
  end,
  desc = "Mark large files for performance guards",
})

-- ============================================================================
-- Automatic Cleanup
-- ============================================================================

-- Remove trailing whitespace on save (excludes markdown/diff)
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("trim_whitespace"),
  pattern = "*",
  callback = function()
    local ft = vim.bo.filetype
    if ft == "markdown" or ft == "diff" or not vim.bo.modifiable then
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

local function auto_save_buffer(buf)
  if
    not vim.api.nvim_buf_is_valid(buf)
    or not vim.api.nvim_buf_is_loaded(buf)
    or not vim.bo[buf].modified
    or vim.bo[buf].readonly
    or vim.api.nvim_buf_get_name(buf) == ""
    or vim.b[buf].agent_plan_disk_conflict
  then
    return
  end

  pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd("silent! write")
  end)
end

-- Auto-save all buffers when switching away from Neovim
vim.api.nvim_create_autocmd("FocusLost", {
  group = augroup("auto_save"),
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      auto_save_buffer(buf)
    end
  end,
})

-- Auto-save buffer when switching to another buffer
vim.api.nvim_create_autocmd("BufLeave", {
  group = augroup("auto_save_buffer_switch"),
  callback = function(event)
    auto_save_buffer(event.buf)
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

  local link_to_normal = {
    "NormalFloat",
    "FloatBorder",
    "FloatTitle",
    "FloatFooter",
    "WhichKeyNormal",
    "WhichKey",
    "WhichKeyFloat",
    "WhichKeyBorder",
    "WhichKeyTitle",
    "BlinkCmpMenu",
    "BlinkCmpMenuBorder",
    "BlinkCmpDoc",
    "BlinkCmpDocBorder",
  }

  for _, group in ipairs(link_to_normal) do
    vim.api.nvim_set_hl(0, group, { link = "Normal" })
  end

  -- Make popup menus (completion) use transparent background
  vim.api.nvim_set_hl(0, "Pmenu", { bg = normal_hl.bg })
  vim.api.nvim_set_hl(0, "PmenuSel", { bg = normal_hl.bg, reverse = true })
  vim.api.nvim_set_hl(0, "PmenuSbar", { bg = normal_hl.bg })
  vim.api.nvim_set_hl(0, "PmenuThumb", { bg = normal_hl.bg })

  local diagnostic_links = {
    DiagnosticFloatingError = "DiagnosticError",
    DiagnosticFloatingWarn = "DiagnosticWarn",
    DiagnosticFloatingInfo = "DiagnosticInfo",
    DiagnosticFloatingHint = "DiagnosticHint",
    DiagnosticVirtualTextError = "DiagnosticError",
    DiagnosticVirtualTextWarn = "DiagnosticWarn",
    DiagnosticVirtualTextInfo = "DiagnosticInfo",
    DiagnosticVirtualTextHint = "DiagnosticHint",
  }

  for group, link in pairs(diagnostic_links) do
    vim.api.nvim_set_hl(0, group, { link = link })
  end
end

-- Apply on colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
  group = augroup("transparent_floats"),
  callback = set_transparent_floats,
})

-- matugen.nvim reloads in place when colors.json changes and emits a User event
-- instead of a full ColorScheme event. Reapply transparency after its highlights land.
vim.api.nvim_create_autocmd("User", {
  group = augroup("transparent_floats_matugen"),
  pattern = "MatugenReloaded",
  callback = function()
    vim.defer_fn(set_transparent_floats, 20)
  end,
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
    -- 4. No buffers created by -c commands (Octo, DiffviewOpen, etc.)
    local has_named_buffers = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) ~= "" then
        has_named_buffers = true
        break
      end
    end

    local should_open_oil = vim.fn.argc() == 0
      and vim.fn.line2byte("$") == -1
      and not vim.o.diff
      and not has_named_buffers

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
    local current_tab = vim.api.nvim_get_current_tabpage()

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local has_diffview_layout = false

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if bufutil.is_diffview_buffer(buf) then
          has_diffview_layout = true
        end
      end

      if not has_diffview_layout then
        vim.api.nvim_set_current_tabpage(tab)
        vim.cmd("wincmd =")
      end
    end

    if vim.api.nvim_tabpage_is_valid(current_tab) then
      vim.api.nvim_set_current_tabpage(current_tab)
    end

    local ok, workflow = pcall(require, "git.workflow")
    if ok then
      workflow.reposition_commit_info_window()
      vim.defer_fn(workflow.reposition_commit_info_window, 50)
    end
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

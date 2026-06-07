-- LSP Autocmds - Language Server Protocol integration
-- Consolidates all LSP-related autocmds

local M = {}

local function augroup(name)
  return vim.api.nvim_create_augroup("lsp_" .. name, { clear = true })
end

-- Check if current buffer/window is a diff buffer (skip expensive LSP ops)
-- Uses vim.wo.diff as primary signal (set by diffview on its panes),
-- plus URI/filetype checks for diffview's non-diff panels.
local function is_diff_buf(bufnr)
  bufnr = bufnr or 0
  -- Primary: check if window is in diff mode (most reliable for diff panes)
  if vim.wo.diff then
    return true
  end
  -- Fallback: check diffview-specific buffer name and filetypes
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name:match("^diffview://") then
    return true
  end
  local ft = vim.bo[bufnr].filetype
  return ft == "DiffviewFiles" or ft == "DiffviewFileHistory"
end

local function is_large_buf(bufnr)
  bufnr = bufnr or 0
  return vim.b[bufnr].nvim_mini_large_file == true
end

function M.setup()
  -- ============================================================================
  -- Import Organization
  -- ============================================================================

  -- Organize imports automatically on save (Python, Go, TypeScript)
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = augroup("organize_imports"),
    pattern = { "*.py", "*.go", "*.ts", "*.tsx" },
    callback = function()
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      if #clients == 0 then
        return
      end
      local client = clients[1]
      local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
      params.context = { only = { "source.organizeImports" } }
      local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
      for _, res in pairs(result or {}) do
        for _, action in pairs(res.result or {}) do
          if action.edit then
            local ok, err = pcall(vim.lsp.util.apply_workspace_edit, action.edit, "utf-8")
            if not ok then
              vim.notify("Failed to organize imports: " .. tostring(err), vim.log.levels.WARN)
            end
          end
        end
      end
    end,
  })

  -- ============================================================================
  -- Document Highlighting
  -- ============================================================================

  -- Highlight symbol references under cursor (normal mode only)
  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup("document_highlight"),
    callback = function()
      if is_diff_buf() or is_large_buf() then return end
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      for _, client in pairs(clients) do
        if client.server_capabilities.documentHighlightProvider then
          pcall(vim.lsp.buf.document_highlight)
          return -- one successful call is enough
        end
      end
    end,
  })

  -- Clear reference highlights when cursor moves (debounced to avoid scroll stutter).
  -- Without debouncing, clear_references fires an LSP request per cursor movement
  -- which causes visible stutter during rapid scrolling.
  local clear_ref_timer = vim.uv.new_timer()
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup("document_highlight_clear"),
    callback = function()
      if is_diff_buf() or is_large_buf() then return end
      clear_ref_timer:stop()
      clear_ref_timer:start(100, 0, vim.schedule_wrap(function()
        pcall(vim.lsp.buf.clear_references)
      end))
    end,
  })

  -- ============================================================================
  -- Diagnostics Display
  -- ============================================================================

  -- Boolean flag to track whether our diagnostic float is open.
  -- Replaces the previous O(n) window scan (nvim_list_wins + nvim_win_get_config per window).
  local diagnostic_float_open = false

  -- Reset flag when cursor moves or we leave the context
  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
    group = augroup("diagnostic_hover_reset"),
    callback = function()
      diagnostic_float_open = false
    end,
  })

  -- Show diagnostics in hover window when cursor is on a line with diagnostics
  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup("diagnostic_hover"),
    callback = function()
      if is_diff_buf() or is_large_buf() then return end
      if diagnostic_float_open then return end

      -- Check if diagnostics are enabled globally
      if vim.diagnostic.is_enabled and not vim.diagnostic.is_enabled() then
        return
      end

      local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
      if #diagnostics > 0 then
        vim.diagnostic.open_float(nil, {
          focusable = false,
          close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
          border = "rounded",
          source = true,
          prefix = " ",
          scope = "cursor",
        })
        diagnostic_float_open = true
      end
    end,
  })

  -- ============================================================================
  -- Code Lens Management
  -- ============================================================================

  -- Safe code lens refresh with capability checking
  local function refresh_codelens()
    local bufnr = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end

    if vim.bo[bufnr].buftype ~= "" then
      return
    end

    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in pairs(clients) do
      if client.server_capabilities and client.server_capabilities.codeLensProvider then
        local ok, _ = pcall(vim.lsp.codelens.enable, true)
        if not ok then
          -- Silently fail - some LSP servers don't properly support code lenses
          return
        end
        break -- Only need to enable once
      end
    end
  end

  -- Auto-refresh code lens (debounced, no BufEnter to avoid spurious fires)
  if vim.g.auto_refresh_codelens then
    local codelens_timer = vim.uv.new_timer()
    vim.api.nvim_create_autocmd({ "InsertLeave", "BufWritePost" }, {
      group = augroup("codelens_refresh"),
      callback = function()
        codelens_timer:stop()
        codelens_timer:start(500, 0, vim.schedule_wrap(refresh_codelens))
      end,
    })
  end

  -- ============================================================================
  -- Inlay Hints Management
  -- ============================================================================

  -- Enable inlay hints for LSP servers that support them
  vim.api.nvim_create_autocmd({ "LspAttach" }, {
    group = augroup("inlay_hints"),
    callback = function(args)
      -- Skip diff buffers (inlay hints disabled in diff_buf_read for scroll perf)
      if is_diff_buf(args.buf) or is_large_buf(args.buf) then return end
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.server_capabilities.inlayHintProvider then
        -- Enable inlay hints by default
        if vim.lsp.inlay_hint then
          vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
        end

        -- Optionally toggle based on insert mode (opt-in via global variable)
        if vim.g.toggle_inlay_hints_on_insert then
          vim.api.nvim_create_autocmd({ "InsertEnter" }, {
            group = augroup("inlay_hints_insert"),
            buffer = args.buf,
            callback = function()
              if vim.lsp.inlay_hint then
                vim.lsp.inlay_hint.enable(false, { bufnr = args.buf })
              end
            end,
          })

          vim.api.nvim_create_autocmd({ "InsertLeave" }, {
            group = augroup("inlay_hints_normal"),
            buffer = args.buf,
            callback = function()
              if is_diff_buf(args.buf) or is_large_buf(args.buf) then return end
              if vim.lsp.inlay_hint then
                vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
              end
            end,
          })
        end
      end
    end,
  })

  -- ============================================================================
  -- LSP Attach Enhancements
  -- ============================================================================

  vim.api.nvim_create_autocmd("LspAttach", {
    group = augroup("lsp_attach"),
    callback = function(args)
      local bufnr = args.buf
      local client = vim.lsp.get_client_by_id(args.data.client_id)

      if not client then
        return
      end

      -- Enable completion triggered by <c-x><c-o>
      vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

      -- Enable tagfunc
      if client.server_capabilities.definitionProvider then
        vim.bo[bufnr].tagfunc = "v:lua.vim.lsp.tagfunc"
      end

      -- Format on save for specific servers
      local format_on_save_servers = {
        gopls = true,
        rust_analyzer = true,
        ts_ls = true,
        lua_ls = true,
        ruff = true,
      }

      if format_on_save_servers[client.name] and client.server_capabilities.documentFormattingProvider then
        vim.api.nvim_create_autocmd("BufWritePre", {
          group = augroup("format_on_save_" .. bufnr),
          buffer = bufnr,
          callback = function()
            -- Check if formatting is disabled
            if vim.b.autoformat == false or vim.g.autoformat == false then
              return
            end

            local ok, _ = pcall(vim.lsp.buf.format, {
              bufnr = bufnr,
              timeout_ms = 2000,
              filter = function(c)
                return c.id == client.id
              end,
            })

            if not ok then
              vim.notify("Formatting failed for " .. client.name, vim.log.levels.WARN)
            end
          end,
        })
      end
    end,
  })

  -- ============================================================================
  -- Workspace Configuration
  -- ============================================================================

  -- Auto-reload LSP when specific config files change
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup("lsp_config_reload"),
    pattern = {
      "tsconfig.json",
      "jsconfig.json",
      ".eslintrc*",
      "package.json",
      "Cargo.toml",
      "go.mod",
      "pyproject.toml",
      "setup.py",
      "setup.cfg",
      ".flake8",
      ".pylintrc",
    },
    callback = function()
      -- Restart LSP servers for this buffer
      vim.schedule(function()
        vim.notify("Config file changed, restarting LSP...", vim.log.levels.INFO)
        vim.cmd("LspRestart")
      end)
    end,
  })

  -- Semantic tokens: handled natively by Neovim 0.11+ via
  -- workspace/semanticTokens/refresh notifications from the LSP server.
  -- No manual autocmd needed.
end

return M

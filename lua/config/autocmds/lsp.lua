-- LSP Autocmds - Language Server Protocol integration
-- Consolidates all LSP-related autocmds

local M = {}

local function augroup(name)
  return vim.api.nvim_create_augroup("lsp_" .. name, { clear = true })
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
      local params = vim.lsp.util.make_range_params()
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

  -- Highlight symbol references under cursor
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = augroup("document_highlight"),
    callback = function()
      local clients = vim.lsp.get_active_clients({ bufnr = 0 })
      for _, client in pairs(clients) do
        if client.server_capabilities.documentHighlightProvider then
          local ok, _ = pcall(vim.lsp.buf.document_highlight)
          if not ok then
            -- Silently fail if document highlight fails
            return
          end
        end
      end
    end,
  })

  -- Clear reference highlights when cursor moves
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup("document_highlight_clear"),
    callback = function()
      pcall(vim.lsp.buf.clear_references)
    end,
  })

  -- ============================================================================
  -- Diagnostics Display
  -- ============================================================================

  -- Show diagnostics in hover window when cursor is on a line with diagnostics
  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup("diagnostic_hover"),
    callback = function()
      -- Check if diagnostics are enabled globally
      local diagnostics_enabled = true
      if vim.diagnostic.is_enabled then
        diagnostics_enabled = vim.diagnostic.is_enabled()
      end

      -- Only show if diagnostics are enabled AND there are diagnostics on the current line
      if not diagnostics_enabled then
        return
      end

      local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
      if #diagnostics > 0 then
        -- Check if any floating window is already open
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local config = vim.api.nvim_win_get_config(win)
          if config.relative ~= "" then
            return -- Don't open if a floating window exists
          end
        end

        vim.diagnostic.open_float(nil, {
          focusable = false,
          close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
          border = "rounded",
          source = "always",
          prefix = " ",
          scope = "cursor",
        })
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

    local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
    for _, client in pairs(clients) do
      if client.server_capabilities and client.server_capabilities.codeLensProvider then
        local ok, _ = pcall(vim.lsp.codelens.refresh)
        if not ok then
          -- Silently fail - some LSP servers don't properly support refresh
          return
        end
        break -- Only need to call refresh once
      end
    end
  end

  -- Auto-refresh code lens on specific events (opt-in via global variable)
  if vim.g.auto_refresh_codelens then
    vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "BufWritePost" }, {
      group = augroup("codelens_refresh"),
      callback = refresh_codelens,
    })
  end

  -- ============================================================================
  -- Inlay Hints Management
  -- ============================================================================

  -- Enable inlay hints for LSP servers that support them
  vim.api.nvim_create_autocmd({ "LspAttach" }, {
    group = augroup("inlay_hints"),
    callback = function(args)
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
        tsserver = true,
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

  -- ============================================================================
  -- Semantic Tokens
  -- ============================================================================

  -- Refresh semantic tokens periodically for better highlighting
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
    group = augroup("semantic_tokens"),
    callback = function()
      local clients = vim.lsp.get_active_clients({ bufnr = 0 })
      for _, client in pairs(clients) do
        if client.server_capabilities.semanticTokensProvider then
          vim.schedule(function()
            pcall(vim.lsp.buf_request, 0, "textDocument/semanticTokens/full", {
              textDocument = vim.lsp.util.make_text_document_params(),
            })
          end)
          break
        end
      end
    end,
  })
end

return M

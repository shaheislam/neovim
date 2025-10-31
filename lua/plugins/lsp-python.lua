-- Python LSP Configuration
-- Enhanced Python development with basedpyright and ruff

return {
  -- Python LSP configurations
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- Ensure opts.servers exists
      opts.servers = opts.servers or {}

      -- Basedpyright configuration
      opts.servers.basedpyright = vim.tbl_deep_extend("force", opts.servers.basedpyright or {}, {
        settings = {
          basedpyright = {
            analysis = {
              autoSearchPaths = true,
              diagnosticMode = "openFilesOnly",
              useLibraryCodeForTypes = true,
              typeCheckingMode = "standard", -- "off", "basic", "standard", "strict"
              autoImportCompletions = true,
              diagnosticSeverityOverrides = {
                reportUnusedImport = "warning",
                reportUnusedVariable = "warning",
                reportUnusedFunction = "warning",
                reportUnusedClass = "warning",
                reportDuplicateImport = "warning",
              },
            },
          },
        },
        -- Suppress progress notifications for basedpyright
        handlers = {
          ["$/progress"] = function() end,
        },
      })

      -- Ruff LSP for fast Python linting
      opts.servers.ruff = vim.tbl_deep_extend("force", opts.servers.ruff or {}, {
        cmd_env = { RUFF_TRACE = "messages" },
        init_options = {
          settings = {
            logLevel = "error",
            -- Ruff settings
            args = {
              "--extend-select=B,C,E,F,W,I",
              "--ignore=E501", -- Line too long (let formatter handle it)
            },
          },
        },
      })

      return opts
    end,
  },

  -- Python-specific keymaps and autocmds
  {
    "neovim/nvim-lspconfig",
    opts = function()
      -- Organize imports keymap for Python
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("python_lsp_keymaps", { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client then
            return
          end

          -- Only for Python files with ruff
          if client.name == "ruff" and vim.bo[event.buf].filetype == "python" then
            vim.keymap.set("n", "<leader>co", function()
              vim.lsp.buf.code_action({
                apply = true,
                context = {
                  only = { "source.organizeImports" },
                  diagnostics = {},
                },
              })
            end, { buffer = event.buf, desc = "Organize Imports" })
          end
        end,
      })

      -- Auto-format Python files on save with ruff
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("python_format_on_save", { clear = true }),
        pattern = { "*.py" },
        callback = function()
          vim.lsp.buf.format({ async = true })
        end,
      })
    end,
  },
}

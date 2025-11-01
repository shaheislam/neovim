-- Rust LSP Configuration (Lazy-Loaded)
-- Only loads when opening Rust files or Cargo.toml

return {
  -- Rustaceanvim: Enhanced Rust development
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    lazy = false, -- Plugin manages its own lazy-loading
    ft = { "rust" }, -- Only load for Rust files
    config = function()
      vim.g.rustaceanvim = {
        -- Plugin configuration
        tools = {
          hover_actions = {
            auto_focus = false,
            replace_builtin_hover = false,
          },
          code_actions = {
            ui_select_fallback = true,
          },
        },
        -- LSP configuration
        server = {
          on_attach = function(client, bufnr)
            -- Set up keymaps for Rust development
            local opts = { buffer = bufnr, silent = true }
            vim.keymap.set("n", "<leader>cra", function()
              vim.cmd.RustLsp("codeAction")
            end, vim.tbl_extend("force", opts, { desc = "Rust Code Action" }))
            vim.keymap.set("n", "<leader>dr", function()
              vim.cmd.RustLsp("debuggables")
            end, vim.tbl_extend("force", opts, { desc = "Rust Debuggables" }))
            vim.keymap.set("n", "<leader>rr", function()
              vim.cmd.RustLsp("runnables")
            end, vim.tbl_extend("force", opts, { desc = "Rust Runnables" }))
            vim.keymap.set("n", "<leader>rt", function()
              vim.cmd.RustLsp("testables")
            end, vim.tbl_extend("force", opts, { desc = "Rust Testables" }))
            vim.keymap.set("n", "K", function()
              vim.cmd.RustLsp({ "hover", "actions" })
            end, vim.tbl_extend("force", opts, { desc = "Rust Hover Actions" }))
            vim.keymap.set("n", "<leader>re", function()
              vim.cmd.RustLsp("expandMacro")
            end, vim.tbl_extend("force", opts, { desc = "Rust Expand Macro" }))
            vim.keymap.set("n", "<leader>rc", function()
              vim.cmd.RustLsp("openCargo")
            end, vim.tbl_extend("force", opts, { desc = "Open Cargo.toml" }))
            vim.keymap.set("n", "<leader>rp", function()
              vim.cmd.RustLsp("parentModule")
            end, vim.tbl_extend("force", opts, { desc = "Rust Parent Module" }))
            vim.keymap.set("n", "<leader>rj", function()
              vim.cmd.RustLsp("joinLines")
            end, vim.tbl_extend("force", opts, { desc = "Rust Join Lines" }))
            vim.keymap.set("n", "<leader>rs", function()
              vim.cmd.RustLsp({ "ssr" })
            end, vim.tbl_extend("force", opts, { desc = "Rust Structural Search Replace" }))
            vim.keymap.set("n", "<leader>rg", function()
              vim.cmd.RustLsp("crateGraph")
            end, vim.tbl_extend("force", opts, { desc = "Rust Crate Graph" }))
          end,
          default_settings = {
            -- rust-analyzer settings
            ["rust-analyzer"] = {
              cargo = {
                allFeatures = true,
                loadOutDirsFromCheck = true,
                buildScripts = {
                  enable = true,
                },
              },
              checkOnSave = {
                allFeatures = true,
                command = "clippy",
                extraArgs = {
                  "--",
                  "--no-deps",
                  "-Dclippy::correctness",
                  "-Wclippy::style",
                  "-Wclippy::complexity",
                  "-Wclippy::perf",
                },
              },
              procMacro = {
                enable = true,
                ignored = {
                  ["async-trait"] = { "async_trait" },
                  ["napi-derive"] = { "napi" },
                  ["async-recursion"] = { "async_recursion" },
                },
              },
              inlayHints = {
                bindingModeHints = {
                  enable = false,
                },
                chainingHints = {
                  enable = true,
                },
                closingBraceHints = {
                  enable = true,
                  minLines = 25,
                },
                closureReturnTypeHints = {
                  enable = "never",
                },
                lifetimeElisionHints = {
                  enable = "never",
                  useParameterNames = false,
                },
                maxLength = 25,
                parameterHints = {
                  enable = true,
                },
                reborrowHints = {
                  enable = "never",
                },
                renderColons = true,
                typeHints = {
                  enable = true,
                  hideClosureInitialization = false,
                  hideNamedConstructor = false,
                },
              },
            },
          },
        },
        -- DAP configuration
        -- rustaceanvim will auto-configure DAP if nvim-dap is installed
        -- It will try to use codelldb if available, otherwise fall back to lldb
        dap = {
          -- adapter = true means use the default adapter configuration
          -- rustaceanvim will handle the setup automatically
          adapter = true,
        },
      }
    end,
  },

  -- crates.nvim: Manage Rust crate dependencies
  {
    "saecki/crates.nvim",
    event = { "BufRead Cargo.toml" }, -- Only load for Cargo.toml
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local crates = require("crates")
      crates.setup({
        autoload = true,
        autoupdate = true,
        loading_indicator = true,
        date_format = "%Y-%m-%d",
        thousands_separator = ",",
        notification_title = "Crates",
        curl_args = { "-sL", "--retry", "1" },
        text = {
          loading = "   Loading...",
          version = "   %s",
          prerelease = "   %s",
          yanked = "   %s yanked",
          nomatch = "   No match",
          upgrade = "   %s",
          error = "   Error fetching crate",
        },
        highlight = {
          loading = "CratesNvimLoading",
          version = "CratesNvimVersion",
          prerelease = "CratesNvimPreRelease",
          yanked = "CratesNvimYanked",
          nomatch = "CratesNvimNoMatch",
          upgrade = "CratesNvimUpgrade",
          error = "CratesNvimError",
        },
        popup = {
          autofocus = false,
          hide_on_select = false,
          copy_register = '"',
          style = "minimal",
          border = "rounded",
          show_version_date = true,
          show_dependency_version = true,
          max_height = 30,
          min_width = 20,
          padding = 1,
        },
        lsp = {
          enabled = true,
          on_attach = function(client, bufnr)
            -- Crates.nvim keymaps for Cargo.toml
            local opts = { noremap = true, silent = true, buffer = bufnr }
            vim.keymap.set(
              "n",
              "<leader>cv",
              function()
                crates.show_versions_popup()
              end,
              vim.tbl_extend("force", opts, { desc = "Show crate versions" })
            )
            vim.keymap.set(
              "n",
              "<leader>cf",
              function()
                crates.show_features_popup()
              end,
              vim.tbl_extend("force", opts, { desc = "Show crate features" })
            )
            vim.keymap.set(
              "n",
              "<leader>cd",
              function()
                crates.show_dependencies_popup()
              end,
              vim.tbl_extend("force", opts, { desc = "Show crate dependencies" })
            )
            vim.keymap.set(
              "n",
              "<leader>cu",
              function()
                crates.update_crate()
              end,
              vim.tbl_extend("force", opts, { desc = "Update crate" })
            )
            vim.keymap.set(
              "v",
              "<leader>cu",
              function()
                crates.update_crates()
              end,
              vim.tbl_extend("force", opts, { desc = "Update selected crates" })
            )
            vim.keymap.set(
              "n",
              "<leader>cua",
              function()
                crates.update_all_crates()
              end,
              vim.tbl_extend("force", opts, { desc = "Update all crates" })
            )
            vim.keymap.set(
              "n",
              "<leader>cU",
              function()
                crates.upgrade_crate()
              end,
              vim.tbl_extend("force", opts, { desc = "Upgrade crate" })
            )
            vim.keymap.set(
              "v",
              "<leader>cU",
              function()
                crates.upgrade_crates()
              end,
              vim.tbl_extend("force", opts, { desc = "Upgrade selected crates" })
            )
            vim.keymap.set(
              "n",
              "<leader>cA",
              function()
                crates.upgrade_all_crates()
              end,
              vim.tbl_extend("force", opts, { desc = "Upgrade all crates" })
            )
            vim.keymap.set(
              "n",
              "<leader>cH",
              function()
                crates.open_homepage()
              end,
              vim.tbl_extend("force", opts, { desc = "Open crate homepage" })
            )
            vim.keymap.set(
              "n",
              "<leader>cR",
              function()
                crates.open_repository()
              end,
              vim.tbl_extend("force", opts, { desc = "Open crate repository" })
            )
            vim.keymap.set(
              "n",
              "<leader>cD",
              function()
                crates.open_documentation()
              end,
              vim.tbl_extend("force", opts, { desc = "Open crate documentation" })
            )
            vim.keymap.set(
              "n",
              "<leader>cC",
              function()
                crates.open_crates_io()
              end,
              vim.tbl_extend("force", opts, { desc = "Open crates.io" })
            )
            vim.keymap.set(
              "n",
              "<leader>cL",
              function()
                crates.open_lib_rs()
              end,
              vim.tbl_extend("force", opts, { desc = "Open lib.rs" })
            )
          end,
          actions = true,
          completion = true,
          hover = true,
        },
      })

      -- Auto-commands for crates.nvim
      vim.api.nvim_create_autocmd("BufRead", {
        group = vim.api.nvim_create_augroup("CratesToml", { clear = true }),
        pattern = "Cargo.toml",
        callback = function()
          crates.show()
        end,
      })
    end,
  },
}

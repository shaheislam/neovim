-- Nix-aware LSP Configuration
-- Prioritizes Nix-provided LSPs (no Mason fallback)
-- This allows per-project LSP versioning via Nix flakes

-- Helper function to check if a command exists
local function command_exists(cmd)
  local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result ~= ""
  end
  return false
end

-- Helper function to get command path for LSP
-- Only checks Nix-provided tools (no Mason fallback)
local function get_lsp_cmd(nix_cmd)
  -- Check if we're in a Nix environment
  local in_nix_shell = os.getenv("IN_NIX_SHELL") ~= nil
  local nix_lsp_enabled = os.getenv("NIX_LSP_ENABLED") == "true"

  -- If in Nix shell or Nix LSP is enabled, prefer Nix
  if in_nix_shell or nix_lsp_enabled then
    if command_exists(nix_cmd) then
      vim.notify("Using Nix-provided " .. nix_cmd, vim.log.levels.DEBUG)
      return { nix_cmd }
    end
  end

  -- Check system-wide Nix installation
  if command_exists(nix_cmd) then
    vim.notify("Using system Nix " .. nix_cmd, vim.log.levels.DEBUG)
    return { nix_cmd }
  end

  -- LSP not found - return nil to prevent starting
  vim.notify("LSP " .. nix_cmd .. " not available from Nix", vim.log.levels.DEBUG)
  return nil
end

return {
  -- nvim-lspconfig: Official LSP configuration plugin
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      -- Optional: nvim-cmp for completion (if you add it later)
      -- Optional: which-key for LSP keymap help
    },
    config = function()
      local lspconfig = require("lspconfig")

      -- Enhanced diagnostics configuration
      vim.diagnostic.config({
        underline = true,
        update_in_insert = false,
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
          -- Only show virtual text for errors and warnings
          severity = { min = vim.diagnostic.severity.WARN },
        },
        severity_sort = true,
        float = {
          focusable = false,
          style = "minimal",
          border = "rounded",
          source = "always",
          header = "",
          prefix = "",
        },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.HINT] = " ",
            [vim.diagnostic.severity.INFO] = " ",
          },
        },
      })

      -- Enhanced hover configuration
      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
        border = "rounded",
        max_width = 80,
        max_height = 20,
      })

      -- Enhanced signature help configuration
      vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
        border = "rounded",
        focusable = false,
        relative = "cursor",
      })

      -- LSP server configurations
      local servers = {
        -- Go
        gopls = {
          cmd = get_lsp_cmd("gopls"),
          settings = {
            gopls = {
              gofumpt = true,
              usePlaceholders = true,
              analyses = {
                unusedparams = true,
              },
              codelenses = {
                gc_details = true,
                generate = true,
                regenerate_cgo = true,
                test = true,
                tidy = true,
                upgrade_dependency = true,
                vendor = true,
              },
              hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
              },
            },
          },
        },

        -- Rust (basic setup, enhanced by rustaceanvim which is lazy-loaded)
        rust_analyzer = {
          cmd = get_lsp_cmd("rust-analyzer"),
          settings = {
            ["rust-analyzer"] = {
              cargo = {
                allFeatures = true,
              },
              lens = {
                enable = true,
                references = {
                  adt = { enable = true },
                  enumVariant = { enable = true },
                  method = { enable = true },
                  trait = { enable = true },
                },
                implementations = { enable = true },
                run = { enable = true },
                debug = { enable = true },
              },
            },
          },
        },

        -- Python (basedpyright preferred, pyright fallback)
        basedpyright = {
          cmd = function()
            -- Try basedpyright-langserver first
            local basedpyright_cmd = get_lsp_cmd("basedpyright-langserver")
            if basedpyright_cmd then
              return { basedpyright_cmd[1], "--stdio" }
            end

            -- Fall back to pyright if basedpyright isn't available
            local pyright_cmd = get_lsp_cmd("pyright-langserver")
            if pyright_cmd then
              vim.notify("Using pyright instead of basedpyright", vim.log.levels.INFO)
              return { pyright_cmd[1], "--stdio" }
            end

            return nil
          end,
          settings = {
            basedpyright = {
              analysis = {
                -- Enable code lens for Python
                enableCodeLens = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
              },
            },
          },
        },

        -- Python linting (ruff)
        ruff = {
          cmd = get_lsp_cmd("ruff-lsp"),
        },

        -- TypeScript/JavaScript
        ts_ls = {
          cmd = get_lsp_cmd("typescript-language-server"),
          settings = {
            typescript = {
              implementationsCodeLens = { enabled = true },
              referencesCodeLens = {
                enabled = true,
                showOnAllFunctions = true,
              },
            },
            javascript = {
              implementationsCodeLens = { enabled = true },
              referencesCodeLens = {
                enabled = true,
                showOnAllFunctions = true,
              },
            },
          },
        },

        -- Terraform
        terraformls = {
          cmd = get_lsp_cmd("terraform-ls"),
        },

        -- Ansible support removed (ansible-language-server unmaintained/removed from nixpkgs)
        -- Use ansible-lint for validation instead

        -- Docker
        dockerls = {
          cmd = get_lsp_cmd("docker-langserver"),
        },

        docker_compose_language_service = {
          cmd = get_lsp_cmd("docker-compose-langserver"),
        },

        -- Helm
        helm_ls = {
          cmd = get_lsp_cmd("helm_ls"),
        },

        -- YAML
        yamlls = {
          cmd = get_lsp_cmd("yaml-language-server"),
        },

        -- JSON
        jsonls = {
          cmd = get_lsp_cmd("vscode-json-language-server"),
        },

        -- Lua
        lua_ls = {
          cmd = get_lsp_cmd("lua-language-server"),
          settings = {
            Lua = {
              runtime = {
                version = "LuaJIT",
              },
              diagnostics = {
                globals = { "vim" },
              },
              workspace = {
                library = vim.api.nvim_get_runtime_file("", true),
                checkThirdParty = false,
              },
              telemetry = {
                enable = false,
              },
              hint = {
                enable = true,
                setType = false,
                paramType = true,
                paramName = "Disable",
                semicolon = "Disable",
                arrayIndex = "Disable",
              },
              codeLens = {
                enable = true,
              },
            },
          },
        },

        -- Markdown
        marksman = {
          cmd = get_lsp_cmd("marksman"),
        },

        -- Bash
        bashls = {
          cmd = get_lsp_cmd("bash-language-server"),
        },

        -- TOML
        taplo = {
          cmd = get_lsp_cmd("taplo"),
        },

        -- Nix
        nil_ls = {
          cmd = get_lsp_cmd("nil"),
          settings = {
            ["nil"] = {
              formatting = {
                command = { "nixpkgs-fmt" },
              },
            },
          },
        },

        -- SQL
        sqls = {
          cmd = get_lsp_cmd("sqls"),
        },

        -- GraphQL
        graphql = {
          cmd = get_lsp_cmd("graphql-lsp"),
        },

        -- Protocol Buffers
        buf_ls = {
          cmd = get_lsp_cmd("buf-language-server"),
        },
      }

      -- Track disabled servers
      local disabled_servers = {}

      -- Set up each server
      for server_name, server_config in pairs(servers) do
        if server_config.cmd then
          -- Check if cmd is a function and call it
          if type(server_config.cmd) == "function" then
            local cmd_result = server_config.cmd()
            if not cmd_result then
              -- Skip this server if command not found
              table.insert(disabled_servers, server_name)
              goto continue
            else
              server_config.cmd = cmd_result
            end
          elseif type(server_config.cmd) == "table" then
            -- Check if the table is empty or has nil first element
            if #server_config.cmd == 0 or server_config.cmd[1] == nil then
              -- Skip if cmd array is empty or has nil
              table.insert(disabled_servers, server_name)
              goto continue
            end
          end
        else
          -- No cmd specified, skip this server
          table.insert(disabled_servers, server_name)
          goto continue
        end

        -- Set up the server (with safety check)
        if lspconfig[server_name] then
          lspconfig[server_name].setup(server_config)
        else
          vim.notify("LSP server '" .. server_name .. "' not found in lspconfig", vim.log.levels.WARN)
        end

        ::continue::
      end

      -- Show a single summary notification if servers were disabled
      if #disabled_servers > 0 then
        vim.defer_fn(function()
          vim.notify(
            string.format("Some LSPs not available: %s", table.concat(disabled_servers, ", ")),
            vim.log.levels.INFO,
            { title = "Nix LSP Status" }
          )
        end, 100)
      end

      -- LSP Keymaps (set on LspAttach)
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lsp_attach_keymaps", { clear = true }),
        callback = function(event)
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = desc })
          end

          -- Diagnostic navigation
          map("n", "]d", vim.diagnostic.goto_next, "Next Diagnostic")
          map("n", "[d", vim.diagnostic.goto_prev, "Previous Diagnostic")
          map("n", "]e", function()
            vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR })
          end, "Next Error")
          map("n", "[e", function()
            vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR })
          end, "Previous Error")
          map("n", "]w", function()
            vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.WARN })
          end, "Next Warning")
          map("n", "[w", function()
            vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.WARN })
          end, "Previous Warning")

          -- Diagnostic actions
          map("n", "<leader>cd", "<cmd>FzfLua diagnostics_document<cr>", "Buffer Diagnostics")
          map("n", "<leader>cD", "<cmd>FzfLua diagnostics_workspace<cr>", "Workspace Diagnostics")

          -- Code lens actions
          map("n", "<leader>cl", function()
            pcall(vim.lsp.codelens.run)
          end, "Run Code Lens")
          map("n", "<leader>cL", function()
            pcall(vim.lsp.codelens.refresh)
          end, "Refresh Code Lens")

          -- Hover documentation (integrated with nvim-ufo in lsp-enhancements.lua)
          map("n", "K", vim.lsp.buf.hover, "Hover Documentation")

          -- Signature help
          map({ "n", "i" }, "<C-k>", vim.lsp.buf.signature_help, "Signature Help")

          -- Go to definition/references
          map("n", "gd", "<cmd>FzfLua lsp_definitions<cr>", "Go to Definition")
          map("n", "gr", "<cmd>FzfLua lsp_references<cr>", "Go to References")
          map("n", "gI", "<cmd>FzfLua lsp_implementations<cr>", "Go to Implementation")
          map("n", "gy", "<cmd>FzfLua lsp_typedefs<cr>", "Go to Type Definition")

          -- Code actions
          map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
          map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")

          -- Symbols
          map("n", "<leader>ss", "<cmd>FzfLua lsp_document_symbols<cr>", "Document Symbols")
          map("n", "<leader>sS", "<cmd>FzfLua lsp_workspace_symbols<cr>", "Workspace Symbols")
        end,
      })
    end,
  },
}

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
      -- vim.notify("Using Nix-provided " .. nix_cmd, vim.log.levels.DEBUG)
      return { nix_cmd }
    end
  end

  -- Check system-wide Nix installation
  if command_exists(nix_cmd) then
    -- vim.notify("Using system Nix " .. nix_cmd, vim.log.levels.DEBUG)
    return { nix_cmd }
  end

  -- LSP not found - return nil to prevent starting
  -- vim.notify("LSP " .. nix_cmd .. " not available from Nix", vim.log.levels.DEBUG)
  return nil
end

-- CRD apiVersion groups that use datreeio/CRDs-catalog for schemas
local CRD_GROUPS = {
  ["argoproj.io"] = true,           -- Argo CD, Workflows, Rollouts
  ["cert-manager.io"] = true,       -- Cert-Manager
  ["monitoring.coreos.com"] = true, -- Prometheus Operator
  ["networking.istio.io"] = true,   -- Istio networking
  ["security.istio.io"] = true,     -- Istio security
  ["telemetry.istio.io"] = true,    -- Istio telemetry
}

-- Get Kubernetes schema URL based on kind + apiVersion
-- Routes to yannh/kubernetes-json-schema for core K8s resources
-- Routes to datreeio/CRDs-catalog for CRDs (Argo, Cert-Manager, Prometheus, Istio)
local function get_k8s_schema_url(kind, api_version)
  local kind_lower = kind:lower()
  local group, version = api_version:match("([%w%.%-]+)/(%w+)")

  if not group then
    -- Core API (v1) - use yannh
    version = api_version
    return string.format(
      "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.31.0-standalone-strict/%s-%s.json",
      kind_lower, version
    )
  end

  -- Check if it's a CRD - route to datreeio/CRDs-catalog
  if CRD_GROUPS[group] then
    -- datreeio format: {group}/{kind}_{version}.json
    return string.format(
      "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/%s/%s_%s.json",
      group, kind_lower, version
    )
  end

  -- Standard K8s resource with group (apps, batch, networking.k8s.io, etc.)
  -- Remove ".k8s.io" suffix and convert dots to dashes for yannh format
  local group_clean = group:gsub("%.k8s%.io$", ""):gsub("%.", "-")
  return string.format(
    "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.31.0-standalone-strict/%s-%s-%s.json",
    kind_lower, group_clean, version
  )
end

return {
  -- nvim-lspconfig: Official LSP configuration plugin
  {
    "neovim/nvim-lspconfig",
    lazy = false, -- Load immediately to ensure LSP works when opening files via fzf
    dependencies = {
      -- Optional: nvim-cmp for completion (if you add it later)
      -- Optional: which-key for LSP keymap help
    },
    config = function()
      -- NOTE: Neovim 0.11+ uses vim.lsp.config instead of require('lspconfig')
      -- See :help lspconfig-nvim-0.11 for migration details

      -- Enhanced diagnostics configuration
      vim.diagnostic.config({
        underline = true,
        update_in_insert = false,
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
          -- Show all diagnostic severities (ERROR, WARN, INFO, HINT)
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

      -- Get blink.cmp LSP capabilities
      local capabilities = vim.lsp.protocol.make_client_capabilities()

      -- Merge blink.cmp capabilities if available
      local has_blink, blink_cmp = pcall(require, 'blink.cmp')
      if has_blink then
        capabilities = blink_cmp.get_lsp_capabilities(capabilities)
      end

      -- LSP server configurations
      local servers = {
        -- Go
        gopls = {
          cmd = get_lsp_cmd("gopls"),
          capabilities = capabilities,
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
          capabilities = capabilities,
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
          capabilities = capabilities,
          settings = {
            basedpyright = {
              analysis = {
                -- Enable code lens for Python
                enableCodeLens = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                -- Enable inlay hints for type information
                inlayHints = {
                  variableTypes = true,
                  functionReturnTypes = true,
                },
              },
            },
          },
        },

        -- Python linting (ruff)
        ruff = {
          cmd = get_lsp_cmd("ruff-lsp"),
          capabilities = capabilities,
        },

        -- TypeScript/JavaScript
        ts_ls = {
          cmd = get_lsp_cmd("typescript-language-server"),
          capabilities = capabilities,
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
          capabilities = capabilities,
        },

        -- Ansible support removed (ansible-language-server unmaintained/removed from nixpkgs)
        -- Use ansible-lint for validation instead

        -- Docker
        dockerls = {
          cmd = function()
            local cmd = get_lsp_cmd("docker-langserver")
            return cmd and { cmd[1], "--stdio" } or nil
          end,
          capabilities = capabilities,
        },

        docker_compose_language_service = {
          cmd = function()
            local cmd = get_lsp_cmd("docker-compose-langserver")
            return cmd and { cmd[1], "--stdio" } or nil
          end,
          capabilities = capabilities,
        },

        -- Helm
        helm_ls = {
          cmd = get_lsp_cmd("helm_ls"),
          capabilities = capabilities,
        },

        -- YAML with Kubernetes schema support
        yamlls = {
          cmd = function()
            local cmd = get_lsp_cmd("yaml-language-server")
            return cmd and { cmd[1], "--stdio" } or nil
          end,
          capabilities = capabilities,
          settings = {
            redhat = { telemetry = { enabled = false } },
            yaml = {
              validate = true,
              completion = true,
              hover = true,
              format = { enable = true },
              schemas = {
                -- Kubernetes: Uses resource-specific schemas via auto-modelines
                -- (see autocmd below that detects kind/apiVersion)
                -- GitHub Actions
                ["https://json.schemastore.org/github-workflow.json"] = ".github/workflows/*",
                -- Docker Compose
                ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = {
                  "docker-compose*.yml",
                  "docker-compose*.yaml",
                  "compose*.yml",
                  "compose*.yaml",
                },
                -- Ansible
                ["https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json"] = "ansible/**/*.yml",
              },
            },
          },
        },

        -- JSON
        jsonls = {
          cmd = function()
            local cmd = get_lsp_cmd("vscode-json-language-server")
            return cmd and { cmd[1], "--stdio" } or nil
          end,
          capabilities = capabilities,
        },

        -- Lua
        lua_ls = {
          cmd = get_lsp_cmd("lua-language-server"),
          capabilities = capabilities,
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
          capabilities = capabilities,
        },

        -- Bash
        bashls = {
          cmd = get_lsp_cmd("bash-language-server"),
          capabilities = capabilities,
        },

        -- TOML
        taplo = {
          cmd = function()
            local cmd = get_lsp_cmd("taplo")
            return cmd and { cmd[1], "lsp", "stdio" } or nil
          end,
          capabilities = capabilities,
        },

        -- Nix
        nil_ls = {
          cmd = get_lsp_cmd("nil"),
          capabilities = capabilities,
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
          capabilities = capabilities,
        },

        -- GraphQL
        graphql = {
          cmd = get_lsp_cmd("graphql-lsp"),
          capabilities = capabilities,
        },

        -- Protocol Buffers
        buf_ls = {
          cmd = get_lsp_cmd("buf-language-server"),
          capabilities = capabilities,
        },
      }

      -- Track disabled servers and enabled servers
      local disabled_servers = {}
      local enabled_servers = {}

      -- Set up each server using Neovim 0.11+ vim.lsp.config API
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

        -- Set up the server using new vim.lsp.config API (Neovim 0.11+)
        local ok, err = pcall(function()
          vim.lsp.config[server_name] = server_config
        end)
        if not ok then
          vim.notify("Failed to setup LSP '" .. server_name .. "': " .. tostring(err), vim.log.levels.WARN)
        else
          -- Track successfully configured server
          table.insert(enabled_servers, server_name)
        end

        ::continue::
      end

      -- CRITICAL: Enable all configured servers (Neovim 0.11+ requirement)
      if #enabled_servers > 0 then
        vim.lsp.enable(enabled_servers)
      end

      -- Explicitly disable conflicting LSP servers from lspconfig defaults
      -- terraform_lsp conflicts with terraformls (HashiCorp's official terraform-ls)
      vim.lsp.enable("terraform_lsp", false)

      -- Global LSP toggle state
      _G.lsp_enabled = true
      _G.enabled_lsp_servers = enabled_servers  -- Store the list of Nix-provided servers

      -- Toggle all LSPs on/off
      _G.toggle_all_lsp = function()
        if _G.lsp_enabled then
          -- Disable all LSPs
          vim.lsp.enable(_G.enabled_lsp_servers, false)
          _G.lsp_enabled = false
          vim.notify("All LSPs disabled", vim.log.levels.INFO)
        else
          -- Re-enable all LSPs
          vim.lsp.enable(_G.enabled_lsp_servers, true)
          _G.lsp_enabled = true
          vim.notify("All LSPs enabled", vim.log.levels.INFO)
        end
      end

      -- Toggle specific LSP
      _G.toggle_lsp = function(server_name)
        local clients = vim.lsp.get_clients({ name = server_name })
        if #clients > 0 then
          vim.lsp.enable(server_name, false)
          vim.notify(string.format("LSP '%s' disabled", server_name), vim.log.levels.INFO)
        else
          vim.lsp.enable(server_name, true)
          vim.notify(string.format("LSP '%s' enabled", server_name), vim.log.levels.INFO)
        end
      end

      -- Show LSP status
      _G.lsp_status = function()
        local clients = vim.lsp.get_clients()
        if #clients == 0 then
          vim.notify("No active LSP clients", vim.log.levels.INFO)
          return
        end

        local status = {}
        for _, client in ipairs(clients) do
          table.insert(status, string.format("%s (id: %d)", client.name, client.id))
        end

        vim.notify(
          string.format("Active LSPs (%d):\n%s", #clients, table.concat(status, "\n")),
          vim.log.levels.INFO,
          { title = "LSP Status" }
        )

        -- Also show available Nix LSPs
        if #_G.enabled_lsp_servers > 0 then
          vim.notify(
            string.format("Available Nix LSPs: %s", table.concat(_G.enabled_lsp_servers, ", ")),
            vim.log.levels.INFO,
            { title = "Nix LSPs" }
          )
        end
      end

      -- Show summary of disabled servers at DEBUG level (reduce noise)
      -- Commented out to reduce message noise
      -- if #disabled_servers > 0 then
      --   vim.notify(
      --     string.format("LSPs not available from Nix: %s", table.concat(disabled_servers, ", ")),
      --     vim.log.levels.DEBUG,
      --     { title = "Nix LSP Status" }
      --   )
      -- end

      -- Auto-insert yaml-language-server modeline with resource-specific K8s/CRD schema
      -- Detects kind: and apiVersion: to route to correct schema source:
      -- - Core K8s (v1, apps, batch, etc.) → yannh/kubernetes-json-schema
      -- - CRDs (Argo, Cert-Manager, Prometheus, Istio) → datreeio/CRDs-catalog
      vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "TextChanged" }, {
        group = vim.api.nvim_create_augroup("yaml_k8s_modeline", { clear = true }),
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()

          -- Check if buffer is YAML (by filetype or by checking content)
          local ft = vim.bo[bufnr].filetype
          if ft ~= "yaml" and ft ~= "" then
            return
          end

          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 30, false)
          local content = table.concat(lines, "\n")

          -- Skip if already has modeline
          if content:match("yaml%-language%-server:") then
            return
          end

          -- Extract apiVersion and kind from content
          local api_version = content:match("apiVersion:%s*([%w%.%/]+)")
          local kind = content:match("kind:%s*(%w+)")

          -- Both apiVersion and kind are required for K8s resources
          if not api_version or not kind then
            return
          end

          -- Get schema URL (routes to yannh for core K8s, datreeio for CRDs)
          local schema_url = get_k8s_schema_url(kind, api_version)
          if not schema_url then
            return
          end

          vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, {
            "# yaml-language-server: $schema=" .. schema_url
          })

          -- Set filetype to yaml if not already set (for scratch buffers)
          if ft == "" then
            vim.bo[bufnr].filetype = "yaml"
          end

          -- Restart yamlls to pick up the modeline
          vim.defer_fn(function()
            vim.cmd("LspRestart yamlls")
          end, 100)
        end,
      })

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

          -- LSP Toggle controls
          map("n", "<leader>cT", function() _G.toggle_all_lsp() end, "Toggle ALL LSPs")
          map("n", "<leader>ct", function()
            local buf_clients = vim.lsp.get_clients({ bufnr = event.buf })
            if #buf_clients > 0 then
              _G.toggle_lsp(buf_clients[1].name)
            else
              vim.notify("No LSP attached to this buffer", vim.log.levels.WARN)
            end
          end, "Toggle buffer's LSP")
          map("n", "<leader>cs", function() _G.lsp_status() end, "Show LSP status")
        end,
      })
    end,
  },
}

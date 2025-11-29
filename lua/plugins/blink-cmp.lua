-- Blink.cmp - Fast completion engine
-- Minimal setup for nvim-mini

return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "rafamadriz/friendly-snippets",
      "Kaiser-Yang/blink-cmp-git",
    },
    version = "v0.*",
    event = { "InsertEnter", "CmdlineEnter" },
    opts = {
      -- Appearance
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono",
      },

      -- Sources
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "git" },
        providers = {
          git = {
            module = "blink-cmp-git",
            name = "Git",
            enabled = function()
              return vim.tbl_contains({ "gitcommit", "markdown", "octo" }, vim.bo.filetype)
            end,
            opts = {
              git_centers = {
                github = {
                  -- Suppress errors for repos with non-standard SSH remotes (e.g., github.com-alias)
                  issue = { on_error = function() return true end },
                  pull_request = { on_error = function() return true end },
                  mention = { on_error = function() return true end },
                },
              },
            },
          },
        },
      },

      -- Command-line completion
      cmdline = {
        enabled = true,
        completion = {
          list = { selection = { preselect = false } },
          menu = {
            auto_show = function(ctx)
              return vim.fn.getcmdtype() == ":"
            end,
          },
          ghost_text = { enabled = true },
        },
      },

      -- Completion behavior
      completion = {
        accept = {
          auto_brackets = {
            enabled = true,
          },
        },
        menu = {
          border = "rounded",
          draw = {
            columns = {
              { "kind_icon", "label", "label_description", gap = 1 },
              { "kind", "source_name", gap = 1 }
            },
            components = {
              -- Enhanced label_description with LSP detail fallback
              label_description = {
                width = { max = 50 },
                text = function(ctx)
                  -- Show label_description if available (for imports)
                  if ctx.label_description and ctx.label_description ~= '' then
                    return ctx.label_description
                  -- Fall back to LSP detail field (type info, signatures)
                  elseif ctx.item and ctx.item.detail then
                    return ctx.item.detail
                  end
                  return ''
                end,
              },
              -- Add source name with brackets
              source_name = {
                width = { max = 20 },
                text = function(ctx)
                  return "[" .. ctx.source_name .. "]"
                end,
                highlight = "BlinkCmpSource",
              },
            },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
          update_delay_ms = 50,
          treesitter_highlighting = true,
          window = {
            border = "rounded",
            max_width = 80,
            max_height = 20,
            scrollbar = true,
          },
        },
        ghost_text = {
          enabled = false,
        },
      },

      -- Keymap
      keymap = {
        preset = "default", -- C-y to accept, C-n/C-p for navigation
        ["<Tab>"] = { "select_and_accept", "fallback" },
        ["<S-Tab>"] = { "select_prev", "fallback" },
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "hide" },
      },

      -- Signature help
      signature = {
        enabled = true,
      },
    },
  },
}

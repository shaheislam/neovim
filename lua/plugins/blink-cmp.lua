-- Blink.cmp - Fast completion engine
-- Minimal setup for nvim-mini

return {
  {
    "saghen/blink.cmp",
    dependencies = "rafamadriz/friendly-snippets",
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
        default = { "lsp", "path", "snippets", "buffer" },
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
            columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind" } },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
          window = {
            border = "rounded",
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

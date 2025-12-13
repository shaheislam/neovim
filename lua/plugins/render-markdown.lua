-- render-markdown.nvim - In-buffer markdown rendering
-- Renders checkboxes, headers, code blocks, callouts with icons

return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  ft = { "markdown" },
  opts = {
    -- Render modes
    render_modes = { "n", "c" },

    -- Heading configuration
    heading = {
      enabled = true,
      sign = true,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
    },

    -- Code blocks
    code = {
      enabled = true,
      sign = true,
      style = "full",
      language_pad = 1,
      border = "thin",
    },

    -- Checkboxes (Obsidian-style)
    checkbox = {
      enabled = true,
      unchecked = { icon = "󰄱 " },
      checked = { icon = "󰄵 " },
      custom = {
        todo = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
        important = { raw = "[!]", rendered = "󰀦 ", highlight = "DiagnosticWarn" },
      },
    },

    -- Bullet points
    bullet = {
      enabled = true,
      icons = { "●", "○", "◆", "◇" },
    },

    -- Links
    link = {
      enabled = true,
      wiki = { icon = "󰌹 " },
      custom = {
        web = { pattern = "^http", icon = "󰖟 " },
      },
    },

    -- Callouts (Obsidian-style)
    callout = {
      note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
      tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
      important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint" },
      warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
      caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
    },

    -- Tables
    pipe_table = {
      enabled = true,
      style = "full",
    },

    -- Sign column integration
    sign = {
      enabled = true,
      highlight = "RenderMarkdownSign",
    },

    -- Anti-conceal (show original on cursor line)
    anti_conceal = {
      enabled = true,
    },

    -- Win options
    win_options = {
      conceallevel = { rendered = 2 },
      concealcursor = { rendered = "" },
    },
  },

  keys = {
    { "<leader>mt", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle render-markdown" },
  },
}

-- Obsidian.nvim - Knowledge base integration
-- Wiki-links, backlinks, daily notes, templates, vault search
-- Using actively maintained fork: https://github.com/obsidian-nvim/obsidian.nvim

return {
  "obsidian-nvim/obsidian.nvim",
  version = "*",
  lazy = true,
  ft = "markdown",
  event = {
    "BufReadPre " .. vim.fn.expand("~") .. "/obsidian/*.md",
    "BufReadPre " .. vim.fn.expand("~") .. "/obsidian/**/*.md",
    "BufNewFile " .. vim.fn.expand("~") .. "/obsidian/*.md",
    "BufNewFile " .. vim.fn.expand("~") .. "/obsidian/**/*.md",
  },
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    workspaces = {
      {
        name = "vault",
        path = "~/obsidian",
      },
    },

    daily_notes = {
      folder = "Daily",
      date_format = "%Y/%m-%b/%Y-%m-%d-%a",
      template = "daily.md",
    },

    templates = {
      folder = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
    },

    picker = {
      name = "fzf-lua",
    },

    completion = {
      blink = true,
      min_chars = 2,
    },

    ui = {
      enable = false, -- Use render-markdown.nvim instead
    },

    attachments = {
      img_folder = "assets/imgs",
    },

    preferred_link_style = "wiki",

    mappings = {
      ["gf"] = {
        action = function()
          return require("obsidian").util.gf_passthrough()
        end,
        opts = { noremap = false, expr = true, buffer = true },
      },
      ["<cr>"] = {
        action = function()
          return require("obsidian").util.smart_action()
        end,
        opts = { buffer = true, expr = true },
      },
    },
  },

  keys = {
    -- Daily notes
    { "<leader>od", "<cmd>ObsidianToday<cr>", desc = "Today's note" },
    { "<leader>oy", "<cmd>ObsidianYesterday<cr>", desc = "Yesterday's note" },
    { "<leader>om", "<cmd>ObsidianTomorrow<cr>", desc = "Tomorrow's note" },

    -- Navigation
    { "<leader>oo", "<cmd>ObsidianQuickSwitch<cr>", desc = "Quick switch" },
    { "<leader>os", "<cmd>ObsidianSearch<cr>", desc = "Search vault" },
    { "<leader>ob", "<cmd>ObsidianBacklinks<cr>", desc = "Backlinks" },
    { "<leader>ol", "<cmd>ObsidianLinks<cr>", desc = "Outgoing links" },
    { "<leader>ok", "<cmd>ObsidianTags<cr>", desc = "Search tags" },

    -- Creation
    { "<leader>on", "<cmd>ObsidianNew<cr>", desc = "New note" },
    { "<leader>ot", "<cmd>ObsidianTemplate<cr>", desc = "Insert template" },

    -- Tasks
    { "<leader>oc", "<cmd>lua require('obsidian').util.toggle_checkbox()<cr>", desc = "Toggle checkbox" },

    -- Links (visual mode)
    { "<leader>oL", "<cmd>ObsidianLink<cr>", desc = "Create link", mode = "v" },
    { "<leader>oN", "<cmd>ObsidianLinkNew<cr>", desc = "Link to new note", mode = "v" },
  },
}

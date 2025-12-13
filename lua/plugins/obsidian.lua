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

    -- Preserve original title as note ID (don't slugify)
    -- This ensures completion inserts human-readable names that match your existing notes
    note_id_func = function(title)
      if title ~= nil and title ~= "" then
        return title
      end
      return tostring(os.time())
    end,

    -- Custom wiki_link_func: path without .md extension + alias
    -- Outputs: [[DfE/Makefile Pointers|Makefile Pointers]]
    -- Built-in "prepend_note_path" adds .md which causes double-extension issues
    wiki_link_func = function(opts)
      if opts.label ~= opts.path then
        return string.format("[[%s|%s]]", opts.path, opts.label)
      else
        return string.format("[[%s]]", opts.path)
      end
    end,

    legacy_commands = false, -- Use new command format (Obsidian xxx)

    callbacks = {
      enter_note = function(note)
        -- CRITICAL: expr = true required because smart_action RETURNS a command string
        vim.keymap.set("n", "gf", require("obsidian.api").smart_action, {
          buffer = note.bufnr,
          desc = "Follow link",
          expr = true,
        })
        vim.keymap.set("n", "<CR>", require("obsidian.api").smart_action, {
          buffer = note.bufnr,
          desc = "Smart action",
          expr = true,
        })
      end,
    },
  },

  keys = {
    -- Daily notes (new command format)
    { "<leader>od", "<cmd>Obsidian today<cr>", desc = "Today's note" },
    { "<leader>oy", "<cmd>Obsidian yesterday<cr>", desc = "Yesterday's note" },
    { "<leader>om", "<cmd>Obsidian tomorrow<cr>", desc = "Tomorrow's note" },

    -- Navigation
    { "<leader>oo", "<cmd>Obsidian quick_switch<cr>", desc = "Quick switch" },
    { "<leader>os", "<cmd>Obsidian search<cr>", desc = "Search vault" },
    { "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Backlinks" },
    { "<leader>ol", "<cmd>Obsidian links<cr>", desc = "Outgoing links" },
    { "<leader>ok", "<cmd>Obsidian tags<cr>", desc = "Search tags" },

    -- Creation
    { "<leader>on", "<cmd>Obsidian new<cr>", desc = "New note" },
    { "<leader>ot", "<cmd>Obsidian template<cr>", desc = "Insert template" },

    -- Tasks
    { "<leader>oc", "<cmd>Obsidian toggle_checkbox<cr>", desc = "Toggle checkbox" },

    -- Links (visual mode)
    { "<leader>oL", "<cmd>Obsidian link<cr>", desc = "Create link", mode = "v" },
    { "<leader>oN", "<cmd>Obsidian link_new<cr>", desc = "Link to new note", mode = "v" },
  },
}

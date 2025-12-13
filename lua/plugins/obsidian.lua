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
        local bufnr = note.bufnr

        -- CRITICAL: expr = true required because smart_action RETURNS a command string
        vim.keymap.set("n", "gf", require("obsidian.api").smart_action, {
          buffer = bufnr,
          desc = "Follow link",
          expr = true,
        })
        vim.keymap.set("n", "<CR>", require("obsidian.api").smart_action, {
          buffer = bufnr,
          desc = "Smart action",
          expr = true,
        })

        -- Heading navigation (linkarzu workflow)
        vim.keymap.set("n", "gj", function()
          vim.fn.search("^#", "W")
        end, { buffer = bufnr, desc = "Next heading" })

        vim.keymap.set("n", "gk", function()
          vim.fn.search("^#", "bW")
        end, { buffer = bufnr, desc = "Previous heading" })

        -- Heading-level folding (linkarzu workflow)
        -- Setup treesitter folding for this buffer
        vim.opt_local.foldmethod = "expr"
        vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.opt_local.foldenable = true
        vim.opt_local.foldlevel = 99 -- Start with all open

        vim.keymap.set("n", "zk", function()
          vim.opt_local.foldlevel = 1
        end, { buffer = bufnr, desc = "Fold to H2" })

        vim.keymap.set("n", "zl", function()
          vim.opt_local.foldlevel = 2
        end, { buffer = bufnr, desc = "Fold to H3" })

        vim.keymap.set("n", "zu", function()
          vim.cmd("normal! zR")
        end, { buffer = bufnr, desc = "Unfold all" })

        -- Task automation: Complete and move to Completed section (linkarzu workflow)
        vim.keymap.set("n", "<A-x>", function()
          local line = vim.api.nvim_get_current_line()
          local row = vim.api.nvim_win_get_cursor(0)[1]

          -- Toggle checkbox if not already done
          if line:match("%- %[ %]") then
            line = line:gsub("%- %[ %]", "- [x]")
          end

          -- Delete current line
          vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, {})

          -- Find "## Completed" section and append
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          for i, l in ipairs(lines) do
            if l:match("^## Completed") then
              vim.api.nvim_buf_set_lines(bufnr, i, i, false, { line })
              vim.notify("Task moved to Completed section", vim.log.levels.INFO)
              return
            end
          end

          -- If no Completed section, create one at end
          vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "## Completed", line })
          vim.notify("Created Completed section and moved task", vim.log.levels.INFO)
        end, { buffer = bufnr, desc = "Complete and move task" })
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
    {
      "<leader>tt",
      function()
        require("fzf-lua").grep({ search = "- \\[ \\]", cwd = vim.fn.expand("~/obsidian") })
      end,
      desc = "Pending tasks",
    },
    {
      "<leader>tc",
      function()
        require("fzf-lua").grep({ search = "- \\[x\\]", cwd = vim.fn.expand("~/obsidian") })
      end,
      desc = "Completed tasks",
    },

    -- Links (visual mode)
    { "<leader>oL", "<cmd>Obsidian link<cr>", desc = "Create link", mode = "v" },
    { "<leader>oN", "<cmd>Obsidian link_new<cr>", desc = "Link to new note", mode = "v" },
  },
}

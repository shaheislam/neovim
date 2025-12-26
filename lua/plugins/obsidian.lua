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

    -- Semantic search (local embeddings) - Enhanced
    {
      "<leader>or",
      function()
        local current_file = vim.fn.expand("%:p")
        local vault_path = vim.fn.expand("~/obsidian")
        local script_path = vim.fn.expand("~/dotfiles/scripts/smart-connections/vault-search.py")

        if not current_file:match(vault_path) then
          vim.notify("Not in Obsidian vault", vim.log.levels.WARN)
          return
        end

        local rel_path = current_file:gsub(vault_path .. "/", "")
        local cmd = string.format("'%s' '%s' --vault '%s' --top 15 --hybrid", script_path, rel_path, vault_path)
        local results = vim.fn.systemlist(cmd)

        if vim.v.shell_error ~= 0 or #results == 0 then
          vim.notify("No related notes found (run vault-index.py first?)", vim.log.levels.WARN)
          return
        end

        local entries = {}
        for _, line in ipairs(results) do
          local parts = vim.split(line, "\t")
          if #parts >= 3 then
            local path, score, title = parts[1], parts[2], parts[3]
            local preview = parts[4] or ""
            table.insert(entries, string.format("[%s] %s │ %s", score, title, preview:sub(1, 50)))
          end
        end

        require("fzf-lua").fzf_exec(entries, {
          prompt = "Related notes> ",
          actions = {
            ["default"] = function(selected)
              if selected and selected[1] then
                local title_match = selected[1]:match("%] ([^│]+)")
                if title_match then
                  -- Find matching result
                  for _, line in ipairs(results) do
                    local parts = vim.split(line, "\t")
                    if #parts >= 1 then
                      local path = parts[1]:gsub(":%d+$", "") -- Remove line number
                      vim.cmd("edit " .. vault_path .. "/" .. path)
                      return
                    end
                  end
                end
              end
            end,
          },
        })
      end,
      desc = "Related notes (semantic)",
    },
    {
      "<leader>oR",
      function()
        local vault_path = vim.fn.expand("~/obsidian")
        local script_path = vim.fn.expand("~/dotfiles/scripts/smart-connections/vault-search.py")

        vim.ui.input({ prompt = "Semantic search: " }, function(query)
          if not query or query == "" then
            return
          end

          local cmd = string.format("'%s' --query '%s' --vault '%s' --top 15 --hybrid", script_path, query, vault_path)
          local results = vim.fn.systemlist(cmd)

          if vim.v.shell_error ~= 0 or #results == 0 then
            vim.notify("No results found", vim.log.levels.WARN)
            return
          end

          local entries = {}
          local result_map = {}
          for _, line in ipairs(results) do
            local parts = vim.split(line, "\t")
            if #parts >= 3 then
              local path, score, title = parts[1], parts[2], parts[3]
              local preview = parts[4] or ""
              local entry = string.format("[%s] %s │ %s", score, title, preview:sub(1, 50))
              table.insert(entries, entry)
              result_map[entry] = path:gsub(":%d+$", "")
            end
          end

          require("fzf-lua").fzf_exec(entries, {
            prompt = "Results: " .. query .. "> ",
            actions = {
              ["default"] = function(selected)
                if selected and selected[1] and result_map[selected[1]] then
                  vim.cmd("edit " .. vault_path .. "/" .. result_map[selected[1]])
                end
              end,
            },
          })
        end)
      end,
      desc = "Semantic search (query)",
    },
    {
      "<leader>oF",
      function()
        local current_file = vim.fn.expand("%:p")
        local vault_path = vim.fn.expand("~/obsidian")
        local script_path = vim.fn.expand("~/dotfiles/scripts/smart-connections/vault-search.py")

        if not current_file:match(vault_path) then
          vim.notify("Not in Obsidian vault", vim.log.levels.WARN)
          return
        end

        local rel_path = current_file:gsub(vault_path .. "/", "")
        local folder = vim.fn.fnamemodify(rel_path, ":h")
        if folder == "." then folder = "" end

        local cmd = string.format("'%s' '%s' --vault '%s' --folder '%s' --top 15", script_path, rel_path, vault_path, folder)
        local results = vim.fn.systemlist(cmd)

        if vim.v.shell_error ~= 0 or #results == 0 then
          vim.notify("No related notes in folder", vim.log.levels.WARN)
          return
        end

        local entries = {}
        local result_map = {}
        for _, line in ipairs(results) do
          local parts = vim.split(line, "\t")
          if #parts >= 3 then
            local path, score, title = parts[1], parts[2], parts[3]
            local entry = string.format("[%s] %s", score, title)
            table.insert(entries, entry)
            result_map[entry] = path:gsub(":%d+$", "")
          end
        end

        require("fzf-lua").fzf_exec(entries, {
          prompt = "Related in " .. folder .. "> ",
          actions = {
            ["default"] = function(selected)
              if selected and selected[1] and result_map[selected[1]] then
                vim.cmd("edit " .. vault_path .. "/" .. result_map[selected[1]])
              end
            end,
          },
        })
      end,
      desc = "Related notes (same folder)",
    },
    {
      "<leader>oS",
      function()
        local current_file = vim.fn.expand("%:p")
        local vault_path = vim.fn.expand("~/obsidian")
        local script_path = vim.fn.expand("~/dotfiles/scripts/smart-connections/vault-suggest.py")

        if not current_file:match(vault_path) then
          vim.notify("Not in Obsidian vault", vim.log.levels.WARN)
          return
        end

        local rel_path = current_file:gsub(vault_path .. "/", "")
        local cmd = string.format("'%s' '%s' --vault '%s' --format plain", script_path, rel_path, vault_path)
        local output = vim.fn.system(cmd)

        if vim.v.shell_error ~= 0 then
          vim.notify("No link suggestions found", vim.log.levels.WARN)
          return
        end

        -- Show in floating window
        local lines = vim.split(output, "\n")
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

        local width = math.min(80, vim.o.columns - 10)
        local height = math.min(#lines + 2, vim.o.lines - 10)

        vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          width = width,
          height = height,
          row = (vim.o.lines - height) / 2,
          col = (vim.o.columns - width) / 2,
          style = "minimal",
          border = "rounded",
          title = " Link Suggestions ",
          title_pos = "center",
        })

        vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
        vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf })
      end,
      desc = "Suggest backlinks",
    },
    {
      "<leader>oH",
      function()
        local vault_path = vim.fn.expand("~/obsidian")
        local script_path = vim.fn.expand("~/dotfiles/scripts/smart-connections/vault-search.py")

        local cmd = string.format("'%s' --history --vault '%s'", script_path, vault_path)
        local output = vim.fn.system(cmd)

        local lines = vim.split(output, "\n")
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

        local width = math.min(60, vim.o.columns - 10)
        local height = math.min(#lines + 2, vim.o.lines - 10)

        vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          width = width,
          height = height,
          row = (vim.o.lines - height) / 2,
          col = (vim.o.columns - width) / 2,
          style = "minimal",
          border = "rounded",
          title = " Query History ",
          title_pos = "center",
        })

        vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
        vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf })
      end,
      desc = "Search history",
    },

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

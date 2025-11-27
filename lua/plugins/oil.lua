-- Oil.nvim - File Browser
-- Required by fzf-lua config

return {
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    cmd = { "Oil" },
    opts = {
      default_file_explorer = true,
      delete_to_trash = true,
      skip_confirm_for_simple_edits = false,
      view_options = {
        show_hidden = true,
        is_hidden_file = function(name, bufnr)
          return vim.startswith(name, ".")
        end,
      },
      float = {
        padding = 2,
        max_width = 0,
        max_height = 0,
        border = "rounded",
        win_options = {
          winblend = 0,
        },
      },
      keymaps = {
        -- Oil-specific fzf-lua mappings
        ["<leader>ff"] = {
          function()
            require("fzf-lua").files({
              cwd = require("oil").get_current_dir(),
              prompt = "Find Files (Oil Directory)> ",
            })
          end,
          desc = "Find files in Oil directory",
        },
        ["<leader>fg"] = {
          function()
            require("fzf-lua").live_grep({
              cwd = require("oil").get_current_dir(),
              prompt = "Live Grep (Oil Directory)> ",
            })
          end,
          desc = "Live grep in Oil directory",
        },
        -- Path yanking with multiple formats (C-y + l/s/g)
        ["<C-y>l"] = {
          function()
            local oil = require("oil")
            local entry = oil.get_cursor_entry()
            if entry then
              vim.fn.setreg("+", entry.name)
              vim.notify("Copied: " .. entry.name, vim.log.levels.INFO)
            end
          end,
          desc = "Yank filename",
        },
        ["<C-y>s"] = {
          function()
            local oil = require("oil")
            local entry = oil.get_cursor_entry()
            local dir = oil.get_current_dir()
            if entry and dir then
              local full_path = vim.fn.fnamemodify(dir .. entry.name, ":p")
              -- Find git root
              local git_dir = vim.fs.find(".git", { path = dir, upward = true })[1]
              if git_dir then
                local git_root = vim.fn.fnamemodify(git_dir, ":h")
                local rel_path = full_path:sub(#git_root + 2) -- +2 to skip trailing /
                vim.fn.setreg("+", rel_path)
                vim.notify("Copied (git): " .. rel_path, vim.log.levels.INFO)
              else
                vim.fn.setreg("+", full_path)
                vim.notify("No git root, copied: " .. full_path, vim.log.levels.WARN)
              end
            end
          end,
          desc = "Yank path from git root",
        },
        ["<C-y>g"] = {
          function()
            local oil = require("oil")
            local entry = oil.get_cursor_entry()
            local dir = oil.get_current_dir()
            if entry and dir then
              local full_path = vim.fn.fnamemodify(dir .. entry.name, ":p")
              local work_dir = vim.fn.expand("~/work/")
              if full_path:find(work_dir, 1, true) == 1 then
                local rel_path = full_path:sub(#work_dir + 1)
                vim.fn.setreg("+", rel_path)
                vim.notify("Copied (global): " .. rel_path, vim.log.levels.INFO)
              else
                vim.fn.setreg("+", full_path)
                vim.notify("Not in ~/work, copied: " .. full_path, vim.log.levels.WARN)
              end
            end
          end,
          desc = "Yank path from ~/work",
        },
      },
    },
    keys = {
      { "<leader>e", "<cmd>Oil<cr>", desc = "Open File Browser", mode = { "n", "v" } },
      { "<leader>fe", "<cmd>Oil<cr>", desc = "Open File Browser" },
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
    },
    init = function()
      -- Override any existing <leader>e mappings immediately
      vim.keymap.set("n", "<leader>e", "<cmd>Oil<cr>", { desc = "Open File Browser", silent = true })
    end,
    config = function(_, opts)
      require("oil").setup(opts)

      -- Guard flag to prevent recursion between DirChanged and BufEnter
      local changing_dir = false

      -- Auto-sync PWD with Oil directory navigation
      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "oil://*",
        callback = function(event)
          if changing_dir then
            return
          end

          -- Only sync PWD if we're actually entering an Oil buffer
          -- Don't run when opening files FROM Oil
          if vim.bo[event.buf].filetype ~= "oil" then
            return
          end

          local oil_dir = require("oil").get_current_dir()
          if oil_dir then
            -- Only change directory if it's different from current PWD
            local current_dir = vim.fn.getcwd()
            if oil_dir ~= current_dir then
              changing_dir = true
              vim.cmd.cd(oil_dir)
              vim.schedule(function()
                changing_dir = false
              end)
            end
          end
        end,
        desc = "Sync PWD with Oil directory navigation",
      })

      -- Auto-update Oil view when directory changes via :cd
      vim.api.nvim_create_autocmd("DirChanged", {
        pattern = "*",
        callback = function()
          if changing_dir then
            return
          end

          -- Don't interfere if current buffer is not Oil (e.g., opening a file)
          local current_buf = vim.api.nvim_get_current_buf()
          local current_ft = vim.bo[current_buf].filetype

          if current_ft ~= "oil" then
            return
          end

          -- Check if any buffer is an Oil buffer
          for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "oil" then
              -- Update Oil to show the new working directory
              changing_dir = true
              require("oil").open(vim.fn.getcwd())
              vim.schedule(function()
                changing_dir = false
              end)
              break
            end
          end
        end,
        desc = "Update Oil view when directory changes via :cd",
      })
    end,
  },
}

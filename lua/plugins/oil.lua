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

      -- Guard flag to prevent recursion
      local changing_dir = false

      -- Auto-update Oil view when directory changes
      vim.api.nvim_create_autocmd("DirChanged", {
        pattern = "*",
        callback = function()
          if changing_dir then
            return
          end

          for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "oil" then
              changing_dir = true
              require("oil").open(vim.fn.getcwd())
              vim.schedule(function()
                changing_dir = false
              end)
              break
            end
          end
        end,
        desc = "Update Oil view when directory changes",
      })

      -- Auto-update pwd when switching buffers
      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function(args)
          if changing_dir then
            return
          end

          local bufnr = args.buf
          local buftype = vim.bo[bufnr].buftype
          if buftype ~= "" and buftype ~= "acwrite" then
            return
          end

          -- Display buffer first
          local current_win_buf = vim.api.nvim_win_get_buf(0)
          if current_win_buf ~= bufnr then
            local filetype = vim.bo[bufnr].filetype
            if filetype ~= "oil" and vim.bo[bufnr].buftype == "" then
              vim.api.nvim_set_current_buf(bufnr)
            end
          end

          -- Change directory asynchronously
          vim.schedule(function()
            if changing_dir then
              return
            end

            if not vim.api.nvim_buf_is_valid(bufnr) then
              return
            end

            local new_dir = nil

            if vim.bo[bufnr].filetype == "oil" then
              new_dir = require("oil").get_current_dir(bufnr)
            else
              local bufname = vim.api.nvim_buf_get_name(bufnr)
              if bufname ~= "" and vim.fn.filereadable(bufname) == 1 then
                new_dir = vim.fn.fnamemodify(bufname, ":p:h")
              end
            end

            if new_dir and vim.fn.isdirectory(new_dir) == 1 then
              local current_dir = vim.fn.getcwd()
              if new_dir ~= current_dir then
                changing_dir = true
                vim.cmd("cd " .. vim.fn.fnameescape(new_dir))
                vim.schedule(function()
                  changing_dir = false
                end)
              end
            end
          end)
        end,
        desc = "Auto-cd to file directory",
      })
    end,
  },
}

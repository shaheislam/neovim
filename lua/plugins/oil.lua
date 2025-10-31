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

      -- Auto-sync PWD with Oil directory
      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "oil://*",
        callback = function()
          local oil_dir = require("oil").get_current_dir()
          if oil_dir then
            -- Only change directory if it's different from current PWD
            local current_dir = vim.fn.getcwd()
            if oil_dir ~= current_dir then
              vim.cmd.cd(oil_dir)
            end
          end
        end,
        desc = "Sync PWD with Oil directory",
      })
    end,
  },
}

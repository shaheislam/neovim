return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    keys = {
      {
        "<leader>ft",
        function()
          -- Get Oil's current directory if in Oil buffer, otherwise use vim's cwd
          local cwd = vim.fn.getcwd()
          if vim.bo.filetype == "oil" then
            local oil = require("oil")
            local oil_dir = oil.get_current_dir()
            if oil_dir then
              cwd = oil_dir
            end
          end

          -- Create or get a terminal instance with the correct directory
          local Terminal = require("toggleterm.terminal").Terminal
          local term = Terminal:new({
            dir = cwd,
            direction = "horizontal",
            hidden = false,
          })
          term:toggle()
        end,
        desc = "Terminal Split (current dir)",
      },
    },
    opts = {
      size = function(term)
        if term.direction == "horizontal" then
          return math.floor(vim.o.lines * 0.4)
        elseif term.direction == "vertical" then
          return vim.o.columns * 0.4
        end
      end,
      open_mapping = nil, -- Disable default <C-\> to avoid conflicts
      hide_numbers = true,
      shade_terminals = true,
      shading_factor = 2,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      persist_mode = true,
      direction = "horizontal",
      close_on_exit = true,
      shell = vim.o.shell,
      float_opts = {
        border = "rounded",
        winblend = 0,
      },
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)

      -- Set terminal-specific keymaps
      function _G.set_terminal_keymaps()
        local keymap_opts = { buffer = 0 }
        -- <C-q> in terminal mode closes the terminal (buffer-local override)
        vim.keymap.set("t", "<C-q>", [[<C-\><C-n><cmd>close<cr>]], keymap_opts)
        -- <Esc><Esc> exits insert mode without closing
        vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], keymap_opts)
      end

      -- Apply terminal keymaps automatically
      vim.cmd("autocmd! TermOpen term://* lua set_terminal_keymaps()")

      -- Sync Neovim's PWD with ToggleTerm's directory
      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "term://*",
        callback = function(event)
          local buf = event.buf
          -- Only for toggleterm buffers
          if vim.bo[buf].filetype ~= "toggleterm" then
            return
          end

          -- Get the terminal's actual working directory
          local term_dir = vim.fn.getcwd(vim.fn.bufwinid(buf))
          local nvim_pwd = vim.fn.getcwd()

          if term_dir ~= "" and term_dir ~= nvim_pwd then
            vim.cmd.cd(term_dir)
          end
        end,
        desc = "Sync Neovim PWD with ToggleTerm directory",
      })
    end,
  },
}

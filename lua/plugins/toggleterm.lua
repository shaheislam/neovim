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
          require("toggleterm").toggle(1, math.floor(vim.o.lines * 0.4), cwd, "horizontal")
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
        border = "curved",
        winblend = 0,
      },
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)

      -- Toggle terminal between 40% and fullscreen
      function _G.toggle_terminal_size()
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        -- Check if we're in a terminal buffer
        if vim.bo[buf].buftype ~= "terminal" then
          return
        end

        -- Get or initialize the state for this buffer
        local is_fullscreen = vim.b[buf].term_is_fullscreen or false

        if is_fullscreen then
          -- Return to 40% size
          local new_height = math.floor(vim.o.lines * 0.4)
          vim.api.nvim_win_set_height(win, new_height)
          vim.b[buf].term_is_fullscreen = false
        else
          -- Go to fullscreen (95% to account for status line and cmd line)
          local new_height = math.floor(vim.o.lines * 0.95)
          vim.api.nvim_win_set_height(win, new_height)
          vim.b[buf].term_is_fullscreen = true
        end
      end

      -- Set terminal-specific keymaps
      function _G.set_terminal_keymaps()
        local keymap_opts = { buffer = 0 }
        -- <C-d> in terminal mode closes the terminal (buffer-local override)
        vim.keymap.set("t", "<C-d>", [[<C-\><C-n><cmd>close<cr>]], keymap_opts)
        -- <Esc><Esc> exits insert mode without closing
        vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], keymap_opts)
        -- <C-z> toggles between 40% and fullscreen
        vim.keymap.set("t", "<C-z>", [[<C-\><C-n><cmd>lua toggle_terminal_size()<cr>i]], keymap_opts)
        vim.keymap.set("n", "<C-z>", [[<cmd>lua toggle_terminal_size()<cr>]], keymap_opts)
      end

      -- Apply terminal keymaps automatically
      vim.cmd("autocmd! TermOpen term://* lua set_terminal_keymaps()")
    end,
  },
}

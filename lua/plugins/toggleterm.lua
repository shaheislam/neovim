local ft_terminal

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

          -- Reuse the cached terminal so repeated presses toggle the same
          -- instance instead of spawning a new shell each time; only
          -- recreate it if the target directory changed.
          if not ft_terminal or ft_terminal.dir ~= cwd then
            local Terminal = require("toggleterm.terminal").Terminal
            ft_terminal = Terminal:new({
              dir = cwd,
              direction = "horizontal",
              hidden = false,
            })
          end
          ft_terminal:toggle()
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

      -- toggleterm's "is a terminal already open" check (find_open_windows)
      -- ignores direction, so opening a horizontal terminal while the
      -- vertical opencode sidebar is open gets misclassified as "existing"
      -- and placed as a vsplit instead of a full-width horizontal split.
      -- Filter that check by direction so each direction gets its own
      -- placement decision.
      local ui = require("toggleterm.ui")
      local term_api = require("toggleterm.terminal")
      local orig_find_open_windows = ui.find_open_windows
      local direction_filter = nil

      ui.find_open_windows = function(comparator)
        if not direction_filter then
          return orig_find_open_windows(comparator)
        end
        return orig_find_open_windows(function(buf)
          local id = vim.b[buf] and vim.b[buf].toggle_number
          local term = id and term_api.get(id, true)
          return term ~= nil and term.direction == direction_filter
        end)
      end

      local orig_open_split = ui.open_split
      ui.open_split = function(size, term)
        direction_filter = term.direction

        -- For a brand-new horizontal terminal (no other horizontal terminal
        -- already open), toggleterm's default "botright split" spans the
        -- whole tabpage, which shrinks sibling vertical splits (e.g.
        -- opencode's persistent sidebar). That resize crashes its
        -- underlying process, so scope the split to the origin window's own
        -- frame instead - this leaves sibling windows' dimensions
        -- completely untouched rather than just discouraging a resize.
        if term.direction == "horizontal" and not (ui.find_open_windows()) then
          local origin = ui.get_origin_window()
          if origin and vim.api.nvim_win_is_valid(origin) then
            vim.api.nvim_set_current_win(origin)
          end
          vim.cmd("belowright split")
          ui.resize_split(term, size)

          local valid_win = term.window and vim.api.nvim_win_is_valid(term.window)
          local window = valid_win and term.window or vim.api.nvim_get_current_win()
          local valid_buf = term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr)
          local bufnr = valid_buf and term.bufnr or vim.api.nvim_create_buf(false, false)
          vim.api.nvim_win_set_buf(window, bufnr)
          term.window, term.bufnr = window, bufnr
          term:__set_options()
          vim.api.nvim_set_current_buf(bufnr)

          direction_filter = nil
          return
        end

        local ok, err = pcall(orig_open_split, size, term)
        direction_filter = nil
        if not ok then
          error(err, 0)
        end
      end

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

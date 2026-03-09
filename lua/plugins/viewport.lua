-- Smart Window Management
-- Modal interface for window resizing and navigation

return {
  {
    "chancez/viewport.nvim",
    keys = {
      { "<C-z>", mode = { "n", "t" }, desc = "Toggle maximize current window" },
      { "<leader>wv", desc = "Viewport Resize Mode" },
      { "<leader>wn", desc = "Viewport Navigate Mode" },
      { "<leader>ws", desc = "Viewport Select Mode" },
    },
    config = function()
      local viewport = require("viewport")

      viewport.setup({
        resize_mode = {
          resize_amount = 2,
          mappings = {
            preset = "relative", -- Position-aware resizing
            -- h = shrink width (smart)
            -- l = grow width (smart)
            -- j = grow height (smart)
            -- k = shrink height (smart)
            -- <Esc> = exit resize mode
          },
        },
        navigate_mode = {
          mappings = {
            preset = "default",
            -- h/j/k/l = focus navigation
            -- H/J/K/L = swap windows
            -- s = select mode
            -- <Esc> = exit navigate mode
          },
        },
      })

      -- Keymaps
      vim.keymap.set('n', '<C-z>', function()
        require('viewport.actions').toggle_maximize()
      end, { desc = "Toggle maximize current window" })

      -- Terminal-mode zoom (works in opencode.nvim and other terminal buffers)
      vim.keymap.set('t', '<C-z>', function()
        local win = vim.api.nvim_get_current_win()
        vim.cmd([[stopinsert]])
        require('viewport.actions').toggle_maximize()
        -- Deferred so startinsert runs after the mapping stack completes
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win)
            and vim.api.nvim_get_current_win() == win
            and vim.bo.buftype == 'terminal' then
            vim.cmd('startinsert')
          end
        end)
      end, { desc = "Toggle maximize current window (terminal mode)" })
      vim.keymap.set('n', '<leader>wv', viewport.start_resize_mode, { desc = "Viewport Resize Mode" })
      vim.keymap.set('n', '<leader>wn', viewport.start_navigate_mode, { desc = "Viewport Navigate Mode" })
      vim.keymap.set('n', '<leader>ws', viewport.start_select_mode, { desc = "Viewport Select Mode" })
    end,
  },
}

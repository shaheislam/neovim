-- Smart Window Management
-- Modal interface for window resizing and navigation

return {
  {
    "chancez/viewport.nvim",
    lazy = false,
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
      vim.keymap.set('n', '<leader>wv', viewport.start_resize_mode, { desc = "Viewport Resize Mode" })
      vim.keymap.set('n', '<leader>wn', viewport.start_navigate_mode, { desc = "Viewport Navigate Mode" })
      vim.keymap.set('n', '<leader>ws', viewport.start_select_mode, { desc = "Viewport Select Mode" })
    end,
  },
}

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

      local function toggle_zoom()
        local ok, mini_misc = pcall(require, "mini.misc")
        if ok and mini_misc.zoom then
          mini_misc.zoom(nil, { border = "none" })
          return
        end

        require("viewport.actions").toggle_maximize()
      end

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
        toggle_zoom()
      end, { desc = "Toggle maximize current window" })

      -- Terminal-mode zoom (works in opencode.nvim and other terminal buffers)
      vim.keymap.set('t', '<C-z>', function()
        -- Track the terminal buffer, not the window: zooming in opens a new
        -- floating window over it, and zooming out closes that window, so a
        -- window-validity check always fails on zoom-out and strands the
        -- cursor in Normal mode.
        local buf = vim.api.nvim_get_current_buf()
        vim.cmd([[stopinsert]])
        toggle_zoom()
        -- Deferred so startinsert runs after the mapping stack completes
        vim.schedule(function()
          if
            vim.api.nvim_buf_is_valid(buf)
            and vim.api.nvim_get_current_buf() == buf
            and vim.bo.buftype == 'terminal'
          then
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

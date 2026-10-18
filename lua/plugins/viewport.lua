-- Smart Window Management
-- Modal interface for window resizing and navigation

return {
  {
    "chancez/viewport.nvim",
    keys = {
      { "<C-z>", mode = { "n", "t" }, desc = "Toggle window or Diffview zoom" },
      { "<C-g>", mode = "n", desc = "Toggle individual pane zoom" },
      { "<leader>vv", desc = "Viewport Resize Mode" },
      { "<leader>vn", desc = "Viewport Navigate Mode" },
      { "<leader>vs", desc = "Viewport Select Mode" },
    },
    config = function()
      local viewport = require("viewport")

      local function toggle_zoom(pane_only)
        local pane = require("config.window_zoom")
        if not pane_only then
          local restored = pane.restore()
          if require("config.diffview_region").toggle_zoom() or restored then
            return
          end
        end
        if pane.toggle() then
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
      for _, key in ipairs({ '<C-z>', '<C-g>' }) do
        local pane_only = key == '<C-g>'
        local description = pane_only and 'Toggle individual pane zoom' or 'Toggle window or Diffview zoom'
        vim.keymap.set('n', key, function()
          toggle_zoom(pane_only)
        end, { desc = description })

        -- Leave Ctrl-G to terminal applications such as fzf.
        if not pane_only then
          vim.keymap.set('t', key, function()
            -- Track the buffer: zoom-out closes the floating window.
            local buf = vim.api.nvim_get_current_buf()
            vim.cmd([[stopinsert]])
            -- Let Terminal-mode exit before zoom's internal `normal!` runs.
            vim.schedule(function()
              toggle_zoom(pane_only)
              if
                vim.api.nvim_buf_is_valid(buf)
                and vim.api.nvim_get_current_buf() == buf
                and vim.bo.buftype == 'terminal'
              then
                vim.cmd('startinsert')
              end
            end)
          end, { desc = description .. ' (terminal mode)' })
        end
      end
      vim.keymap.set('n', '<leader>vv', viewport.start_resize_mode, { desc = "Viewport Resize Mode" })
      vim.keymap.set('n', '<leader>vn', viewport.start_navigate_mode, { desc = "Viewport Navigate Mode" })
      vim.keymap.set('n', '<leader>vs', viewport.start_select_mode, { desc = "Viewport Select Mode" })
    end,
  },
}

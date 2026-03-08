-- Smart Window Management
-- Modal interface for window resizing and navigation

return {
  {
    "chancez/viewport.nvim",
    lazy = true,
    keys = {
      { "<C-z>", desc = "Toggle maximize current window" },
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

      -- Terminal-mode zoom for opencode.nvim (buffer-local to opencode terminals)
      vim.api.nvim_create_autocmd("TermOpen", {
        callback = function(ev)
          vim.schedule(function()
            local bufname = vim.api.nvim_buf_get_name(ev.buf)
            if bufname:match("opencode") then
              vim.keymap.set('t', '<C-z>', [[<C-\><C-n><cmd>lua require('viewport.actions').toggle_maximize()<cr>]], {
                buffer = ev.buf,
                desc = "Toggle maximize opencode window",
              })
            end
          end)
        end,
      })
      vim.keymap.set('n', '<leader>wv', viewport.start_resize_mode, { desc = "Viewport Resize Mode" })
      vim.keymap.set('n', '<leader>wn', viewport.start_navigate_mode, { desc = "Viewport Navigate Mode" })
      vim.keymap.set('n', '<leader>ws', viewport.start_select_mode, { desc = "Viewport Select Mode" })
    end,
  },
}

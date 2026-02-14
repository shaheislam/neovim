-- Neoscroll - Smooth scrolling animations
-- Provides aesthetic smooth scrolling for better visual experience

return {
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    opts = {
      -- Remove <C-d> and <C-u> from auto-mappings (using custom keys below)
      mappings = { "<C-b>", "zt", "zz", "zb" },
      hide_cursor = true,
      stop_eof = true,
      respect_scrolloff = false,
      cursor_scrolls_alone = true,
    },
    keys = {
      -- Custom mappings with swapped scroll direction
      -- <C-d> scrolls UP (negative scroll value)
      -- Duration reduced from 250ms to 100ms to minimize CursorMoved autocmd triggers
      -- (neoscroll fires CursorMoved per animation frame, each triggering blink.pairs,
      -- LSP highlight clear, lualine refresh, and incline render)
      { "<C-d>", function() require('neoscroll').scroll(-vim.wo.scroll, true, 100) end, desc = "Scroll up (smooth)" },
      -- <C-f> scrolls DOWN (positive scroll value)
      { "<C-f>", function() require('neoscroll').scroll(vim.wo.scroll, true, 100) end, desc = "Scroll down (smooth)" },
    },
  },
}

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
      { "<C-d>", function() require('neoscroll').scroll(-vim.wo.scroll, true, 250) end, desc = "Scroll up (smooth)" },
      -- <C-f> scrolls DOWN (positive scroll value)
      { "<C-f>", function() require('neoscroll').scroll(vim.wo.scroll, true, 250) end, desc = "Scroll down (smooth)" },
    },
  },
}

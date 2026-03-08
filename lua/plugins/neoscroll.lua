-- Neoscroll - Smooth scrolling animations
-- Only used for zt/zz/zb/C-b where single-fire animation looks nice.
-- C-d/C-f use native scrolling (see config/keymaps.lua) because neoscroll
-- fires CursorMoved per animation frame (~6 per scroll). At macOS KeyRepeat=1
-- (~15 keys/sec held), that's ~90 CursorMoved/sec triggering blink.pairs,
-- incline, LSP clear_references, etc. Native scrolling fires ONE CursorMoved
-- per keypress, eliminating the cascade.

return {
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    opts = {
      mappings = { "<C-b>", "zt", "zz", "zb" },
      hide_cursor = true,
      stop_eof = true,
      respect_scrolloff = false,
      cursor_scrolls_alone = true,
    },
  },
}

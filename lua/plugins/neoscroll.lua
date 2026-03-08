-- Neoscroll - Smooth scrolling animations
-- Only used for zt/zz/zb (viewport positioning) where single-fire animation
-- is appropriate and keys are never held down for rapid repeat.
--
-- All paging keys (C-d, C-f, C-b, C-u) use native scrolling instead because
-- neoscroll fires CursorMoved per animation frame (~6 per scroll). At macOS
-- KeyRepeat=1 (~15 keys/sec held), that produces ~90 CursorMoved/sec triggering
-- blink.pairs, incline, LSP clear_references, etc. Native scrolling fires ONE
-- CursorMoved per keypress, reducing per-scroll plugin overhead significantly.

return {
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    opts = {
      mappings = { "zt", "zz", "zb" },
      hide_cursor = true,
      stop_eof = true,
      respect_scrolloff = false,
      cursor_scrolls_alone = true,
    },
  },
}

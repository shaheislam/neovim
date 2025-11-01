-- Multi-cursor editing plugin
-- Enables simultaneous editing at multiple cursor positions with native Vim behavior
return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")

      mc.setup()

      local set = vim.keymap.set

      -- Add/skip cursors vertically with up/down arrows
      set({ "n", "v" }, "<up>", function()
        mc.lineAddCursor(-1)
      end, { desc = "Add cursor above" })
      set({ "n", "v" }, "<down>", function()
        mc.lineAddCursor(1)
      end, { desc = "Add cursor below" })
      set({ "n", "v" }, "<leader><up>", function()
        mc.lineSkipCursor(-1)
      end, { desc = "Skip line above" })
      set({ "n", "v" }, "<leader><down>", function()
        mc.lineSkipCursor(1)
      end, { desc = "Skip line below" })

      -- Match new cursor by word/selection
      set({ "n", "v" }, "<leader>n", function()
        mc.matchAddCursor(1)
      end, { desc = "Add cursor to next match" })
      set({ "n", "v" }, "<leader>N", function()
        mc.matchAddCursor(-1)
      end, { desc = "Add cursor to prev match" })

      -- Skip matches (using 'j' for "jump over" to avoid conflicts)
      set({ "n", "v" }, "<leader>j", function()
        mc.matchSkipCursor(1)
      end, { desc = "Skip next match" })
      set({ "n", "v" }, "<leader>J", function()
        mc.matchSkipCursor(-1)
      end, { desc = "Skip prev match" })

      -- Add all matches in the buffer
      set({ "n", "v" }, "<leader>A", mc.matchAllAddCursors, { desc = "Add cursors to all matches" })

      -- Rotate through cursors
      set({ "n", "v" }, "<left>", mc.nextCursor, { desc = "Next cursor" })
      set({ "n", "v" }, "<right>", mc.prevCursor, { desc = "Previous cursor" })

      -- Delete current cursor
      set({ "n", "v" }, "<leader>x", mc.deleteCursor, { desc = "Delete cursor" })

      -- Toggle cursors on/off
      set("n", "<c-q>", function()
        if mc.cursorsEnabled() then
          mc.disableCursors()
        else
          mc.addCursor()
        end
      end, { desc = "Toggle cursors" })

      -- Align cursor columns
      set("n", "<leader>a", mc.alignCursors, { desc = "Align cursors" })

      -- Split visual selections by regex
      set("v", "S", mc.splitCursors, { desc = "Split cursors by regex" })

      -- Append/insert for visual selections
      set("n", "I", mc.insertVisual, { desc = "Insert at visual selections" })
      set("n", "A", mc.appendVisual, { desc = "Append at visual selections" })

      -- Enhanced escape: clear cursors or default behavior
      set({ "n", "v" }, "<esc>", function()
        if not mc.cursorsEnabled() then
          mc.enableCursors()
        elseif mc.hasCursors() then
          mc.clearCursors()
        else
          -- Default escape behavior (clear search highlight)
          vim.cmd("nohlsearch")
        end
      end, { desc = "Clear cursors or search highlight" })

      -- Customize cursor appearance to match theme
      vim.api.nvim_set_hl(0, "MultiCursorCursor", { link = "Cursor" })
      vim.api.nvim_set_hl(0, "MultiCursorVisual", { link = "Visual" })
      vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { link = "Visual" })
      vim.api.nvim_set_hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
    end,
  },
}

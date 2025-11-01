-- marks.nvim - Visual marks in sign column with enhanced navigation
-- Complements fzf-lua's marks picker by adding visual indicators and quick navigation
return {
  "chentoast/marks.nvim",
  event = "VeryLazy",
  opts = {
    -- Enable default mappings (m prefix for mark operations)
    default_mappings = true,

    -- Show important built-in marks in sign column
    builtin_marks = { ".", "<", ">", "^" },

    -- Enable cycling through marks with m] and m[
    cyclic = true,

    -- Don't force write shada on every mark operation
    force_write_shada = false,

    -- Refresh interval for mark display
    refresh_interval = 250,

    -- Sign column priority settings
    sign_priority = {
      lower = 10,
      upper = 15,
      builtin = 8,
      bookmark = 20
    },

    -- Exclude certain buffer types from showing marks
    excluded_filetypes = {
      "oil",         -- Oil file browser
      "noice",       -- Noice UI buffers
      "toggleterm",  -- Terminal buffers
      "lazy",        -- Lazy.nvim UI
      "mason",       -- Mason UI
      "help",        -- Help buffers
      "qf",          -- Quickfix
      "prompt",      -- Prompt buffers
      "TelescopePrompt",
      "TelescopeResults",
    },

    -- Exclude certain buffer types
    excluded_buftypes = {
      "terminal",
      "nofile",
    },

    -- Bookmark configuration (numbered marks 0-9)
    bookmark_0 = {
      sign = "⚑",
      virt_text = "bookmark",
      -- Don't prompt for annotation by default (can still add with mx<cr>)
      annotate = false,
    },

    -- Additional mappings configuration
    mappings = {
      -- These are in addition to default mappings:
      -- mx        Set mark x
      -- m,        Set next available mark
      -- m;        Toggle mark at current line
      -- dmx       Delete mark x
      -- dm<space> Delete all marks in buffer
      -- dm-       Delete all marks on current line
      -- m]        Jump to next mark
      -- m[        Jump to previous mark
      -- m:        Preview marks in floating window
      -- m<0-9>    Set bookmark
    }
  },

  config = function(_, opts)
    require("marks").setup(opts)

    -- Optional: Add which-key descriptions for marks.nvim mappings
    local ok, which_key = pcall(require, "which-key")
    if ok then
      which_key.add({
        { "m", group = "marks" },
        { "m,", desc = "Set next available mark" },
        { "m;", desc = "Toggle mark at current line" },
        { "m]", desc = "Next mark" },
        { "m[", desc = "Previous mark" },
        { "m:", desc = "Preview marks" },
        { "m<space>", desc = "Delete all marks in buffer" },
        { "dm", group = "delete marks" },
        { "dm<space>", desc = "Delete all marks in buffer" },
        { "dm-", desc = "Delete marks on line" },
      })
    end
  end,
}
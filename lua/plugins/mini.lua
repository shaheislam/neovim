-- mini.nvim - Collection of independent modules
-- Selective inclusion of essential modules for minimal setup

return {
  {
    "echasnovski/mini.nvim",
    version = false, -- use main branch for latest features
    event = "VeryLazy",
    config = function()
      -- ===== Text Editing Modules =====

      -- mini.ai: Enhanced text objects (around/inside functions, classes, etc.)
      -- Treesitter-textobjects plugin owns: f (function), c (class), a (parameter)
      -- mini.ai keeps: t (tag), q (quote), b (brackets), o (operator), etc.
      require("mini.ai").setup({
        n_lines = 500,
        search_method = "cover_or_next",
        custom_textobjects = {
          -- Disabled: nvim-treesitter-textobjects provides AST-based versions
          f = '',  -- @function.outer/inner (treesitter)
          c = '',  -- @class.outer/inner (treesitter)
          a = '',  -- @parameter.outer/inner (treesitter)
        },
      })

      -- mini.surround: Surround operations
      -- sa{motion}{char} - Add surrounding
      -- sd{char} - Delete surrounding
      -- sr{old}{new} - Replace surrounding
      -- sf/sF - Find surrounding right/left
      -- sh - Highlight surrounding
      require("mini.surround").setup({
        mappings = {
          add = "sa", -- Add surrounding in Normal and Visual modes
          delete = "sd", -- Delete surrounding
          find = "sf", -- Find surrounding (to the right)
          find_left = "sF", -- Find surrounding (to the left)
          highlight = "sh", -- Highlight surrounding
          replace = "sr", -- Replace surrounding
          update_n_lines = "sn", -- Update `n_lines`
        },
      })

      -- mini.comment: Smart commenting
      -- gc{motion} - Toggle comment
      -- gcc - Toggle current line
      -- Respects treesitter for proper commenting
      require("mini.comment").setup({
        options = {
          ignore_blank_line = false,
          custom_commentstring = nil,
        },
        mappings = {
          comment = "gc",
          comment_line = "gcc",
          comment_visual = "gc",
          textobject = "gc",
        },
      })


      -- ===== Navigation Modules =====

      -- mini.bracketed: Square bracket navigation
      -- Treesitter-textobjects replaces: ]f (function), ]c (class), ]b (block), ]l (loop)
      -- Remaining: ]d (diagnostic), ]i (indent), ]j (jump), ]o (oldfile),
      --            ]q (quickfix), ]t (tag), ]u (undo), ]w (window), ]y (yank)
      require("mini.bracketed").setup({
        buffer  = { suffix = '' }, -- disabled: ]b/[b → treesitter block nav
        comment = { suffix = '' }, -- disabled: ]c/[c → treesitter class nav (gitsigns ]c for hunks)
        file    = { suffix = '' }, -- disabled: ]f/[f → treesitter function nav
        location = { suffix = '' }, -- disabled: ]l/[l → treesitter loop nav
      })

      -- mini.move: Move selections and lines
      -- Alt+h/j/k/l in visual mode to move selection
      -- Alt+h/j/k/l in normal mode to move current line
      require("mini.move").setup({
        mappings = {
          -- Move visual selection
          left = "<M-h>",
          right = "<M-l>",
          down = "<M-j>",
          up = "<M-k>",
          -- Move current line
          line_left = "<M-h>",
          line_right = "<M-l>",
          line_down = "<M-j>",
          line_up = "<M-k>",
        },
      })

      -- ===== UI Enhancements =====

      -- mini.cursorword: Auto-highlight word under cursor
      require("mini.cursorword").setup({
        delay = 100,
      })

      -- mini.trailspace: Highlight and remove trailing whitespace
      require("mini.trailspace").setup()

      -- ===== Utility Modules =====

      -- mini.bufremove: Better buffer deletion
      -- Preserves window layout when deleting buffers
      require("mini.bufremove").setup()

      -- mini.misc: Miscellaneous utilities
      -- Provides useful functions like put_text, zoom, etc.
      require("mini.misc").setup()

      -- mini.splitjoin: Split/join arguments
      -- gS - Toggle split/join for arguments, array elements, etc.
      require("mini.splitjoin").setup({
        mappings = {
          toggle = "gS",
        },
      })
    end,

    keys = {
      -- mini.bufremove keybindings
      { "<leader>bd", function() require("mini.bufremove").delete(0, false) end, desc = "Delete Buffer" },
      {
        "<leader>bD",
        function() require("mini.bufremove").delete(0, true) end,
        desc = "Delete Buffer (Force)",
      },

      -- mini.trailspace keybindings
      { "<leader>tw", function() require("mini.trailspace").trim() end, desc = "Trim Trailing Whitespace" },
      {
        "<leader>tl",
        function() require("mini.trailspace").trim_last_lines() end,
        desc = "Trim Last Empty Lines",
      },
    },
  },
}

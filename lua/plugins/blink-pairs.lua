-- blink.pairs - Rainbow highlighting and intelligent auto-pairs
-- Rust-based plugin for performance with indent-aware matching

return {
  {
    'saghen/blink.pairs',
    dependencies = 'saghen/blink.lib',
    version = '*',

    --- @module 'blink.pairs'
    --- @type blink.pairs.Config
    config = function(_, opts)
      local pairs = require('blink.pairs')
      pairs.setup(opts)
      -- Disable built-in matchparen after runtime plugins are sourced
      -- (NoMatchParen unsets g:loaded_matchparen, so it must run after matchparen.vim)
      vim.api.nvim_create_autocmd('VimEnter', {
        once = true,
        callback = function()
          pcall(vim.cmd, 'NoMatchParen')
        end,
      })
    end,
    opts = {
      mappings = {
        -- you can call require("blink.pairs.mappings").enable()
        -- and require("blink.pairs.mappings").disable()
        -- to enable/disable mappings at runtime
        enabled = true,
        cmdline = true,
        -- or disable with `vim.g.pairs = false` (global) and `vim.b.pairs = false` (per-buffer)
        -- and/or with `vim.g.blink_pairs = false` and `vim.b.blink_pairs = false`
        disabled_filetypes = {},
        -- see the defaults:
        -- https://github.com/Saghen/blink.pairs/blob/main/lua/blink/pairs/config/mappings.lua#L14
        pairs = {},
      },
      highlights = {
        enabled = true,
        -- requires require('vim._extui').enable({}), otherwise has no effect
        cmdline = true,
        groups = {
          'BlinkPairsOrange',
          'BlinkPairsPurple',
          'BlinkPairsBlue',
        },
        unmatched_group = 'BlinkPairsUnmatched',

        -- highlights matching pairs under the cursor
        matchparen = {
          enabled = true,
          -- known issue where typing won't update matchparen highlight, disabled by default
          cmdline = false,
          -- also include pairs not on top of the cursor, but surrounding the cursor
          include_surrounding = false,
          group = 'BlinkPairsMatchParen',
          priority = 250,
        },
      },
      debug = false,
    }
  }
}

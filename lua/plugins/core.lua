-- Core Dependencies
-- Required by multiple plugins

return {
  -- Lua utility functions (required by many plugins)
  {
    "nvim-lua/plenary.nvim",
    lazy = true,
  },

  -- UI components library (required by some plugins)
  {
    "MunifTanjim/nui.nvim",
    lazy = true,
  },

  -- Icons (choose one)
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },

  -- FZF binary (required by fzf-lua)
  {
    "junegunn/fzf",
    build = "./install --bin",
  },
}

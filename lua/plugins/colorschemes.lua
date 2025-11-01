-- Colorschemes
-- Multiple themes for fzf-lua colorscheme picker

return {
  -- OneDark (default theme)
  {
    "navarasu/onedark.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = 'dark',
      transparent = true,
      term_colors = true,
      ending_tildes = false,
    },
    config = function(_, opts)
      require("onedark").setup(opts)
      vim.cmd([[colorscheme onedark]])
    end,
  },

  -- Catppuccin Mocha
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 999,
    opts = {
      flavour = "mocha",
      transparent_background = true,
      term_colors = true,
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
    end,
  },

  -- Tokyo Night Storm
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 998,
    opts = {
      style = "storm",
      transparent = true,
      terminal_colors = true,
    },
  },

  -- Rose Pine Moon
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 997,
    opts = {
      variant = "moon",
      dark_variant = "moon",
      styles = {
        transparency = true,
      },
    },
  },

  -- GitHub Theme
  {
    "projekt0n/github-nvim-theme",
    lazy = false,
    priority = 996,
    config = function()
      require("github-theme").setup({
        options = {
          transparent = true,
          terminal_colors = true,
        },
      })
    end,
  },
}

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

  -- Kanagawa
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 997,
    opts = {
      transparent = true,
      terminal_colors = true,
    },
  },

  -- Rose Pine
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 996,
    opts = {
      variant = "main",
      dark_variant = "main",
      styles = {
        transparency = true,
      },
    },
  },

  -- Nightfox
  {
    "EdenEast/nightfox.nvim",
    lazy = false,
    priority = 995,
    opts = {
      options = {
        transparent = true,
        terminal_colors = true,
      },
    },
  },

  -- GitHub Theme
  {
    "projekt0n/github-nvim-theme",
    lazy = false,
    priority = 992,
    config = function()
      require("github-theme").setup({
        options = {
          transparent = true,
          terminal_colors = true,
        },
      })
    end,
  },

  -- Gruvbox Material
  {
    "sainnhe/gruvbox-material",
    lazy = false,
    priority = 994,
    config = function()
      vim.g.gruvbox_material_background = "medium"
      vim.g.gruvbox_material_transparent_background = 1
    end,
  },

  -- Everforest
  {
    "sainnhe/everforest",
    lazy = false,
    priority = 993,
    config = function()
      vim.g.everforest_background = "medium"
      vim.g.everforest_transparent_background = 1
      vim.g.everforest_better_performance = 1
    end,
  },

  -- Nord
  {
    "shaunsingh/nord.nvim",
    lazy = false,
    priority = 990,
    config = function()
      vim.g.nord_contrast = true
      vim.g.nord_borders = false
      vim.g.nord_disable_background = true
    end,
  },

  -- Cyberdream
  {
    "scottmckendry/cyberdream.nvim",
    lazy = false,
    priority = 991,
    opts = {
      transparent = true,
      hide_fillchars = true,
      borderless_telescope = true,
    },
  },
}

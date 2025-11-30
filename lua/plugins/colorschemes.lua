-- Colorschemes
-- Multiple themes for fzf-lua colorscheme picker

return {
  -- OneDark
  {
    "navarasu/onedark.nvim",
    lazy = true,
    priority = 996,
    opts = {
      style = 'dark',
      transparent = true,
      term_colors = true,
      ending_tildes = false,
      code_style = {
        comments = 'italic',
        keywords = 'italic',
        functions = 'italic',
        strings = 'none',
        variables = 'none'
      },
    },
  },

  -- Catppuccin Mocha
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = true,
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
    lazy = true,
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
    lazy = true,
    priority = 997,
    opts = {
      transparent = true,
      terminal_colors = true,
    },
  },

  -- Rose Pine (default theme)
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
    opts = {
      variant = "main",
      dark_variant = "main",
      styles = {
        transparency = true,
      },
    },
    config = function(_, opts)
      require("rose-pine").setup(opts)
      vim.cmd([[colorscheme rose-pine]])
    end,
  },

  -- Nightfox
  {
    "EdenEast/nightfox.nvim",
    lazy = true,
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
    lazy = true,
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
    lazy = true,
    priority = 994,
    config = function()
      vim.g.gruvbox_material_background = "medium"
      vim.g.gruvbox_material_transparent_background = 1
    end,
  },

  -- Everforest
  {
    "sainnhe/everforest",
    lazy = true,
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
    lazy = true,
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
    lazy = true,
    priority = 991,
    opts = {
      transparent = true,
      hide_fillchars = true,
      borderless_telescope = true,
    },
  },
}

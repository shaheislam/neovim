-- Colorschemes
-- Multiple themes for fzf-lua colorscheme picker
-- TEST: Added this comment for diff testing

return {
  -- OneDark (a classic dark theme)
  {
    "navarasu/onedark.nvim",
    lazy = true,
    priority = 996, -- TEST: modified this line slightly
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

  -- Catppuccin Mocha - DELETED FOR TESTING

  -- Tokyo Night Storm (default theme)
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "storm",
      transparent = true,
      terminal_colors = true,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd([[colorscheme tokyonight]])
    end,
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

  -- Rose Pine
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = true,
    priority = 999,
    opts = {
      variant = "main",
      dark_variant = "main",
      styles = {
        transparency = true,
      },
    },
  },

  -- Nightfox (commented out for testing)
  -- {
  --   "EdenEast/nightfox.nvim",
  --   lazy = true,
  --   priority = 995,
  --   opts = {
  --     options = {
  --       transparent = true,
  --       terminal_colors = true,
  --     },
  --   },
  -- },

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
      italic_comments = true, -- TEST: added new option
      saturation = 1.0, -- TEST: added new option
    },
  },

  -- TEST: New theme added for testing
  {
    "nyoom-engineering/oxocarbon.nvim",
    lazy = true,
    priority = 985,
  },
}

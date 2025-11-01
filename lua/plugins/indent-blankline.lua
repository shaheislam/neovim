-- indent-blankline.nvim - Indentation guides
-- Shows vertical lines at each indentation level

return {
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      -- Indentation guide configuration
      indent = {
        char = "│",
        tab_char = "│",
      },
      -- Scope configuration (requires treesitter)
      scope = {
        enabled = true,
        show_start = true,
        show_end = false,
        injected_languages = true,
        highlight = { "Function", "Label" },
        priority = 500,
      },
      -- Exclude certain filetypes
      exclude = {
        filetypes = {
          "help",
          "alpha",
          "dashboard",
          "neo-tree",
          "Trouble",
          "trouble",
          "lazy",
          "mason",
          "notify",
          "toggleterm",
          "lazyterm",
        },
      },
    },
  },
}

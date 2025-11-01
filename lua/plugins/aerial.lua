-- Aerial symbol browser and breadcrumb navigation
return {
  "stevearc/aerial.nvim",
  event = "LspAttach",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    attach_mode = "global",
    backends = { "lsp", "treesitter", "markdown" },
    show_guides = true,
    layout = {
      min_width = 30,
      default_direction = "prefer_right",
      resize_to_content = false,
    },
    -- Show guide lines for nested symbols
    guides = {
      mid_item = "├╴",
      last_item = "└╴",
      nested_top = "│ ",
      whitespace = "  ",
    },
  },
  keys = {
    { "<leader>cs", "<cmd>AerialToggle<cr>", desc = "Aerial (Symbols)" },
    { "<leader>cS", "<cmd>AerialNavToggle<cr>", desc = "Aerial Nav" },
  },
}

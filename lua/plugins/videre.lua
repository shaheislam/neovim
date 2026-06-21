-- videre.nvim - interactive JSON/YAML/TOML graph explorer
return {
  "Owen-Dechow/videre.nvim",
  cmd = "Videre",
  dependencies = {
    "Owen-Dechow/graph_view_yaml_parser", -- YAML support
    "Owen-Dechow/graph_view_toml_parser", -- TOML support
  },
  keys = {
    { "<leader>Jo", "<cmd>Videre<cr>", desc = "Open graph explorer" },
  },
  opts = {
    box_style = "rounded",
    line_style = "rounded",
  },
}

-- Typr - Typing practice game for Neovim
-- Interactive typing speed practice within the editor

return {
  {
    "nvzone/typr",
    dependencies = "nvzone/volt",  -- Required UI framework dependency
    cmd = { "Typr", "TyprStats" },
    keys = {
      { "<leader>tt", "<cmd>Typr<cr>", desc = "Open Typr (typing practice)" },
      { "<leader>ts", "<cmd>TyprStats<cr>", desc = "Typr Statistics" },
    },
    opts = {},
  },
}

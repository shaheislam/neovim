-- blink.indent - Fast indentation guides
-- Shows vertical lines at each indentation level (~10x faster than alternatives)

return {
  {
    "saghen/blink.indent",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      -- Exclude certain filetypes and buftypes
      blocked = {
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

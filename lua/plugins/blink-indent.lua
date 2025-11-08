-- blink.indent - Fast indentation guides
-- Shows only colored scope guides for the active code block (~10x faster than alternatives)

return {
  {
    "saghen/blink.indent",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      -- Disable static guides (non-active indent lines)
      static = {
        enabled = false,
      },
      -- Keep scope guides enabled (shows only active/current scope)
      scope = {
        enabled = true,
      },
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

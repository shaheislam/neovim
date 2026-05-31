-- pi.nvim - lightweight Pi agent integration
-- OpenCode remains the primary stateful coding-agent workflow; Pi is for quick
-- buffer/selection edits and one-shot asks.

return {
  {
    "pablopunk/pi.nvim",
    version = false,
    cmd = { "PiAsk", "PiAskSelection", "PiCancel", "PiLog" },
    keys = {
      {
        "<leader>apa",
        "<cmd>PiAsk<cr>",
        mode = "n",
        desc = "Ask Pi",
      },
      {
        "<leader>apa",
        ":PiAskSelection<cr>",
        mode = "x",
        desc = "Ask Pi selection",
      },
      {
        "<leader>apc",
        "<cmd>PiCancel<cr>",
        mode = "n",
        desc = "Cancel Pi",
      },
      {
        "<leader>apl",
        "<cmd>PiLog<cr>",
        mode = "n",
        desc = "Pi log",
      },
    },
    opts = {
      binary = "pi",
      thinking = "off",
      skills = true,
      extensions = true,
      context = {
        max_bytes = 24000,
        ask = {
          surrounding_lines = 80,
        },
        selection = {
          surrounding_lines = 40,
        },
        diagnostics = {
          enabled = false,
        },
      },
    },
  },
}

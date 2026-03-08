-- opencode.nvim - AI coding agent integration
-- Connects to opencode server (running with --port) via HTTP + SSE
-- Shares editor context (buffers, selections, diagnostics) with the agent

return {
  {
    "nickjvandyke/opencode.nvim",
    version = "*",
    cmd = { "Opencode" },
    keys = {
      -- Toggle opencode terminal (primary entry point)
      {
        "<C-.>",
        function() require("opencode").toggle() end,
        mode = { "n", "t" },
        desc = "Toggle opencode",
      },
      -- Ask opencode with current context
      {
        "<leader>Aa",
        function() require("opencode").ask("@this: ", { submit = false }) end,
        mode = { "n", "x" },
        desc = "Ask opencode",
      },
      -- Quick ask with auto-submit
      {
        "<leader>As",
        function() require("opencode").ask("@this: ", { submit = true }) end,
        mode = { "n", "x" },
        desc = "Ask opencode (submit)",
      },
      -- Action picker
      {
        "<leader>Ax",
        function() require("opencode").select() end,
        mode = { "n", "x" },
        desc = "opencode actions",
      },
      -- Operator-pending mode (select range then type prompt)
      {
        "go",
        function() return require("opencode").operator("@this ") end,
        mode = { "n", "x" },
        desc = "Add range to opencode",
        expr = true,
      },
      {
        "goo",
        function() return require("opencode").operator("@this ") .. "_" end,
        mode = "n",
        desc = "Add line to opencode",
        expr = true,
      },
      -- Named prompts via leader
      {
        "<leader>Ae",
        function() require("opencode").prompt("explain") end,
        mode = { "n", "x" },
        desc = "Explain (opencode)",
      },
      {
        "<leader>Af",
        function() require("opencode").prompt("fix") end,
        mode = { "n", "x" },
        desc = "Fix diagnostics (opencode)",
      },
      {
        "<leader>Ar",
        function() require("opencode").prompt("review") end,
        mode = { "n", "x" },
        desc = "Review (opencode)",
      },
      {
        "<leader>At",
        function() require("opencode").prompt("test") end,
        mode = { "n", "x" },
        desc = "Add tests (opencode)",
      },
      {
        "<leader>Ad",
        function() require("opencode").prompt("document") end,
        mode = { "n", "x" },
        desc = "Document (opencode)",
      },
      {
        "<leader>Ao",
        function() require("opencode").prompt("optimize") end,
        mode = { "n", "x" },
        desc = "Optimize (opencode)",
      },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        events = {
          enabled = true,
          reload = true,
        },
      }

      -- Required for auto-reload when opencode edits files
      vim.o.autoread = true
    end,
  },
}

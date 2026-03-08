-- opencode.nvim - AI coding agent integration
-- Connects to opencode server (running with --port) via HTTP + SSE
-- Shares editor context (buffers, selections, diagnostics) with the agent

return {
  {
    "nickjvandyke/opencode.nvim",
    version = "*",
    cmd = { "Opencode" },
    keys = {
      -- Toggle opencode terminal
      {
        "<leader>aoc",
        function() require("opencode").toggle() end,
        mode = { "n", "t" },
        desc = "Toggle opencode",
      },
      -- Quick toggle (global shortcut)
      {
        "<C-.>",
        function() require("opencode").toggle() end,
        mode = { "n", "t" },
        desc = "Toggle opencode",
      },
      -- Ask opencode with current context
      {
        "<leader>aoa",
        function() require("opencode").ask("@this: ", { submit = false }) end,
        mode = { "n", "x" },
        desc = "Ask opencode",
      },
      -- Quick ask with auto-submit
      {
        "<leader>aos",
        function() require("opencode").ask("@this: ", { submit = true }) end,
        mode = { "n", "x" },
        desc = "Ask opencode (submit)",
      },
      -- Action picker
      {
        "<leader>aox",
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
      -- Named prompts
      {
        "<leader>aoe",
        function() require("opencode").prompt("explain") end,
        mode = { "n", "x" },
        desc = "Explain (opencode)",
      },
      {
        "<leader>aof",
        function() require("opencode").prompt("fix") end,
        mode = { "n", "x" },
        desc = "Fix diagnostics (opencode)",
      },
      {
        "<leader>aor",
        function() require("opencode").prompt("review") end,
        mode = { "n", "x" },
        desc = "Review (opencode)",
      },
      {
        "<leader>aot",
        function() require("opencode").prompt("test") end,
        mode = { "n", "x" },
        desc = "Add tests (opencode)",
      },
      {
        "<leader>aod",
        function() require("opencode").prompt("document") end,
        mode = { "n", "x" },
        desc = "Document (opencode)",
      },
      {
        "<leader>aoo",
        function() require("opencode").prompt("optimize") end,
        mode = { "n", "x" },
        desc = "Optimize (opencode)",
      },
      {
        "<leader>aoi",
        function() require("opencode").prompt("implement") end,
        mode = { "n", "x" },
        desc = "Implement (opencode)",
      },
      {
        "<leader>aog",
        function() require("opencode").prompt("diff") end,
        mode = { "n", "x" },
        desc = "Review git diff (opencode)",
      },
      {
        "<leader>aoE",
        function() require("opencode").prompt("diagnostics") end,
        mode = { "n", "x" },
        desc = "Explain diagnostics (opencode)",
      },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        events = {
          enabled = true,
          reload = true,
          permissions = {
            enabled = true,
            idle_delay_ms = 1000,
          },
        },
        lsp = {
          enabled = true,
        },
      }

      -- Required for auto-reload when opencode edits files
      vim.o.autoread = true

      -- Track opencode status for statusline via OpencodeEvent autocmds
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:session.idle",
        callback = function()
          vim.g.opencode_status = "idle"
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:session.busy",
        callback = function()
          vim.g.opencode_status = "busy"
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:file.edited",
        callback = function()
          vim.cmd("checktime")
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:connected",
        callback = function()
          vim.g.opencode_status = "connected"
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:disconnected",
        callback = function()
          vim.g.opencode_status = nil
        end,
      })
    end,
  },
}

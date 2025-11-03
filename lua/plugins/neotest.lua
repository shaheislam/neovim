-- ~/.config/nvim-mini/lua/plugins/neotest.lua
-- Test integration for running tests across multiple languages

return {
  -- Test integration for code lens "Run Test" actions
  {
    "nvim-neotest/neotest",
    dependencies = {
      -- Core dependencies (required by neotest)
      "nvim-neotest/nvim-nio",           -- Async IO library (REQUIRED)
      "nvim-lua/plenary.nvim",           -- Lua utility functions
      "antoinemadec/FixCursorHold.nvim", -- Fix CursorHold performance
      "nvim-treesitter/nvim-treesitter", -- Syntax parsing

      -- Test adapters
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-go",
      "nvim-neotest/neotest-jest",
      "rouge8/neotest-rust",
      "nvim-neotest/neotest-vim-test",
    },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}

      -- Add test adapters for different languages
      table.insert(opts.adapters, require("neotest-python")({
        dap = { justMyCode = false },
        runner = "pytest",
      }))

      table.insert(opts.adapters, require("neotest-go")({
        experimental = {
          test_table = true,
        },
      }))

      table.insert(opts.adapters, require("neotest-jest")({
        jestCommand = "npm test --",
        env = { CI = true },
        cwd = function(path)
          return vim.fn.getcwd()
        end,
      }))

      table.insert(opts.adapters, require("neotest-rust")({
        args = { "--no-capture" },
      }))

      return opts
    end,
    keys = {
      -- Test running keymaps (work with code lens)
      { "<leader>tt", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run File Tests" },
      { "<leader>tT", function() require("neotest").run.run(vim.uv.cwd()) end, desc = "Run All Tests" },
      { "<leader>tr", function() require("neotest").run.run() end, desc = "Run Nearest Test" },
      { "<leader>tl", function() require("neotest").run.run_last() end, desc = "Run Last Test" },
      { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Toggle Test Summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Show Test Output" },
      { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Toggle Test Output Panel" },
      { "<leader>tS", function() require("neotest").run.stop() end, desc = "Stop Tests" },
      { "<leader>tw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Toggle Test Watch" },
    },
  },
}

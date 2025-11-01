return {
  "mfussenegger/nvim-dap",
  lazy = true,
  dependencies = {
    -- Go debugging support
    {
      "leoluz/nvim-dap-go",
      ft = "go",
      opts = {},
    },
  },
  keys = {
    -- Test debugging (requires neotest)
    { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug Nearest Test" },

    -- Basic debugging controls
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
    { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = "Conditional Breakpoint" },
    { "<leader>dc", function() require("dap").continue() end, desc = "Continue/Start Debug" },
    { "<leader>dC", function() require("dap").run_to_cursor() end, desc = "Run to Cursor" },
    { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate Debug" },

    -- Stepping
    { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
    { "<leader>do", function() require("dap").step_over() end, desc = "Step Over" },
    { "<leader>dO", function() require("dap").step_out() end, desc = "Step Out" },
    { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
    { "<leader>dl", function() require("dap").run_last() end, desc = "Run Last Debug" },

    -- Hover for variable inspection (K in debug mode)
    { "<leader>dh", function() require("dap.ui.widgets").hover() end, desc = "Hover Variables" },
    { "<leader>dp", function() require("dap.ui.widgets").preview() end, desc = "Preview Variables" },
  },
  config = function()
    local dap = require("dap")

    -- Debug signs
    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticSignError", linehl = "", numhl = "" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticSignError", linehl = "", numhl = "" })
    vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticSignInfo", linehl = "DiagnosticVirtualTextInfo", numhl = "" })
    vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticSignHint", linehl = "", numhl = "" })
    vim.fn.sign_define("DapLogPoint", { text = "◉", texthl = "DiagnosticSignInfo", linehl = "", numhl = "" })

    -- Python configuration (using debugpy)
    dap.adapters.python = {
      type = "executable",
      command = "python",
      args = { "-m", "debugpy.adapter" },
    }

    dap.configurations.python = {
      {
        type = "python",
        request = "launch",
        name = "Launch file",
        program = "${file}",
        pythonPath = function()
          -- Use activated virtualenv
          if vim.env.VIRTUAL_ENV then
            return vim.env.VIRTUAL_ENV .. "/bin/python"
          end
          -- Fallback to system python
          return "/usr/bin/python3"
        end,
      },
    }

    -- Node/TypeScript configuration
    -- Requires: npm install -g @vscode/js-debug
    dap.adapters["pwa-node"] = {
      type = "server",
      host = "localhost",
      port = "${port}",
      executable = {
        command = "node",
        args = {
          vim.fn.expand("~/.local/share/nvim-mini/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js"),
          "${port}",
        },
      },
    }

    dap.configurations.javascript = {
      {
        type = "pwa-node",
        request = "launch",
        name = "Launch file",
        program = "${file}",
        cwd = "${workspaceFolder}",
      },
    }

    dap.configurations.typescript = dap.configurations.javascript

    -- Note: Rust debugging is handled by rustaceanvim
    -- Note: Go debugging is handled by nvim-dap-go
  end,
}
-- trace.nvim: trace Go values back toward their origin with LSP + treesitter.
-- Vendored under trace.nvim/ because the engine is local and Go-specific.
return {
  {
    dir = vim.fn.stdpath("config") .. "/trace.nvim",
    keys = {
      {
        "<leader>lu",
        function()
          require("trace").trace_up_n(vim.v.count1)
        end,
        desc = "Trace value up",
      },
      {
        "<leader>lU",
        function()
          local count = vim.v.count > 0 and vim.v.count or 1000
          require("trace").trace_up_n(count, { quickfix = true })
        end,
        desc = "Trace value to origin",
      },
      {
        "<leader>lz",
        function()
          local opts = {}
          if vim.v.count > 0 then
            opts.max_depth = vim.v.count
          end
          require("trace").trace_tree(opts)
        end,
        desc = "Trace provenance tree",
      },
      {
        "<leader>lp",
        function()
          require("trace").peek()
        end,
        desc = "Peek trace sources",
      },
    },
    cmd = { "TraceUp", "TraceOrigin", "TraceTree", "TracePeek", "TraceDebug" },
    opts = {
      peek_context = 3,
    },
    config = function(_, opts)
      local trace = require("trace")
      trace.setup(opts)

      vim.api.nvim_create_user_command("TraceUp", function(cmd)
        trace.trace_up_n(cmd.count > 0 and cmd.count or 1)
      end, { count = true, desc = "Trace a value one hop up toward its origin" })

      vim.api.nvim_create_user_command("TraceOrigin", function(cmd)
        trace.trace_up_n(cmd.count > 0 and cmd.count or 1000, { quickfix = true })
      end, { count = true, desc = "Trace a value to its origin into quickfix" })

      vim.api.nvim_create_user_command("TraceTree", function(cmd)
        local trace_opts = {}
        if cmd.count > 0 then
          trace_opts.max_depth = cmd.count
        end
        trace.trace_tree(trace_opts)
      end, { count = true, desc = "Build a value provenance tree into quickfix" })

      vim.api.nvim_create_user_command("TracePeek", function()
        trace.peek()
      end, { desc = "Peek at value trace sources without jumping" })

      vim.api.nvim_create_user_command("TraceDebug", function(cmd)
        trace.config.debug = cmd.bang or not trace.config.debug
        print("Trace debug " .. (trace.config.debug and "enabled" or "disabled"))
      end, { bang = true, desc = "Toggle trace debug logging" })
    end,
  },
}

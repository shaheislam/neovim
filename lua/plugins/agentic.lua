return {
  {
    "carlos-algms/agentic.nvim",
    dependencies = {
      "HakonHarnes/img-clip.nvim",
    },
    keys = {
      {
        "<leader>aao",
        function()
          require("agentic").open({ auto_add_to_context = false })
        end,
        mode = { "n", "v" },
        desc = "Open Agentic",
      },
      {
        "<leader>aat",
        function()
          require("agentic").toggle()
        end,
        mode = { "n", "v", "i" },
        desc = "Toggle Agentic",
      },
      {
        "<leader>aac",
        function()
          require("agentic").add_selection_or_file_to_context()
        end,
        mode = { "n", "v" },
        desc = "Add File/Selection",
      },
      {
        "<leader>aad",
        function()
          require("agentic").add_current_line_diagnostics()
        end,
        mode = "n",
        desc = "Add Line Diagnostics",
      },
      {
        "<leader>aaD",
        function()
          require("agentic").add_buffer_diagnostics()
        end,
        mode = "n",
        desc = "Add Buffer Diagnostics",
      },
      {
        "<leader>aan",
        function()
          require("agentic").new_session()
        end,
        mode = { "n", "v", "i" },
        desc = "New Session",
      },
      {
        "<leader>aar",
        function()
          require("agentic").restore_session()
        end,
        mode = { "n", "v", "i" },
        desc = "Restore Session",
      },
      {
        "<leader>aap",
        function()
          require("agentic").switch_provider()
        end,
        mode = "n",
        desc = "Switch Provider",
      },
      {
        "<leader>aal",
        function()
          require("agentic").rotate_layout({ "right", "bottom", "left" })
        end,
        mode = "n",
        desc = "Rotate Layout",
      },
      {
        "<leader>aas",
        function()
          require("agentic").stop_generation()
        end,
        mode = "n",
        desc = "Stop Generation",
      },
    },
    opts = {
      provider = "claude-agent-acp",
      windows = {
        position = "right",
        width = "40%",
        height = "30%",
      },
      diff_preview = {
        enabled = true,
        layout = "split",
        center_on_navigate_hunks = true,
      },
    },
  },
}

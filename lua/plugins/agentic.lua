-- agentic.nvim - ACP-based AI chat panel (Cursor/Windsurf-like experience)
-- Provider-agnostic: Claude (default), Gemini, Codex, OpenCode all available
-- Toggle with <C-\>, switch providers live with <localleader>s
-- Complements CodeCompanion (API-based) and claude-bridge (state export)

return {
  {
    "carlos-algms/agentic.nvim",
    dependencies = {
      "hakonharnes/img-clip.nvim", -- already in config; enables image paste in chat
    },
    cmd = { "Agentic" },
    keys = {
      -- Primary: toggle chat panel (Cursor-style <C-\>)
      -- toggleterm.lua sets open_mapping = nil, so <C-\> is free
      {
        "<C-\\>",
        function() require("agentic").toggle() end,
        mode = { "n", "v", "i" },
        desc = "Toggle Agentic Chat",
      },
      -- Add current selection or file to chat context
      {
        "<C-'>",
        function() require("agentic").add_selection_or_file_to_context() end,
        mode = { "n", "v" },
        desc = "Add to Agentic Context",
      },
      -- New chat session
      {
        "<C-,>",
        function() require("agentic").new_session() end,
        mode = { "n", "v", "i" },
        desc = "New Agentic Session",
      },
      -- Leader-key actions under <leader>A (capital, distinct from CodeCompanion's <leader>a)
      {
        "<leader>Ar",
        function() require("agentic").restore_session() end,
        desc = "Restore Agentic Session",
      },
      {
        "<leader>Ad",
        function() require("agentic").add_current_line_diagnostics() end,
        desc = "Add Line Diagnostics",
        mode = "n",
      },
      {
        "<leader>AD",
        function() require("agentic").add_buffer_diagnostics() end,
        desc = "Add Buffer Diagnostics",
        mode = "n",
      },
    },
    opts = {
      -- Default to Claude via ACP (installed at ~/.bun/bin/claude-agent-acp)
      provider = "claude-agent-acp",

      window = {
        position = "right",
        width = "40%",
      },

      -- Sub-panel tuning
      input = { height = 12 },
      todos = { display = true },

      -- Diff preview for proposed edits
      diff_preview = {
        enabled = true,
        layout = "split",
        center_on_navigate_hunks = true,
      },

      -- Image paste via img-clip.nvim (already configured)
      image_paste = { enabled = true },

      -- Session persistence across restarts
      -- Default storage: ~/.cache/nvim/agentic/sessions/
    },
  },
}

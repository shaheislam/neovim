-- agentic.nvim - ACP-based AI chat panel (Cursor/Windsurf-like experience)
-- Provider-agnostic: Claude (default), Gemini, Codex, OpenCode all available
-- Primary toggle: <leader>At, switch providers live with <localleader>s
-- Complements CodeCompanion (API-based) and claude-bridge (state export)

-- Resolve the best available ACP provider at load time.
-- claude-agent-acp is preferred; falls back to others that are in PATH.
local function resolve_provider()
  local candidates = {
    { id = "claude-agent-acp", cmd = "claude-agent-acp" },
    { id = "gemini",           cmd = "gemini" },
    { id = "codex-acp",        cmd = "codex" },
    { id = "opencode-acp",     cmd = "opencode" },
  }
  for _, c in ipairs(candidates) do
    if vim.fn.executable(c.cmd) == 1 then
      return c.id
    end
  end
  return "claude-agent-acp" -- ultimate fallback; healthcheck will flag it
end

return {
  {
    "carlos-algms/agentic.nvim",
    dependencies = {
      "hakonharnes/img-clip.nvim", -- already in config; enables image paste in chat
    },
    cmd = { "Agentic" },
    keys = {
      -- ── Leader-based primary bindings (always reliable) ──────────
      {
        "<leader>At",
        function() require("agentic").toggle() end,
        mode = { "n", "v" },
        desc = "Toggle Chat",
      },
      {
        "<leader>Aa",
        function() require("agentic").add_selection_or_file_to_context() end,
        mode = { "n", "v" },
        desc = "Add to Context",
      },
      {
        "<leader>An",
        function() require("agentic").new_session() end,
        mode = { "n", "v" },
        desc = "New Session",
      },
      {
        "<leader>Ar",
        function() require("agentic").restore_session() end,
        desc = "Restore Session",
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

      -- ── Convenience shortcut (normal + visual only) ──────────────
      -- <C-\> is a builtin prefix in insert mode (<C-\><C-n>, <C-\><C-o>),
      -- so we intentionally exclude insert mode to avoid timeoutlen friction.
      -- toggleterm.lua sets open_mapping = nil, keeping <C-\> free in n/v.
      {
        "<C-\\>",
        function() require("agentic").toggle() end,
        mode = { "n", "v" },
        desc = "Toggle Agentic Chat",
      },
    },
    opts = function()
      return {
        provider = resolve_provider(),

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

        -- Sessions persist to ~/.cache/nvim/agentic/sessions/ (local only).
        -- No data is sent externally beyond what the ACP provider sees in-chat.
      }
    end,
  },
}

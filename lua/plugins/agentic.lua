-- agentic.nvim - ACP-based AI chat panel (Cursor/Windsurf-like experience)
-- Provider-agnostic: Claude (default), Gemini, Codex, OpenCode all available
-- Primary toggle: <leader>At, switch providers live with <localleader>s
-- Complements CodeCompanion (API-based) and claude-bridge (state export)
--
-- Security notes:
--   Sessions persist full conversation (messages, tool calls, diffs) unencrypted
--   to ~/.cache/nvim/agentic/sessions/. Local-only, no external upload.
--   Tool execution requires explicit permission (allow_once/always, reject_once/always).
--   setup() installs a FileChangedShell autocmd that auto-reloads buffers when the
--   agent edits files on disk — modified buffers reload silently without prompting.

-- Resolve the best available ACP provider at load time.
-- Command names must match the plugin's acp_providers config (config_default.lua),
-- NOT the general CLI tool names (e.g. codex-acp binary, not codex).
local function resolve_provider()
  local candidates = {
    { id = "claude-agent-acp", cmd = "claude-agent-acp" },
    { id = "gemini-acp",       cmd = "gemini" },
    { id = "codex-acp",        cmd = "codex-acp" },
    { id = "opencode-acp",     cmd = "opencode" },
  }
  for _, c in ipairs(candidates) do
    if vim.fn.executable(c.cmd) == 1 then
      return c.id
    end
  end
  -- Fallback; :checkhealth agentic will flag if the command is missing or
  -- unauthenticated. Auth status can't be checked from a lazy spec.
  return "claude-agent-acp"
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
      -- <C-\> in insert mode is a Neovim builtin prefix (<C-\><C-n>, <C-\><C-o>);
      -- mapping it there adds timeoutlen delay and breaks muscle memory.
      -- In normal/visual <C-\> may not transmit through all terminal/tmux/SSH
      -- chains — <leader>At is the reliable alternative.
      -- toggleterm.lua sets open_mapping = nil, so no conflict in n/v.
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

        -- Hooks drive the lualine status indicator (vim.g.agentic_visible/generating).
        -- on_prompt_submit fires when user sends a message; on_response_complete when
        -- the agent finishes. There's no public is_visible() API, so we track state
        -- ourselves via vim.g globals that lualine reads.
        hooks = {
          on_prompt_submit = function()
            vim.g.agentic_visible = true
            vim.g.agentic_generating = true
          end,
          on_response_complete = function()
            vim.g.agentic_generating = false
          end,
        },

        -- Sessions persist to ~/.cache/nvim/agentic/sessions/ (local filesystem only).
        -- Contains full conversation text, tool call args, and diffs — not encrypted.
        -- No data is sent externally beyond what the ACP provider sees in-chat.
        -- Run :checkhealth agentic after first load to verify provider auth status.
      }
    end,
  },
}

# Config Agent Guide

Rules for `~/neovim/lua/config`.

## Core Config

- Global editor keymaps belong in `keymaps.lua`.
- Plugin-specific keymaps belong in that plugin's spec file under `lua/plugins/`.
- Always include `desc` on keymaps for which-key discovery.
- Use project-prefixed augroups with `clear = true`.
- Skip expensive LSP operations in diff buffers when helpers such as `is_diff_buf()` are available.

## Agent Bridge

- `claude-bridge.lua` writes editor state to `/tmp/nvim-claude-bridge/`.
- `hotreload.lua` handles external edit reload behavior; avoid adding competing file watchers.
- Keep bridge and hotreload changes reviewed through diagnostics, quickfix, and git diff.

## Validation

- Run `nvim --headless +qa` after core config changes.
- Run `nvim --headless "+checkhealth nvim_mini" +qa` after bridge, LSP, or health changes.

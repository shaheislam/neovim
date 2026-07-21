# Neovim Agent Guide

Global rules for `~/neovim`. Read any deeper `AGENTS.md` in the directory you are editing.

## Scope

- This is the personal Neovim config repo, separate from `~/dotfiles`.
- It is symlinked to `~/.config/nvim` and should remain commit-worthy across devices.
- LSPs are Nix-managed; never add Mason or `mason-lspconfig`.
- Preserve transparent UI behavior unless the task explicitly changes the theme model.

## Subdirectory Guidance

- `lua/AGENTS.md` covers Lua module style and runtime conventions.
- `lua/config/AGENTS.md` covers core config, keymaps, autocmds, and agent bridges.
- `lua/plugins/AGENTS.md` covers lazy.nvim plugin specs.
- `lua/plugins/git/AGENTS.md` covers Git plugin integrations.
- `lua/git/AGENTS.md` covers custom Git workflow modules.
- `lua/parley/AGENTS.md` covers Parley review tooling.
- `tests/AGENTS.md` covers headless Neovim tests.

## Workflow Contract

- `.plan.md` is untracked per-worktree durable state; agents read it for context and mutate it only through the current `planctl` turn guard, never by direct edits.
- Use `opencode.nvim` as the primary Neovim bridge into OpenCode.
- Trusted idle handoff stays in the originating tmux window: open Diffview first when appropriate, then open or reuse one `.plan.md` tab and focus it last. With no trusted source pane, do nothing.
- Treat diagnostics, quickfix, and git diff as the review plane before handoff.

## Beads

- This project uses `bd` for issue tracking; run `bd onboard` for full context.
- Use `bd ready`, `bd show <id>`, `bd update <id> --status in_progress`, and `bd close <id>` for task lifecycle.

## Validation

- Run `nvim --headless +qa` for startup validation.
- Run `nvim --headless "+checkhealth nvim_mini" +qa` for project health.
- Run `nvim --headless -l tests/parley_review_spec.lua` when review tooling changes.

## Session Completion

- If code changed, run relevant validation before finishing.
- Push bead state with `bd dolt push` when issue state changed.
- Work is not complete until commits and `git push` succeed when the task reaches session-completion scope.

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

- `.plan.md` is an untracked per-worktree markdown document maintained by hand; agents read it for context and edit it directly when asked. There is no coordinator or turn guard.
- Use `opencode.nvim` as the primary Neovim bridge into OpenCode.
- Trusted idle handoff stays in the originating tmux window: open Diffview first when appropriate, then open or reuse one `.plan.md` tab and focus it last. With no trusted source pane, do nothing.
- `config.diffview_idle` stamps `@nvim_project` once from the launch directory and never updates it on `DirChanged`; `@nvim_cwd` keeps following the cwd for other consumers. Matching on `@nvim_cwd` alone loses this editor as soon as a file is opened in a subdirectory, which makes every later handoff split a duplicate pane. `VimLeavePre` clears `@nvim_server`, `@nvim_cwd`, and `@nvim_project` synchronously, because a detached job is not guaranteed to run before exit and leaves the pane advertising an editor it no longer runs.
- A plan-save notification route is only honoured when its `serverPid` matches the live tmux generation and `diffview-review.sh verify-pane` proves the source pane; matching window and directory are not ownership, since pane IDs are reused after a tmux restart.
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

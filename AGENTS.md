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
- A Neovim-owned OpenCode TUI registers an opaque terminal generation before spawn. The TUI bridge must complete hello, lease, and monotonic session binding before `config.opencode_handoff` accepts an idle batch; stale generation, session, revision, lease, or out-of-project paths fail closed with no tmux fallback.
- `config.opencode_status` accepts exact `error|permission|question|busy|idle` events only from those bound TUI routes, aggregates all bound sessions with that precedence, and publishes owner/PID-proven pane facts through the dotfiles `tmux-agent-state` helper. Raw `session.status` remains a compatibility fallback; idle requires every binding to be known idle.
- Native idle handoff keeps the matching OpenCode terminal generation open, reloads changed buffers, fills quickfix without opening it, focuses the latest changed normal file in the leftmost unlocked, unmodified nonterminal window, and, when the root `.plan.md` changed, opens Diffview before focusing one reused plan tab. A newer accepted route discards pending work from the prior route.
- `config.diffview_idle.open_from_tmux()` remains a separate deliberate/Claude compatibility route. It stays in the trusted source tmux window and uses pane ownership checks; native plan provenance never falls back to this route.
- `config.diffview_idle` stamps `@nvim_project` once from the launch directory and never updates it on `DirChanged`; `@nvim_cwd` keeps following the cwd for other consumers. Matching on `@nvim_cwd` alone loses this editor as soon as a file is opened in a subdirectory, which makes every later handoff split a duplicate pane. `VimLeavePre` clears `@nvim_server`, `@nvim_cwd`, and `@nvim_project` synchronously, because a detached job is not guaranteed to run before exit and leaves the pane advertising an editor it no longer runs.
- Native plan-save notification is honoured only while its exact project, session, generation, route revision, and route token remain live. Legacy tmux plans separately require a live tmux `serverPid` plus `diffview-review.sh verify-pane`; route kinds never fall back into one another.
- Treat diagnostics, quickfix, and git diff as the review plane before handoff.

## Beads

- This project uses `bd` for issue tracking; run `bd onboard` for full context.
- Use `bd ready`, `bd show <id>`, `bd update <id> --status in_progress`, and `bd close <id>` for task lifecycle.

## Validation

- Run `nvim --headless +qa` for startup validation.
- Run `nvim --headless "+checkhealth nvim_mini" +qa` for project health.
- Run the OpenCode handoff specs: `tests/opencode_handoff_spec.lua`, `tests/opencode_terminal_spec.lua`, `tests/opencode_plugin_spec.lua`, `tests/plan_idle_spec.lua`, and `tests/plan_save_push_spec.lua`.
- Run `nvim --headless -l tests/parley_review_spec.lua` when review tooling changes.

## Session Completion

- If code changed, run relevant validation before finishing.
- Commit validated changes before finishing, following the commit policy below.
- Push Git commits or bead state only when the user asks.

## Commits

- Commit mode is on by the user's standing request for this repository and every worktree spawned from it, regardless of checkout path. After a logical change passes its checks, commit it locally without asking again. `/commit-mode off` disables this for the session.
- Commit on the branch in the checkout where the work was done; never switch to the main checkout just to commit a worktree's changes.
- Stage only your task's changes, by explicit path. Never use `git add -A`, `git add .` or `git add -u`; leave unrelated edits out of the commit.
- Use a conventional `type: summary` subject under 72 characters, followed by a reasoning body explaining why the change was needed and how it was validated.
- Let configured Git hooks run. Never use `--no-verify`; fix failures, restage and retry the commit.

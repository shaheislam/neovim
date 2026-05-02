# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd dolt push          # Push bead state to remote
```

## Workflow Contract

- Read `.claude/context/workflows.md` before changing how AI tooling is used in this repo.
- Read `.claude/context/ai-cheatsheet.md` for the fast operator view.
- Read `.claude/context/ai-recipes.md` for the expected handoff patterns between learning, investigation, execution, and review.
- Treat `.plan.md` as the control plane for the current task.
- Use `opencode.nvim` as the Neovim bridge into OpenCode, and `sidekick.nvim` for learning-oriented Copilot NES / CLI assist.
- Treat git diff, diagnostics, and quickfix as the required review plane before handoff.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

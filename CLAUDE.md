# Neovim Configuration (nvim-mini)

> Personal Neovim config. Standalone repo, NOT part of `~/dotfiles`. Symlinked to `~/.config/nvim`; launched as its own app via `nvm` (alias for `NVIM_APPNAME=nvim-mini nvim`). Commit-worthy across devices.

## Structure

```
init.lua                       # Entry point: leader keys, lazy.nvim bootstrap, disable builtins
lazy-lock.json                 # Pinned plugin commits (lazy.nvim lockfile)
.emmyrc.json                   # EmmyLua/LuaLS analyzer config (LuaJIT runtime, `vim` global)
mise.toml                      # Toolchain pin (python for tooling)

lua/config/                    # Core config + custom runtime helpers
  options.lua                  # Editor settings (numbers, tabs=2, OSC-52 clipboard, diff opts)
  keymaps.lua                  # Global editor mappings + git permalink utilities
  usercommands.lua             # Deterministic editor-native text transforms (:commands)
  autocmds.lua                 # Orchestrates autocmd submodules, auto-save, transparent floats
  autocmds/lsp.lua             # Import organization, doc highlight, codelens, inlay hints
  autocmds/styling.lua         # Theme-consistent italics/bold, Blink highlight colors
  hotreload.lua                # File watcher for Claude Code integration (debounced)
  claude-bridge.lua            # Writes editor state to /tmp/nvim-claude-bridge/
  opencode_http.lua            # HTTP client for the launchd-managed OpenCode server
  opencode_messages.lua        # Reads/caches OpenCode session + message history
  opencode_pickers.lua         # fzf pickers over OpenCode sessions/prompts/tools/reasoning
  annotations.lua              # Inline repo annotation ghosts (virtual text) + resolve flow
  filter.lua                   # Structured text filters (replace buffer/range/selection)
  bufutil.lua                  # Buffer helpers (URI buffer detection, etc.)
  kubectl.lua                  # :Kube command — pod file push/pull/picker workflows
  return_target.lua            # Track/restore a "return here" jump target

lua/git/                       # Reusable Git workflow LOGIC (headless-testable, no UI)
  command.lua                  # Thin git-exec wrapper returning {ok, stdout, ...}
  workflow.lua                 # Shared workflow helpers wired into plugin specs (setup())
  diffview.lua / diffview_workflow.lua  # Diffview navigation + jump-to-first-diff logic
  flog.lua                     # Commit-graph branch coloring helpers

lua/parley/                    # Markdown review tooling
  review.lua                   # Parses `㊷[text]` review markers + `{question}` blocks

lua/nvim_mini/
  health.lua                   # Custom `:checkhealth nvim_mini` (hotreload, bridge, etc.)

lua/plugins/                   # One file per plugin (lazy.nvim specs) — ~48 files
  core.lua                     # Shared deps: plenary, nui, devicons, fzf
  lsp.lua                      # Nix-aware LSP (no Mason) + K8s schema routing
  lsp-*.lua                    # Language/domain LSP add-ons (rust, devops, garmin, enhancements)
  colorschemes.lua             # 10+ themes, all transparent, Tokyo Night Storm default
  fzf-lua.lua                  # Fuzzy finder (largest config, ~3300 lines)
  git.lua                      # LOADER: calls git.workflow.setup(), returns git/ specs
  git/                         # Git UI plugin specs (gitsigns, diffview, flog, fugitive, gitlab)
  octo.lua                     # GitHub issues/PRs (~2200 lines)
  opencode.lua                 # Primary AI agent bridge (HTTP + SSE to OpenCode server)
  pi.lua                       # pi.nvim — lightweight one-shot asks / selection edits
  sidekick.lua                 # sidekick.nvim — Copilot NES / CLI assist
  trace.lua                    # Vendored trace.nvim spec (value-origin motion)
  videre.lua                   # JSON/YAML/TOML interactive graph explorer
  csvview.lua                  # CSV/TSV aligned view
  ...                          # 30+ more plugin files

lua/format.lua                 # Treesitter-aware gq/gw for injected languages
lua/lsp-hierarchy.lua          # LSP type-hierarchy utilities
lua/scroll-diagnose.lua        # :luafile helper to bisect scroll-perf regressions

trace.nvim/lua/trace/init.lua  # Vendored plugin: trace a value up its call stack (LSP+treesitter)
ftplugin/, syntax/             # Garmin Connect IQ / Monkey-C filetype + syntax support
tests/parley_review_spec.lua   # Headless test for parley review parsing
.github/workflows/ci.yml       # CI: Lazy sync, headless startup, health, parley test
```

## AGENTS.md Hierarchy

This repo layers per-directory `AGENTS.md` guides on top of this file. When editing, read the deepest applicable one:

| File | Scope |
|------|-------|
| `AGENTS.md` (root) | Global rules, workflow contract, beads, validation |
| `lua/AGENTS.md` | Lua module style + runtime conventions |
| `lua/config/AGENTS.md` | Core config, keymaps, autocmds, agent bridges |
| `lua/git/AGENTS.md` | Custom Git workflow modules |
| `lua/parley/AGENTS.md` | Parley review tooling |
| `lua/plugins/AGENTS.md` | lazy.nvim plugin specs |
| `lua/plugins/git/AGENTS.md` | Git UI plugin integrations |
| `tests/AGENTS.md` | Headless Neovim tests |

## Conventions

### Plugin Specs
- **One plugin per file** in `lua/plugins/` (exception: `core.lua` bundles shared deps)
- Use lazy.nvim spec format: `{ "owner/repo", opts = {}, config = function() end }`
- Declare `dependencies` for load-order correctness
- Default `lazy = false`; use `event`, `ft`, `cmd`, or `keys` for lazy-loading
- Pin to `version = false` (latest commit), not tagged releases; `lazy-lock.json` records the actual pins
- Vendored/local plugins use `dir = vim.fn.stdpath("config") .. "/<name>"` (see `trace.lua`)

### Git Module Split
- **Logic** (headless-testable, no UI) lives in `lua/git/`
- **UI plugin specs** live in `lua/plugins/git/`; `lua/plugins/git.lua` is a loader that runs `git.workflow.setup()` and aggregates the specs
- Don't duplicate keymaps between the two layers

### Keymaps
- Leader: `<Space>`, Local leader: `\`
- Groups: `<leader>a` AI, `<leader>c` Code, `<leader>f` Find, `<leader>g` Git, `<leader>h` Hunks, `<leader>J` graph/JSON, `<leader>l` LSP, `<leader>o` Obsidian, `<leader>O` Octo, `<leader>y` Yank
- Always include `desc` for which-key discovery
- Scroll is swapped: `<C-d>` = UP, `<C-f>` = DOWN
- Global/editor keymaps go in `keymaps.lua`; plugin-specific keymaps go in that plugin's spec file

### LSP
- Nix-first: LSPs come from the Nix devShell, NOT Mason
- `get_lsp_cmd()` resolves full binary path via `vim.fn.exepath()`
- Auto-import organization on save for Go/Python/TypeScript
- Codelens auto-refresh (debounced)
- Inlay hints enabled by default
- Skip expensive LSP ops in diff buffers (`is_diff_buf()` guard)

### Themes
- Default: Tokyo Night Storm (priority 1000)
- ALL themes use `transparent = true` (terminal provides background)
- `autocmds/styling.lua` applies consistent italics/bold after every ColorScheme event
- Float backgrounds linked to Normal (no bg) for transparency

### Lua Style
- Module pattern: `local M = {} ... return M` for shared modules
- Keep plugin specs under `lua/plugins/`; keep reusable runtime helpers in domain dirs (`lua/config`, `lua/git`, `lua/parley`)
- Augroup helper: project-prefixed name with `clear = true`
- Debouncing: `vim.uv.new_timer()` for async/expensive operations
- Error handling: `pcall()` around optional plugin/LSP integrations that can fail at startup
- `local opt = vim.opt`, `local keymap = vim.keymap.set` at file top
- LuaLS annotations (`---@param`, `---@class`) on shared modules; analyzer config in `.emmyrc.json`

## Rules

- NEVER add Mason or mason-lspconfig. LSPs are Nix-managed.
- NEVER set opaque backgrounds on floats/popups. Transparency is enforced.
- ALWAYS add `desc` to keymaps. Which-key depends on it.
- ALWAYS use lazy.nvim spec format. No manual `require("plugin").setup()` in specs.
- ALWAYS check for keymap conflicts before adding new bindings.
- ALWAYS run health/startup validation after LSP or runtime changes (see Testing).
- Plugin-specific keymaps go in the plugin's spec file, not `keymaps.lua`.
- Keep Git workflow logic in `lua/git/`; keep only UI setup in `lua/plugins/git/`.

## Claude Code / AI Integration

- **Hotreload** (`config/hotreload.lua`): watches project files, auto-reloads visible buffers when an agent edits them; `autoread` is on so external changes are picked up immediately
- **State Bridge** (`config/claude-bridge.lua`): writes diagnostics/focus/git to `/tmp/nvim-claude-bridge/{hash}/state.json` for the dotfiles harness to consume
- **OpenCode** (`plugins/opencode.lua` + `config/opencode_*.lua`): primary stateful agent bridge over HTTP/SSE to the launchd-managed OpenCode server (port 4096); pickers browse session history
- **Pi** (`plugins/pi.lua`): lightweight one-shot asks / selection edits — not the primary workflow
- **Sidekick** (`plugins/sidekick.lua`): Copilot NES / CLI assist for learning-oriented flows
- **Skill** (`.claude/skills/neovim/SKILL.md`): guided workflow for adding plugins/keymaps/LSP + debugging this config

### Workflow contract
- Treat Neovim as a context router into OpenCode and the dotfiles hook system, not a separate orchestration layer
- Prefer one delivery harness per task: OpenCode primary, Pi for quick edits, Sidekick for assist
- Treat diagnostics, quickfix, and git diff as the review plane before considering work complete
- `.plan.md` (when present) is the control plane for the active task; keep it aligned with the worktree
- Issue tracking uses beads (`bd`): `bd ready`, `bd show <id>`, `bd update <id> --status in_progress`, `bd close <id>`; `bd dolt push` when issue state changed

## Testing Changes

CI (`.github/workflows/ci.yml`) runs these under `NVIM_APPNAME=nvim-mini`:

```bash
# Syntax check an edited Lua file
luac -p lua/plugins/new-plugin.lua

# Startup validation
nvim --headless +qa

# Custom project health check (hotreload, bridge, etc.)
nvim --headless "+checkhealth nvim_mini" +qa

# Verify lazy.nvim can parse/sync specs
nvim --headless "+Lazy! sync" +qa
nvim --headless -c "lua require('lazy').health()" -c "qa"

# Parley review tooling test
nvim --headless -l tests/parley_review_spec.lua
```

Run `luac -p` on edited standalone Lua files, `nvim --headless +qa` after any startup-affecting change, and the `nvim_mini` health check after bridge/LSP/runtime changes.

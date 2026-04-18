# Neovim Configuration (nvim-mini)

> Personal Neovim config. Standalone repo, NOT part of dotfiles. Symlinked to `~/.config/nvim`.

## Structure

```
init.lua                    # Entry point: leader keys, lazy.nvim bootstrap, disable builtins
lua/config/
  options.lua               # Editor settings (numbers, tabs=2, OSC-52 clipboard, diff opts)
  keymaps.lua               # Mappings + git permalink utilities
  autocmds.lua              # Orchestrates autocmd submodules, auto-save, transparent floats
  autocmds/lsp.lua          # Import organization, doc highlight, codelens, inlay hints
  autocmds/styling.lua      # Theme-consistent italics/bold, Blink highlight colors
  hotreload.lua             # File watcher for Claude Code integration (debounced 100ms)
  claude-bridge.lua         # Writes editor state to /tmp/nvim-claude-bridge/
lua/plugins/                # One file per plugin (lazy.nvim specs)
  core.lua                  # Shared deps: plenary, nui, devicons, fzf
  lsp.lua                   # Nix-aware LSP (no Mason) + K8s schema routing
  colorschemes.lua          # 10+ themes, all transparent, Tokyo Night Storm default
  fzf-lua.lua               # Fuzzy finder (largest config: ~3000 lines)
  git.lua                   # Fugitive + custom git commands (~2500 lines)
  octo.lua                  # GitHub issues/PRs (~1100 lines)
  ...                       # 40+ more plugin files
lua/format.lua              # Treesitter-aware gq/gw for injected languages
lua/lsp-hierarchy.lua       # LSP type hierarchy utilities
```

## Conventions

### Plugin Specs
- **One plugin per file** in `lua/plugins/` (exception: `core.lua` bundles shared deps)
- Use lazy.nvim spec format: `{ "owner/repo", opts = {}, config = function() end }`
- Declare `dependencies` for load-order correctness
- Default `lazy = false`; use `event`, `ft`, `cmd`, or `keys` for lazy-loading
- Pin to `version = false` (latest commit), not tagged releases

### Keymaps
- Leader: `<Space>`, Local leader: `\`
- Groups: `<leader>a` AI, `<leader>c` Code, `<leader>f` Find, `<leader>g` Git, `<leader>h` Hunks, `<leader>o` Obsidian, `<leader>O` Octo, `<leader>y` Yank
- Always include `desc` for which-key discovery
- Scroll is swapped: `<C-d>` = UP, `<C-f>` = DOWN

### LSP
- Nix-first: LSPs come from Nix devShell, NOT Mason
- `get_lsp_cmd()` resolves full binary path via `vim.fn.exepath()`
- Auto-import organization on save for Go/Python/TypeScript
- Codelens auto-refresh (debounced 500ms)
- Inlay hints enabled by default
- Skip expensive LSP ops in diff buffers (`is_diff_buf()` guard)

### Themes
- Default: Tokyo Night Storm (priority 1000)
- ALL themes use `transparent = true` (terminal provides background)
- `autocmds/styling.lua` applies consistent italics/bold after every ColorScheme event
- Float backgrounds linked to Normal (no bg) for transparency

### Lua Style
- Module pattern: `local M = {} ... return M` for shared modules
- Augroup helper: `augroup(name)` with project prefix + `clear = true`
- Debouncing: `vim.uv.new_timer()` for async/expensive operations
- Error handling: `pcall()` around LSP calls to prevent crashes
- `local opt = vim.opt`, `local keymap = vim.keymap.set` at file top

## Rules

- NEVER add Mason or mason-lspconfig. LSPs are Nix-managed.
- NEVER set opaque backgrounds on floats/popups. Transparency is enforced.
- ALWAYS add `desc` to keymaps. Which-key depends on it.
- ALWAYS use lazy.nvim spec format. No manual `require("plugin").setup()`.
- ALWAYS check for keymap conflicts before adding new bindings.
- ALWAYS test with `:checkhealth` after LSP changes.
- Plugin-specific keymaps go in the plugin's spec file, not `keymaps.lua`.
- Global/editor keymaps go in `keymaps.lua`.

## Claude Code Integration

- **Hotreload** (`hotreload.lua`): Watches project files, auto-reloads visible buffers when Claude edits them
- **State Bridge** (`claude-bridge.lua`): Writes diagnostics/focus/git to `/tmp/nvim-claude-bridge/{hash}/state.json`
- **autoread**: Enabled so external file changes are picked up immediately

## AI Workflow

- Workflow contract: `.claude/context/workflows.md`
- Quick cheat sheet: `.claude/context/ai-cheatsheet.md`
- Practical recipes: `.claude/context/ai-recipes.md`
- `.plan.md` is the control plane for the active task; keep it aligned with the worktree when direction changes
- Prefer one delivery harness per task; use `CodeCompanion` for learning and routing, `agentic.nvim` for investigation, and `claude-code` / `opencode` for execution
- Treat Neovim as a context router into the surrounding hook-driven dotfiles system, not as a separate orchestration layer
- Treat diagnostics, quickfix, and git diff as the review plane before considering work complete

## Testing Changes

```bash
# Syntax check a Lua file
luac -p lua/plugins/new-plugin.lua

# Validate from command line
nvim --headless -c "checkhealth" -c "qa" 2>&1

# Check lazy.nvim can parse specs
nvim --headless -c "lua require('lazy').health()" -c "qa" 2>&1
```

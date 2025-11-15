# Neovim Configuration Troubleshooting Guide

Quick reference for common issues and their solutions.

---

## Table of Contents

1. [LSP Issues](#lsp-issues)
2. [Treesitter Issues](#treesitter-issues)
3. [Nix Integration Issues](#nix-integration-issues)
4. [Quick Diagnostic Commands](#quick-diagnostic-commands)
5. [Important File Locations](#important-file-locations)

---

## LSP Issues

### Issue: No Type Hints or Semantic Highlighting

**Symptoms:**
- LSPs show in `:LspInfo` under "Enabled Configurations" but not "Active Clients"
- No inlay hints for types in Python, Go, or other languages
- No semantic token highlighting

**Common Causes & Solutions:**

#### 1. Missing `--stdio` Flag (Node.js-based LSPs)

**Affected LSPs:**
- `docker-langserver`
- `docker-compose-langserver`
- `yaml-language-server`
- `vscode-json-language-server`
- `taplo` (requires `lsp stdio` subcommand)

**Error in LSP log:**
```
Error: Connection input stream is not set. Use arguments of createConnection or set command line parameters: '--node-ipc', '--stdio' or '--socket={number}'
```

**Fix:**
Edit `~/neovim/lua/plugins/lsp.lua` and wrap the cmd in a function:

```lua
-- WRONG ❌
dockerls = {
  cmd = get_lsp_cmd("docker-langserver"),
  capabilities = capabilities,
},

-- CORRECT ✅
dockerls = {
  cmd = function()
    local cmd = get_lsp_cmd("docker-langserver")
    return cmd and { cmd[1], "--stdio" } or nil
  end,
  capabilities = capabilities,
},

-- Special case for taplo ✅
taplo = {
  cmd = function()
    local cmd = get_lsp_cmd("taplo")
    return cmd and { cmd[1], "lsp", "stdio" } or nil
  end,
  capabilities = capabilities,
},
```

**Verification:**
```bash
tail -100 ~/.local/state/nvim/lsp.log | grep -i "stdio"
```
Should show NO errors after fix.

---

#### 2. LSP Not Attaching to Buffer

**Diagnosis:**
1. Open the file type you're testing (`.py`, `.nix`, etc.)
2. Run `:set filetype?` - verify correct filetype is detected
3. Run `:LspInfo` - check "Active Clients" section

**If LSP shows as enabled but not active:**

**Check messages for errors:**
```vim
:messages
```

**Try manual start:**
```vim
:LspStart basedpyright  " or other LSP name
```

**Check LSP command availability:**
```bash
which basedpyright-langserver
which nil
which taplo
```

---

#### 3. Inlay Hints Not Showing

**For Python (basedpyright):**

Ensure inlay hints are configured in `~/neovim/lua/plugins/lsp.lua`:

```lua
basedpyright = {
  settings = {
    basedpyright = {
      analysis = {
        inlayHints = {
          variableTypes = true,
          functionReturnTypes = true,
        },
      },
    },
  },
},
```

**Check if inlay hints are enabled globally:**
```vim
:lua print(vim.inspect(vim.lsp.inlay_hint.is_enabled()))
```
Should return `true`.

**Manually enable inlay hints:**
```vim
:lua vim.lsp.inlay_hint.enable(true, { bufnr = 0 })
```

---

## Treesitter Issues

### Issue: Python Files Fail to Load with Query Error

**Symptoms:**
```
Error executing lua callback: Query error at 226:4. Invalid node type "except*":
  "except*"
   ^
```

**Cause:**
Outdated Python parser doesn't support Python 3.11+ `except*` syntax (exception groups).

**Diagnosis:**
```bash
ls -la ~/.local/share/nvim/site/parser/python.so
```

If this file exists but was NOT installed by nvim-treesitter, it's likely outdated.

**Solution:**

1. **Exit Neovim**

2. **Remove outdated parser:**
```bash
rm ~/.local/share/nvim/site/parser/python.so
```

3. **Restart Neovim and reinstall:**
```vim
:TSInstall python
```

4. **Verify in Neovim:**
```vim
:checkhealth nvim-treesitter
```

**If parser keeps reappearing:**
It might be managed by Nix or Homebrew. Check:
```bash
# Check if it's a symlink
ls -la ~/.local/share/nvim/site/parser/python.so

# If it's managed by Nix, you may need to update Nix packages
nix-env --upgrade
```

---

### Issue: Treesitter Parser Conflicts

**Error:**
```
Tried to uninstall parser for python! But the parser is still installed (not by nvim-treesitter)
```

**Cause:**
Parser was installed outside nvim-treesitter (Nix, Homebrew, or manual installation).

**Solution:**
1. Manually remove the parser file
2. Ensure `ensure_installed` in your treesitter config includes the language
3. Let nvim-treesitter manage the installation

**Check treesitter config:**
```lua
-- In ~/neovim/lua/plugins/treesitter.lua (or similar)
require('nvim-treesitter.configs').setup {
  ensure_installed = { "lua", "python", "javascript", ... },
}
```

---

## Nix Integration Issues

### Issue: LSPs Not Found by Neovim

**Symptoms:**
- `:LspInfo` shows "LSP not available from Nix"
- `get_lsp_cmd()` returns nil

**Diagnosis:**

1. **Check if LSP is in PATH:**
```bash
which basedpyright-langserver
which nil
which gopls
```

2. **Check direnv is loaded:**
```bash
direnv status
```

3. **Manually load Nix environment:**
```bash
cd ~
direnv allow
```

**Verify Nix environment:**
```bash
echo $PATH | tr ':' '\n' | grep nix
```
Should show `/nix/store/...` paths.

---

### Issue: Nix Environment Not Loading Automatically

**Cause:**
Direnv not configured or `.envrc` file missing/not allowed.

**Solution:**

1. **Check `.envrc` exists:**
```bash
cat ~/.envrc
```
Should contain:
```bash
use flake ./dotfiles/nix/global
```

2. **Allow direnv:**
```bash
cd ~
direnv allow
```

3. **Verify direnv hook in shell:**
```bash
# For Fish
grep direnv ~/.config/fish/config.fish

# For Zsh
grep direnv ~/.zshrc
```

Should have: `eval "$(direnv hook fish)"` or similar.

---

## Quick Diagnostic Commands

### Neovim Commands

```vim
:LspInfo                    " Check LSP status and capabilities
:messages                   " View recent error messages
:checkhealth                " Run comprehensive health check
:checkhealth nvim-treesitter " Check treesitter specifically
:TSUpdate                   " Update all treesitter parsers
:TSInstall python           " Install specific parser
:TSUninstall python         " Uninstall specific parser
:Lazy                       " Open plugin manager
:Lazy update nvim-treesitter " Update treesitter plugin
```

### Shell Commands

```bash
# Check LSP availability
which basedpyright-langserver
which nil
which gopls

# Check Nix environment
direnv status
echo $PATH | grep nix

# View LSP logs
tail -100 ~/.local/state/nvim/lsp.log
tail -f ~/.local/state/nvim/lsp.log  # Follow in real-time

# Search for specific errors
grep -i "error" ~/.local/state/nvim/lsp.log | tail -20
grep -i "stdio" ~/.local/state/nvim/lsp.log | tail -20

# Check treesitter parser installation
ls -la ~/.local/share/nvim/site/parser/
```

---

## Important File Locations

### Configuration Files

| File | Purpose |
|------|---------|
| `~/neovim/lua/plugins/lsp.lua` | LSP server configurations |
| `~/neovim/lua/config/autocmds/lsp.lua` | LSP autocommands (inlay hints, code lens, etc.) |
| `~/neovim/lua/config/options.lua` | General Neovim options |
| `~/neovim/lua/plugins/treesitter.lua` | Treesitter configuration |
| `~/dotfiles/nix/global/default.nix` | Nix global LSP packages |
| `~/dotfiles/nix/lsp-versions.nix` | LSP version specifications |
| `~/.envrc` | Direnv configuration for global Nix environment |

### Log and State Files

| File | Purpose |
|------|---------|
| `~/.local/state/nvim/lsp.log` | LSP server logs and errors |
| `~/.local/share/nvim/site/parser/` | Treesitter parser binaries |
| `~/.local/state/nvim/lazy/` | Plugin manager state |

### Nix Directories

| Directory | Purpose |
|-----------|---------|
| `/nix/store/` | Nix package store (LSP binaries) |
| `~/dotfiles/nix/global/` | Global Nix environment flake |
| `~/dotfiles/nix/project-templates/` | Per-project Nix templates |

---

## Common Fix Patterns

### Pattern 1: LSP Not Starting

1. Check `:LspInfo` - is it enabled?
2. Check `:messages` - any errors?
3. Check `which <lsp-command>` - is it in PATH?
4. Check `~/.local/state/nvim/lsp.log` - startup errors?
5. Try `:LspStart <name>` manually

### Pattern 2: Treesitter Syntax Error

1. Check `:messages` for query errors
2. Check parser location: `ls ~/.local/share/nvim/site/parser/`
3. Remove outdated parser: `rm ~/.local/share/nvim/site/parser/<lang>.so`
4. Reinstall: `:TSInstall <lang>`
5. Verify: `:checkhealth nvim-treesitter`

### Pattern 3: Nix LSP Not Found

1. Check direnv: `direnv status`
2. Allow direnv: `direnv allow` in home directory
3. Verify PATH: `echo $PATH | grep nix`
4. Test LSP command: `which <lsp-command>`
5. Reload Neovim

---

## When to Update This Guide

- After fixing a new unique issue
- When adding new LSPs to configuration
- When Nix LSP management changes
- When Neovim or plugin versions change significantly
- After any breaking changes to LSP/Treesitter setup

---

## Related Documentation

- Main README: `~/neovim/README.md` (if exists)
- Nix LSP Guide: `~/dotfiles/nix/README.md`
- Dotfiles Rules: `~/dotfiles/.claude/CLAUDE.md`

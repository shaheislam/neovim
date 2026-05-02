---
name: neovim
description: Use when adding, modifying, or debugging plugins, keymaps, LSP servers, or autocmds in the neovim config. Also use when the user says "add plugin", "fix neovim", "add keymap", or asks about neovim config structure.
argument-hint: "[action] [target] — e.g., 'add plugin telescope', 'add keymap for formatting', 'fix lsp gopls'"
---

# Neovim Config — Modify, Add, Debug

Guided workflow for safely modifying this neovim configuration. Routes to the correct file, follows conventions, and validates changes.

## Arguments

- `$ARGUMENTS` — Natural language description of what to do. Examples:
  - `add plugin neo-tree` → Phase 1 (Add Plugin)
  - `add keymap for format on save` → Phase 2 (Add Keymap)
  - `configure gopls` → Phase 3 (LSP)
  - `fix colorscheme bleeding` → Phase 4 (Debug)
  - No args → show this help and ask what to do

## Phase 1: Add Plugin

### Step 1 — Check for conflicts

```bash
# Check if plugin or similar functionality already exists
grep -r "PLUGIN_NAME_OR_KEYWORD" lua/plugins/ --include="*.lua" -l
# Check lazy-lock for existing installation
grep "PLUGIN_NAME" lazy-lock.json
```

If the plugin or equivalent functionality already exists, report it and ask whether to replace or extend.

### Step 2 — Create the plugin spec

Create `lua/plugins/<plugin-name>.lua` with this template:

```lua
-- <Plugin Description>
-- <Why this plugin exists / what it replaces>

return {
  {
    "<owner>/<repo>",
    -- Lazy-loading (pick ONE appropriate trigger):
    -- event = "VeryLazy",           -- load after UI
    -- event = "BufReadPost",        -- load when opening files
    -- ft = { "go", "rust" },        -- load for specific filetypes
    -- cmd = { "CommandName" },      -- load on command
    -- keys = { ... },               -- load on keypress
    dependencies = {
      -- Only list DIRECT dependencies
    },
    opts = {
      -- Plugin configuration
    },
    -- Use config only if opts alone isn't enough:
    -- config = function(_, opts)
    --   require("<plugin>").setup(opts)
    -- end,
  },
}
```

**Rules:**
- File name = plugin name (kebab-case): `lua/plugins/neo-tree.lua`
- One plugin per file (unless tightly coupled pair)
- Always add a comment header explaining purpose
- Use `opts = {}` over `config = function()` when possible (lazy.nvim auto-calls setup)
- Declare `dependencies` — don't assume load order
- For UI plugins: add `transparent = true` or equivalent (check colorschemes.lua for pattern)

### Step 3 — Add keymaps

Plugin-specific keymaps go INSIDE the plugin spec, not in `keymaps.lua`:

```lua
keys = {
  { "<leader>xx", "<cmd>PluginCommand<cr>", desc = "Do thing" },
  { "<leader>xy", function() ... end, desc = "Do other thing" },
},
```

Before adding any keymap, check for conflicts:

```bash
# Check if the key combination is already used
grep -r '"<leader>xx"' lua/ --include="*.lua"
grep -r "'<leader>xx'" lua/ --include="*.lua"
```

**Leader groups** (stay within these):
| Prefix | Purpose | Example |
|--------|---------|---------|
| `<leader>a` | AI / OpenCode / Sidekick | `<leader>ao` OpenCode, `<leader>as` Sidekick |
| `<leader>c` | Code / LSP actions | `<leader>ca` code action |
| `<leader>f` | Find / Files (fzf) | `<leader>ff` find files |
| `<leader>g` | Git operations | `<leader>gs` git status |
| `<leader>h` | Git hunks | `<leader>hs` stage hunk |
| `<leader>m` | Markdown | `<leader>mp` preview |
| `<leader>o` | Obsidian | `<leader>ot` today |
| `<leader>O` | Octo (GitHub) | `<leader>Ol` list issues |
| `<leader>q` | Quickfix / Quit | `<leader>q` quit |
| `<leader>s` | Sessions | `<leader>ss` save |
| `<leader>w` | Save / Window | `<leader>w` save |
| `<leader>y` | Yank / Copy | `<leader>yl` permalink |

New plugin groups: pick an UNUSED `<leader>` prefix. Check which-key.lua for registered groups.

### Step 4 — Validate

```bash
# Syntax check
luac -p lua/plugins/<new-file>.lua

# Verify lazy.nvim can parse it (opens and closes nvim)
nvim --headless -c "lua print(vim.inspect(require('lazy.core.config').spec))" -c "qa" 2>&1 | head -20
```

## Phase 2: Add Keymap

### Step 1 — Determine scope

- **Global/editor keymap** (not plugin-specific) → edit `lua/config/keymaps.lua`
- **Plugin-specific keymap** → edit the plugin's spec file in `lua/plugins/`
- **LSP keymap** (attached per-buffer) → edit `lua/config/autocmds/lsp.lua`

### Step 2 — Check for conflicts

```bash
grep -rn "KEY_COMBO" lua/ --include="*.lua"
```

### Step 3 — Add the keymap

Use the correct pattern for the target file:

```lua
-- In keymaps.lua:
keymap("n", "<leader>xx", "<cmd>Command<cr>", { desc = "Description" })

-- In plugin spec (keys field):
keys = {
  { "<leader>xx", "<cmd>Command<cr>", desc = "Description" },
}

-- In LSP autocmd (buffer-local):
vim.keymap.set("n", "<leader>xx", function() ... end, { buffer = bufnr, desc = "Description" })
```

**ALWAYS include `desc`** — which-key depends on it for discoverability.

**Scroll warning**: `<C-d>` is UP, `<C-f>` is DOWN in this config (swapped in keymaps.lua).

## Phase 3: Configure LSP

### Key constraint: Nix-first, no Mason

LSP servers come from the Nix devShell. Never add Mason or mason-lspconfig.

### Step 1 — Add server config

Edit `lua/plugins/lsp.lua`. Add to the `servers` table inside the config function:

```lua
-- Example: adding a new LSP
servers.new_server = {
  cmd = get_lsp_cmd("new-server-binary"),
  settings = {
    -- Server-specific settings
  },
}
```

Use `get_lsp_cmd()` to resolve the binary path — it returns `nil` if not found, which gracefully skips setup.

### Step 2 — Add format-on-save (if needed)

In `lua/config/autocmds/lsp.lua`, the `format_on_save_servers` table controls which LSPs format on save:

```lua
local format_on_save_servers = {
  gopls = true,
  rust_analyzer = true,
  -- Add your server here
}
```

### Step 3 — Verify

```bash
# Check if binary is available
which new-server-binary

# Open a file of that type and check
nvim --headless -c "e test.ext" -c "lua print(vim.inspect(vim.lsp.get_clients()))" -c "qa" 2>&1
```

## Phase 4: Debug

### Common issues

| Symptom | Check |
|---------|-------|
| Plugin not loading | `lazy-lock.json` has entry? `:Lazy` shows it? |
| Keymap not working | Conflict? Check `grep -r "KEY" lua/` |
| LSP not attaching | Binary on PATH? `which server-name` |
| Theme colors wrong | `autocmds/styling.lua` overriding? Float bg set? |
| Slow scrolling | `is_diff_buf()` guard missing? `synmaxcol` issue? |
| Hotreload not working | `hotreload.lua` watcher running? File pattern excluded? |

### Diagnostic commands

```bash
# Full health check
nvim --headless -c "checkhealth" -c "qa" 2>&1

# Check specific plugin
nvim --headless -c "checkhealth <plugin>" -c "qa" 2>&1

# List loaded plugins
nvim --headless -c "lua for _,p in ipairs(require('lazy').plugins()) do print(p.name, p._.loaded) end" -c "qa" 2>&1

# Check for Lua errors on startup
nvim --headless -c "qa" 2>&1
```

## Common Mistakes

- **Adding Mason**: This config uses Nix for LSPs. Mason will conflict.
- **Opaque float backgrounds**: All UI must be transparent. Use `bg = "NONE"` or link to Normal.
- **Keymaps without `desc`**: Which-key won't show them. Always add descriptions.
- **Editing keymaps.lua for plugin keys**: Plugin keymaps belong in the plugin's spec file.
- **Forgetting dependencies**: If plugin A requires plugin B, declare it in `dependencies`.
- **Using `require("plugin").setup()`**: Use `opts = {}` in the lazy.nvim spec instead.

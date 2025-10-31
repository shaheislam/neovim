# Migration Summary - nvim-mini

This document summarizes what was migrated from your main Neovim (LazyVim) config to nvim-mini.

## Migrated Components

### ✅ Core Dependencies
- **plenary.nvim** - Lua utilities
- **nui.nvim** - UI components
- **nvim-web-devicons** - File icons
- **fzf** - Fuzzy finder binary

### ✅ Colorschemes (11 themes)
All your colorschemes with fzf-lua picker integration:
- onedark (default)
- catppuccin-mocha
- tokyonight-storm
- kanagawa
- rose-pine
- nightfox
- github-theme
- gruvbox-material
- everforest
- nord
- cyberdream

**Access:** `:FzfLua colorschemes` or your custom keybinds

### ✅ Quickfix Enhancements
- **quicker.nvim** - Better quickfix management
- **nvim-pqf** - Pretty quickfix formatting
- **nvim-bqf** - Enhanced filtering

**Keymaps:**
- `<leader>qq` - Toggle quickfix
- `<leader>ql` - Toggle loclist
- `]q` / `[q` - Next/Previous quickfix item
- `]Q` / `[Q` - First/Last quickfix item

### ✅ Viewport
Modal window management for resizing and navigation.

**Keymaps:**
- `<leader>wv` - Viewport Resize Mode
- `<leader>wn` - Viewport Navigate Mode
- `<leader>ws` - Viewport Select Mode

### ✅ Blink.cmp
Fast completion engine with:
- LSP completion
- Path completion
- Buffer completion
- Snippet support (friendly-snippets)
- Auto-brackets
- Signature help

**Keymaps:**
- `<Tab>` - Accept completion
- `<S-Tab>` - Select previous
- `Ctrl+space` - Trigger completion/docs
- `Ctrl+y` - Accept (default preset)
- `Ctrl+n/p` - Navigate

### ✅ Oil.nvim
File browser with fzf-lua integration (required by fzf-lua config).

**Keymaps:**
- `<leader>e` / `<leader>fe` - Open Oil
- `-` - Open parent directory
- `<leader>ff` (in Oil) - Find files in Oil directory
- `<leader>fg` (in Oil) - Live grep in Oil directory

**Features:**
- Auto-cd to file directory
- Show hidden files
- Delete to trash
- Sync with working directory

### ✅ Lualine
Beautiful and informative statusline (matches LazyVim default).

**Sections:**
- **Left**: Mode, git branch
- **Center**: Diagnostics (errors/warnings/hints), file icon, filename with path
- **Right**: Git diff stats (from gitsigns), progress %, location, time

**Features:**
- Auto-adapts to current colorscheme
- Global statusline (single bar across all windows)
- Gitsigns integration for real-time git stats
- Nerd Font icons for diagnostics and git
- Extensions for lazy.nvim, quickfix, and oil.nvim

### ✅ Which-key
Popup showing available keybindings as you type.

**Configuration:**
- Modern preset with rounded borders
- 300ms delay before popup appears
- Shows marks, registers, spelling suggestions
- Operator, motion, and text object help
- Window management hints

**Key Groups Registered:**
- `<leader>f` - Find/File operations
- `<leader>g` - Git operations
- `<leader>h` - Git hunks
- `<leader>q` - Quickfix/quit
- `<leader>w` - Window/viewport
- Navigation hints for `]c`, `[c`, `]q`, `[q`, etc.

**Features:**
- Automatically shows available keybindings
- Helps discover new shortcuts
- Integrates with all plugins
- Search functionality with `/`

### ✅ Gitsigns.nvim
Git integration with visual indicators and inline operations.

**Hunk Navigation:**
- `]c` / `[c` - Next/Previous hunk (wrap enabled)
- `]C` / `[C` - First/Last hunk
- `]p` / `[p` - Next/Previous hunk with preview
- `]g` / `[g` - Next/Previous non-contiguous hunk
- `]s` / `[s` - Next/Previous staged hunk only
- `]u` / `[u` - Next/Previous unstaged hunk only

**Hunk Actions:**
- `<leader>hs` - Stage hunk
- `<leader>hr` - Reset hunk
- `<leader>hS` - Stage entire buffer
- `<leader>hu` - Undo stage hunk
- `<leader>hR` - Reset entire buffer
- `<leader>hp` - Preview hunk
- `<leader>hi` - Preview hunk inline
- `<leader>hP` - Preview and stage with confirmation

**Blame & Diff:**
- `<leader>hb` - Blame line (full)
- `<leader>hB` - Toggle blame line
- `<leader>hv` - Blame buffer (full)
- `<leader>hd` - Diff this
- `<leader>hD` - Diff this ~
- `<leader>hc` - Diff against custom revision

**Advanced Features:**
- `<leader>ht` - Toggle deleted lines as virtual text
- `<leader>hy` - Yank deleted lines from current hunk
- `<leader>hC` - Change diff base
- `<leader>hE` - Reset diff base to index
- `<leader>hF` - Reset buffer to revision (interactive)

**Toggle Features:**
- `<leader>hn` - Toggle line number highlighting
- `<leader>hl` - Toggle line highlighting
- `<leader>hw` - Toggle word diff
- `<leader>hg` - Toggle git signs

**Quickfix Integration:**
- `<leader>hq` - Send all hunks to quickfix
- `<leader>hQ` - Send hunks from all buffers to quickfix
- `<leader>hL` - Send hunks to location list

**Text Objects:**
- `ih` - Inside hunk (only changed lines)
- `ah` - Around hunk (with 2 lines context above/below)

**Visual Mode:**
- `<leader>hs` - Stage selected lines
- `<leader>hr` - Reset selected lines
- `<leader>hx` - Select all contiguous hunks
- `<leader>hX` - Select only current hunk

**Features:**
- Custom subscript count characters (₁₂₃₄₅₆₇₈₉₊)
- Distinct signs for staged vs unstaged changes
- Line number highlighting (numhl)
- Word-level diff highlighting
- Current line blame with virtual text
- Custom highlight colors (persistent across colorscheme changes)

### ✅ FZF-Lua (Full Config - 1836 lines!)
Your complete fzf-lua configuration including:
- Directory history management
- Scope toggling (Local/Git/Parent/Buffer)
- Zoxide integration
- Custom keymaps
- All 40+ helper functions
- File/grep with history
- **Enhanced colorscheme picker** (95% window size with 70% preview)

**Key Features:**
- Directory-specific search history
- Navigate history with Ctrl+h/l
- Scope switching with Ctrl+g/o/p/b
- Browse folders with Ctrl+f
- History search with Ctrl+r
- **Larger colorscheme picker** for better preview visualization

### ✅ Custom Autocmds & Styling
- **Styling system** - Consistent italic/bold across themes
- **inccommand highlights** - Bold search/substitute preview
- **Auto-save** - On focus lost and buffer switch
- **Trim whitespace** - On save (excludes markdown/diff)
- **Highlight yank** - Visual feedback on yank
- **Restore cursor** - Remember last position
- **Auto-resize splits** - On terminal resize

### ✅ Enhanced Options
- `inccommand = "split"` - Live substitute preview
- `clipboard = "unnamedplus"` - System clipboard
- **Hybrid line numbers** - Both absolute and relative displayed side by side via `statuscolumn`
- Smart search, indent
- And all your custom settings

### ✅ Enhanced Keymaps
- Quickfix navigation (]q, [q, ]Q, [Q)
- Centered search (n, N with zzzv)
- Window navigation (Ctrl+hjkl)
- Better scrolling (Ctrl+d/u centered)
- Viewport modes (<leader>w*)

## What's NOT Migrated (Yet)

These were not requested:
- Treesitter
- LSP servers (mason, lspconfig)
- Additional Git plugins (diffview, git-conflict, fugitive, rhubarb)
- DAP (debugging)
- Terminal (toggleterm, snacks)
- Writing plugins
- Language-specific plugins

## File Structure

```
~/.config/nvim-mini/
├── init.lua
├── README.md
├── MIGRATION.md (this file)
└── lua/
    ├── config/
    │   ├── options.lua
    │   ├── keymaps.lua
    │   ├── autocmds.lua
    │   └── autocmds/
    │       └── styling.lua
    └── plugins/
        ├── core.lua
        ├── colorschemes.lua
        ├── quickfix.lua
        ├── viewport.lua
        ├── oil.lua
        ├── blink-cmp.lua
        ├── lualine.lua
        ├── which-key.lua
        ├── git.lua
        └── fzf-lua.lua (1836 lines!)
```

## Usage

Launch nvim-mini:
```bash
nvm
```

Or explicitly:
```bash
NVIM_APPNAME=nvim-mini nvim
```

Your main LazyVim config remains at:
```bash
nvim
```

## Testing

On first launch:
1. Lazy.nvim will auto-install
2. All plugins will be downloaded
3. You'll see "nvim-mini loaded" notification
4. Check the statusbar at the bottom - you should see lualine with mode, branch, filename, etc.
5. Try `:FzfLua colorschemes` to test fzf-lua
6. Try `]q` after running a command that populates quickfix
7. Try `<Tab>` in insert mode for completions
8. Press `<leader>` and wait 300ms to see which-key popup

## Data Directories

Completely isolated from main config:
- **Data:** `~/.local/share/nvim-mini/`
- **State:** `~/.local/state/nvim-mini/`
- **Cache:** `~/.cache/nvim-mini/`

## Next Steps

If you want to add more plugins:
1. Identify plugin from main config
2. Create or edit plugin file in `lua/plugins/`
3. Test with `nvm`
4. Iterate

Happy minimalist Vimming! 🚀

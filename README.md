# nvim-mini

A minimal Neovim configuration for selective plugin migration from LazyVim.

## Usage

Launch with the `nvm` alias:
```bash
nvm
```

Or explicitly:
```bash
NVIM_APPNAME=nvim-mini nvim
```

## Structure

```
~/.config/nvim-mini/
├── init.lua                  # Main config with lazy.nvim bootstrap
├── lua/
│   ├── config/
│   │   ├── options.lua      # Core Neovim settings
│   │   └── keymaps.lua      # Essential keymaps
│   └── plugins/             # Plugin specifications (empty, ready for migration)
└── README.md
```

## Separate from LazyVim

This config is completely isolated from your main `~/.config/nvim/` (LazyVim):
- Separate data directory: `~/.local/share/nvim-mini/`
- Separate state: `~/.local/state/nvim-mini/`
- Separate cache: `~/.cache/nvim-mini/`
- No interference between configs

## Adding Plugins

Create plugin files in `lua/plugins/`:

```lua
-- lua/plugins/example.lua
return {
  "author/plugin-name",
  opts = {
    -- plugin options
  },
}
```

## Migration Process

1. Identify plugins from main config to migrate
2. Create plugin file in `lua/plugins/`
3. Launch `nvm` to test
4. Iterate until satisfied

## Reset

To start fresh, delete the data directory:
```bash
rm -rf ~/.local/share/nvim-mini/
```

# nvim-mini

A personal Neovim configuration with lazy.nvim plugin specs, custom editor workflows, and Claude Code integration.

## Usage
ghgh gjjgjg 
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
│   ├── config/              # Core config modules and custom runtime helpers
│   ├── plugins/             # lazy.nvim plugin specs
│   ├── parley/              # Review tooling for markdown workflows
│   └── nvim_mini/health.lua # Custom :checkhealth entry point
├── tests/                   # Headless Neovim tests
├── .github/workflows/ci.yml # Startup, health, and test validation
└── README.md
```

## Separate from LazyVim

This config is completely isolated from your main `~/.config/nvim/` (LazyVim):
- Separate data directory: `~/.local/share/nvim-mini/`
- Separate state: `~/.local/state/nvim-mini/`
- Separate cache: `~/.cache/nvim-mini/`
- No interference between configs

## Validation

```bash
nvim --headless +qa
nvim --headless "+checkhealth nvim_mini" +qa
nvim --headless -l tests/parley_review_spec.lua
```

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

## Notes

- This repo is no longer an empty migration scaffold; most day-to-day config now lives in `lua/config/` and `lua/plugins/`.
- Custom runtime modules should expose a `setup()` entrypoint, validate any user config, and surface diagnostics through `:checkhealth nvim_mini` when practical.

## Reset

To start fresh, delete the data directory:
```bash
rm -rf ~/.local/share/nvim-mini/
```

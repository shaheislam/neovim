# Plugins Agent Guide

Rules for `~/neovim/lua/plugins`.

## lazy.nvim Specs

- Use one plugin spec per file, except `core.lua` for shared dependencies.
- Use lazy.nvim spec format: `{ "owner/repo", opts = {}, config = function() end }`.
- Declare `dependencies` for load-order correctness.
- Default to `lazy = false`; use `event`, `ft`, `cmd`, or `keys` only when lazy-loading is intentional.
- Pin with `version = false` rather than tagged releases unless a plugin requires otherwise.

## Rules

- Never add Mason or `mason-lspconfig`; LSPs come from Nix.
- Preserve transparent backgrounds for floats and popups.
- Add `desc` to all keymaps.
- Check for keymap conflicts before adding bindings.

## Validation

- Run `luac -p lua/plugins/<file>.lua` for edited plugin specs.
- Run `nvim --headless -c "lua require('lazy').health()" -c "qa"` after plugin spec changes.
- Run `nvim --headless +qa` for startup validation.

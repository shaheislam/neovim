# Lua Agent Guide

Rules for `~/neovim/lua`.

## Style

- Use Lua module style with `local M = {}` and `return M` for shared modules.
- Keep plugin specs under `lua/plugins/`; keep reusable runtime helpers under domain directories such as `lua/config`, `lua/git`, or `lua/parley`.
- Prefer `pcall()` around optional plugin or LSP integrations that can fail at startup.
- Use `vim.uv.new_timer()` for debounced async work.

## Validation

- Run `luac -p <file>.lua` for edited standalone Lua files when possible.
- Run `nvim --headless +qa` after startup-affecting changes.
- Run `nvim --headless "+checkhealth nvim_mini" +qa` after runtime or health changes.

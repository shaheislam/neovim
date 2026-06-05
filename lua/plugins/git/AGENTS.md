# Git Plugin Agent Guide

Rules for `~/neovim/lua/plugins/git`.

## Scope

- Keep plugin setup for Git UI integrations here.
- Keep reusable Git workflow logic in `lua/git/`.
- Do not duplicate keymaps already provided by broader Git plugin specs.

## Validation

- Run `luac -p lua/plugins/git/<file>.lua` for edited files.
- Run `nvim --headless +qa` after plugin setup changes.

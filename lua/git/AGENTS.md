# Git Workflow Agent Guide

Rules for `~/neovim/lua/git`.

## Scope

- This directory contains reusable Git workflow modules used by Neovim commands and plugins.
- Keep UI plugin setup in `lua/plugins/git/`; keep workflow logic here.
- Prefer small composable functions that can be exercised from headless Neovim.

## Validation

- Run `luac -p lua/git/<file>.lua` for edited files.
- Run `nvim --headless +qa` after workflow integration changes.

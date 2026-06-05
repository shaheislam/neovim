# Parley Agent Guide

Rules for `~/neovim/lua/parley`.

## Review Tooling

- Preserve review marker parsing for `㊷[text]` and optional `{question}` blocks.
- Keep diagnostics and quickfix output aligned with `tests/parley_review_spec.lua`.
- Prefer pure collection/formatting functions that are easy to test headlessly.

## Validation

- Run `luac -p lua/parley/<file>.lua` for edited files.
- Run `nvim --headless -l tests/parley_review_spec.lua` after Parley changes.

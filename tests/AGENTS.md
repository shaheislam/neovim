# Tests Agent Guide

Rules for `~/neovim/tests`.

## Test Style

- Tests run under headless Neovim.
- Keep tests deterministic and independent of local UI state.
- Add focused tests near the behavior being changed rather than broad startup assertions.

## Validation

- Run `nvim --headless -l tests/parley_review_spec.lua` for Parley review tests.
- Run `nvim --headless +qa` for startup sanity.
- Run `nvim --headless "+checkhealth nvim_mini" +qa` for health checks.

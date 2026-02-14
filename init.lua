-- Minimal Neovim Configuration (nvim-mini)
-- A clean slate for selective plugin migration from LazyVim

-- Enable faster Lua module loading (Neovim 0.9+)
if vim.loader then vim.loader.enable() end

-- Set leader key before lazy.nvim loads
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Bootstrap lazy.nvim plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Disable built-in plugins early (before runtime sources them)
-- lazy.nvim's disabled_plugins handles gzip/tar/zip/tohtml/tutor,
-- but these need explicit guards to prevent $VIMRUNTIME/plugin/ sourcing
vim.g.loaded_netrw = 1          -- disable netrw library
vim.g.loaded_netrwPlugin = 1    -- oil.nvim replaces file browsing; gx is built-in since nvim 0.11
vim.g.loaded_matchparen = 1     -- blink.pairs matchparen replaces this
vim.g.loaded_2html_plugin = 1
vim.g.loaded_spellfile_plugin = 1
vim.g.loaded_rplugin = 1

-- Load core configuration
require("config.options")
require("config.keymaps")
require("config.autocmds")

-- Setup lazy.nvim with minimal plugins
require("lazy").setup({
  -- Plugins will be added here one-by-one
  spec = {
    { import = "plugins" },
  },
  defaults = {
    lazy = false,                            -- plugins load on startup by default
    version = false,                         -- use latest git commit
  },
  install = { colorscheme = { "habamax" } }, -- fallback colorscheme
  checker = { enabled = false },             -- disable automatic update checks
  performance = {
    rtp = {
disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
        -- netrwPlugin, matchparen, 2html_plugin, spellfile_plugin, rplugin
        -- are disabled via vim.g.loaded_* guards above (more reliable)
      },
    },
  },
})

-- Status message (removed - no longer needed)
-- vim.notify("nvim-mini loaded - ready for plugin migration", vim.log.levels.INFO)

-- Minimal Neovim Configuration (nvim-mini)
-- A clean slate for selective plugin migration from LazyVim

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
    lazy = false, -- plugins load on startup by default
    version = false, -- use latest git commit
  },
  install = { colorscheme = { "habamax" } }, -- fallback colorscheme
  checker = { enabled = false }, -- disable automatic update checks
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

-- Status message
vim.notify("nvim-mini loaded - ready for plugin migration", vim.log.levels.INFO)

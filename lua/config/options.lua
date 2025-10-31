-- Basic Neovim Options
-- Core editor settings for nvim-mini

local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Statuscolumn: display both absolute and relative line numbers side by side
-- %s = sign column (gitsigns, diagnostics, etc.)
-- %{v:lnum} = absolute line number
-- %{v:relnum} = relative line number
opt.statuscolumn = "%s %{v:lnum} %{v:relnum}"

-- Clipboard
opt.clipboard = "unnamedplus" -- System clipboard integration

-- Command preview
opt.inccommand = "split" -- Show command preview in split window

-- Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- UI
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

-- Splits
opt.splitbelow = true
opt.splitright = true

-- Completion
opt.completeopt = "menu,menuone,noselect"

-- Undo/Backup
opt.undofile = true
opt.backup = false
opt.swapfile = false

-- Misc
opt.mouse = "a"
opt.updatetime = 250
opt.timeoutlen = 300
opt.hidden = true

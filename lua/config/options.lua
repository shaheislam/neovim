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

-- Clipboard - Custom OSC-52 with explicit tmux passthrough
-- The built-in vim.ui.clipboard.osc52 doesn't wrap sequences for tmux correctly
local function osc52_copy(lines, regtype)
  local text = table.concat(lines, "\n")
  local encoded = vim.base64.encode(text)
  local osc = string.format("\027]52;c;%s\a", encoded)

  -- Wrap for tmux passthrough if in tmux
  if vim.env.TMUX then
    osc = string.format("\027Ptmux;\027%s\027\\", osc)
  end

  io.stdout:write(osc)
  io.stdout:flush()
end

vim.g.clipboard = {
  name = "OSC 52 (tmux)",
  copy = {
    ["+"] = osc52_copy,
    ["*"] = osc52_copy,
  },
  paste = {
    ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
    ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
  },
}
opt.clipboard = "unnamedplus" -- Use system clipboard (+ register) for all yank/delete/paste

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
opt.fillchars:append({ diff = "╱" }) -- Diagonal lines for deleted diff regions

-- Diff options for better diff visualization
opt.diffopt = {
  "internal",           -- Use internal diff library
  "filler",             -- Show filler lines for sync
  "closeoff",           -- Exit diff mode when window closes
  "context:12",         -- 12 lines of context (default: 6)
  "algorithm:histogram", -- Better than default "myers"
  "linematch:200",      -- Match lines within blocks (key improvement)
  "indent-heuristic",   -- Smarter indentation handling
}

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

-- Disable intro screen to prevent flicker when auto-opening Oil
opt.shortmess:append("I")

-- LSP Enhancements
vim.g.auto_refresh_codelens = true -- Enable auto-refresh for code lens

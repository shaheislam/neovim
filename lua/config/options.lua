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

  -- Wrap for tmux passthrough if:
  -- 1. In tmux directly ($TMUX set)
  -- 2. In SSH session (likely through tmux on local machine)
  -- 3. In Kubernetes container (kubectl exec/debug through tmux)
  local needs_tmux_wrap = vim.env.TMUX
    or vim.env.SSH_TTY
    or vim.env.KUBERNETES_SERVICE_HOST

  if needs_tmux_wrap then
    osc = string.format("\027Ptmux;\027%s\027\\", osc)
  end

  -- Use Neovim's channel API (channel 2 = stdout) for reliable output
  vim.api.nvim_chan_send(2, osc)
end

-- Paste function: use pbpaste on macOS, empty on remote (use Ctrl-V for terminal paste)
local function get_paste_fn()
  local is_remote = vim.env.SSH_TTY or vim.env.KUBERNETES_SERVICE_HOST
  if is_remote then
    -- Remote: return empty (user should use Ctrl-V for terminal paste)
    return function()
      return {}
    end
  else
    -- Local macOS: use pbpaste
    return function()
      return vim.fn.systemlist("pbpaste")
    end
  end
end

vim.g.clipboard = {
  name = "OSC 52 copy + smart paste",
  copy = {
    ["+"] = osc52_copy,
    ["*"] = osc52_copy,
  },
  paste = {
    ["+"] = get_paste_fn(),
    ["*"] = get_paste_fn(),
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

-- Auto-reload files changed outside Neovim (e.g., by Claude Code)
opt.autoread = true

-- Disable intro screen to prevent flicker when auto-opening Oil
opt.shortmess:append("I")

-- LSP Enhancements
vim.g.auto_refresh_codelens = true -- Enable auto-refresh for code lens

-- Basic Neovim Options
-- Core editor settings for nvim-mini

local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Statuscolumn: signs + right-aligned hybrid line number
-- %l = "line number column for currently drawn line" (:help statuscolumn).
-- With nu+rnu, the number column shows hybrid (:help number_relativenumber):
-- absolute on cursor line, relative elsewhere — and %l mirrors that exactly.
-- Verified on 0.11.5: cursor@10 → lnum 9→"1", 10→"10", 11→"1" (hybrid).
-- Previously "%s %{v:lnum} %{v:relnum}" (both numbers side-by-side) but %{}
-- expressions evaluate Vimscript per visible line per redraw causing scroll stutter.
opt.statuscolumn = "%s%=%l "

-- Clipboard - Custom OSC-52 with explicit tmux passthrough
-- The built-in vim.ui.clipboard.osc52 doesn't wrap sequences for tmux correctly.
-- Disable with: vim.g.clipboard_disable_osc52 = true (before this file loads)

-- Detect whether the terminal likely supports OSC 52
local function osc52_supported()
  if vim.g.clipboard_disable_osc52 then return false end
  -- Known-good: tmux, screen, xterm-family, ghostty, wezterm, alacritty, kitty
  local term = vim.env.TERM or ""
  if vim.env.TMUX or vim.env.SSH_TTY or vim.env.KUBERNETES_SERVICE_HOST or vim.env.DEVCONTAINER then
    return true -- remote contexts always need OSC52 for clipboard
  end
  return term:match("xterm") or term:match("screen") or term:match("tmux")
    or term:match("ghostty") or term:match("wezterm") or term:match("alacritty")
    or term:match("kitty") or vim.env.TERM_PROGRAM ~= nil
end

if osc52_supported() then
  local function osc52_copy(lines, regtype)
    local text = table.concat(lines, "\n")
    local encoded = vim.base64.encode(text)
    local osc = string.format("\027]52;c;%s\a", encoded)

    -- Wrap for tmux passthrough if:
    -- 1. In tmux directly ($TMUX set)
    -- 2. In SSH session (likely through tmux on local machine)
    -- 3. In Kubernetes container (kubectl exec/debug through tmux)
    -- 4. In devcontainer (docker exec through tmux)
    local needs_tmux_wrap = vim.env.TMUX
      or vim.env.SSH_TTY
      or vim.env.KUBERNETES_SERVICE_HOST
      or vim.env.DEVCONTAINER

    if needs_tmux_wrap then
      osc = string.format("\027Ptmux;\027%s\027\\", osc)
    end

    -- Use Neovim's channel API (channel 2 = stdout) for reliable output
    vim.api.nvim_chan_send(2, osc)
  end

  -- Paste function: use pbpaste on macOS, empty on remote (use Ctrl-V for terminal paste)
  local function get_paste_fn()
    local is_remote = vim.env.SSH_TTY or vim.env.KUBERNETES_SERVICE_HOST or vim.env.DEVCONTAINER
    if is_remote then
      return function() return {} end
    else
      return function() return vim.fn.systemlist("pbpaste") end
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
end
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

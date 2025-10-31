-- Essential Keymaps
-- Basic key mappings for nvim-mini

local keymap = vim.keymap.set

-- Better window navigation
keymap("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Resize windows
keymap("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase window height" })
keymap("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease window height" })
keymap("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width" })
keymap("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width" })

-- Move lines up/down
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Better indenting
keymap("v", "<", "<gv", { desc = "Indent left" })
keymap("v", ">", ">gv", { desc = "Indent right" })

-- Clear search highlighting
keymap("n", "<Esc>", ":noh<CR>", { desc = "Clear search highlighting", silent = true })

-- Save file
keymap("n", "<leader>w", ":w<CR>", { desc = "Save file" })

-- Quit
keymap("n", "<leader>q", ":q<CR>", { desc = "Quit" })

-- Global scroll direction swap (works in all buffers and windows)
-- <C-d> = scroll UP, <C-f> = scroll DOWN
local function setup_scroll_mappings()
  -- For normal buffers: neoscroll provides smooth animations
  -- For floating windows/popups (which-key, help, etc.): these keymaps provide the swap
  local modes = { "n", "v", "x" }

  for _, mode in ipairs(modes) do
    -- <C-d> scrolls UP (use native <C-u>)
    vim.keymap.set(mode, "<C-d>", "<C-u>", {
      desc = "Scroll up",
      silent = true,
      remap = true -- Allow neoscroll to intercept in normal buffers
    })

    -- <C-f> scrolls DOWN (use native <C-d>)
    vim.keymap.set(mode, "<C-f>", "<C-d>", {
      desc = "Scroll down",
      silent = true,
      remap = true -- Allow neoscroll to intercept in normal buffers
    })
  end
end

setup_scroll_mappings()

-- Search navigation (centered)
keymap("n", "n", "nzzzv", { desc = "Next search result (centered)" })
keymap("n", "N", "Nzzzv", { desc = "Previous search result (centered)" })

-- Better paste (doesn't overwrite clipboard)
keymap("x", "<leader>p", '"_dP', { desc = "Paste without yanking" })

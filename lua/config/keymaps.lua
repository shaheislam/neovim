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

-- ============================================================================
-- Yank with file path and line numbers (for Claude Code)
-- ============================================================================

-- Get git root directory
local function get_git_root()
  local git_dir = vim.fs.find(".git", { path = vim.fn.getcwd(), upward = true })[1]
  if git_dir then
    return vim.fn.fnamemodify(git_dir, ":h")
  end
  return nil
end

-- Yank selection with file path (relative or absolute)
local function yank_with_path(use_relative)
  -- Exit visual mode to set '< and '> marks
  vim.cmd('normal! "vy')

  -- Get line numbers
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Get selected lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    vim.notify("No selection", vim.log.levels.WARN)
    return
  end

  -- Get file path
  local file_path = vim.fn.expand("%:p")
  if use_relative then
    local git_root = get_git_root()
    if git_root then
      file_path = file_path:sub(#git_root + 2) -- +2 to skip trailing /
    else
      file_path = vim.fn.expand("%:.")
    end
  end

  -- Format line range
  local line_range
  if start_line == end_line then
    line_range = tostring(start_line)
  else
    line_range = string.format("%d-%d", start_line, end_line)
  end

  -- Build output: path:lines\n\ncode
  local code = table.concat(lines, "\n")
  local output = string.format("%s:%s\n\n%s", file_path, line_range, code)

  -- Copy to clipboard
  vim.fn.setreg("+", output)

  -- Notify
  local path_type = use_relative and "relative" or "absolute"
  vim.notify(string.format("Yanked %s:%s (%s)", file_path, line_range, path_type), vim.log.levels.INFO)
end

-- Visual mode keymaps for yanking with paths
keymap("v", "<leader>yr", function() yank_with_path(true) end, { desc = "Yank with relative path" })
keymap("v", "<leader>ya", function() yank_with_path(false) end, { desc = "Yank with absolute path" })

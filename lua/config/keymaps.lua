-- Essential Keymaps
-- Basic key mappings for nvim-mini

local keymap = vim.keymap.set

-- Exit terminal mode in any terminal buffer (toggleterm, opencode, etc.)
keymap("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Window navigation handled by vim-tmux-navigator plugin (see plugins/navigation.lua)
-- Uses Ctrl-h/j/k/l for seamless navigation between vim splits and tmux panes

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
-- Uses native Vim scrolling for lag-free held-key repeat.
local function setup_scroll_mappings()
  local modes = { "n", "v", "x" }

  for _, mode in ipairs(modes) do
    -- <C-d> scrolls UP (native <C-u> = half page up)
    vim.keymap.set(mode, "<C-d>", "<C-u>", {
      desc = "Scroll up",
      silent = true,
    })

    -- <C-f> scrolls DOWN (native <C-d> = half page down)
    vim.keymap.set(mode, "<C-f>", "<C-d>", {
      desc = "Scroll down",
      silent = true,
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

-- ============================================================================
-- Shared git helpers (cached, non-blocking)
-- ============================================================================

-- Cache git remote URL per cwd (invalidated on DirChanged)
local _git_cache = {}
vim.api.nvim_create_autocmd('DirChanged', {
  callback = function() _git_cache = {} end,
})

local function git_cmd(args)
  local result = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then return nil end
  return vim.trim(result)
end

-- Parse git remote URL into GitHub owner/repo
local function get_github_repo()
  local cwd = vim.fn.getcwd()
  if _git_cache[cwd] then return _git_cache[cwd] end

  local url = git_cmd({ "git", "-C", cwd, "remote", "get-url", "origin" })
  if not url then return nil end

  -- SSH: git@github.com:owner/repo.git (also handles aliases like github.com-personal)
  local owner, repo = url:match("git@github%.com[^:]*:([^/]+)/(.+)$")
  if not owner then
    -- HTTPS: https://github.com/owner/repo.git
    owner, repo = url:match("github%.com/([^/]+)/(.+)$")
  end
  if not owner then return nil end
  repo = repo:gsub("%.git$", "")
  local result = owner .. "/" .. repo
  _git_cache[cwd] = result
  return result
end

-- Get current commit SHA
local function get_commit_sha()
  return git_cmd({ "git", "-C", vim.fn.getcwd(), "rev-parse", "HEAD" })
end

-- Get file path relative to git root
local function get_git_relative_path()
  local git_root = get_git_root()
  if not git_root then return nil end
  local abs_path = vim.fn.expand("%:p")
  return abs_path:sub(#git_root + 2)
end

-- Format a line range string
local function format_line_range(start_line, end_line)
  if start_line == end_line then
    return tostring(start_line)
  end
  return string.format("%d-%d", start_line, end_line)
end

-- ============================================================================
-- Yank with file path and line numbers (for Claude Code)
-- ============================================================================

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
  local file_path
  if use_relative then
    file_path = get_git_relative_path() or vim.fn.expand("%:.")
  else
    file_path = vim.fn.expand("%:p")
  end

  local line_range = format_line_range(start_line, end_line)

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

-- Build a GitHub permalink for current file + lines
local function github_permalink(opts)
  opts = opts or {}
  local repo = get_github_repo()
  if not repo then
    vim.notify("Not a GitHub repository", vim.log.levels.WARN)
    return
  end

  local sha = get_commit_sha()
  if not sha then
    vim.notify("Could not determine commit SHA", vim.log.levels.WARN)
    return
  end

  local rel_path = get_git_relative_path()
  if not rel_path then
    vim.notify("Could not determine file path relative to git root", vim.log.levels.WARN)
    return
  end

  local url = string.format("https://github.com/%s/blob/%s/%s", repo, sha, rel_path)

  -- Add line anchor
  if opts.start_line then
    if opts.end_line and opts.end_line ~= opts.start_line then
      url = url .. string.format("#L%d-L%d", opts.start_line, opts.end_line)
    else
      url = url .. string.format("#L%d", opts.start_line)
    end
  end

  return url
end

-- Copy GitHub permalink for current line (normal mode)
keymap("n", "<leader>yl", function()
  local url = github_permalink({ start_line = vim.fn.line(".") })
  if url then
    vim.fn.setreg("+", url)
    vim.notify(url, vim.log.levels.INFO)
  end
end, { desc = "Copy GitHub permalink" })

-- Copy GitHub permalink for selection (visual mode)
keymap("v", "<leader>yl", function()
  -- Exit visual to set marks
  vim.cmd("normal! \27")
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local url = github_permalink({ start_line = start_line, end_line = end_line })
  if url then
    vim.fn.setreg("+", url)
    vim.notify(url, vim.log.levels.INFO)
  end
end, { desc = "Copy GitHub permalink (selection)" })

-- Copy GitHub permalink as markdown link (normal mode)
keymap("n", "<leader>yL", function()
  local line = vim.fn.line(".")
  local url = github_permalink({ start_line = line })
  if url then
    local rel_path = get_git_relative_path()
    local md = string.format("[`%s:%d`](%s)", rel_path, line, url)
    vim.fn.setreg("+", md)
    vim.notify(md, vim.log.levels.INFO)
  end
end, { desc = "Copy GitHub permalink (markdown)" })

-- Copy GitHub permalink as markdown link (visual mode)
keymap("v", "<leader>yL", function()
  vim.cmd("normal! \27")
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local url = github_permalink({ start_line = start_line, end_line = end_line })
  if url then
    local rel_path = get_git_relative_path()
    local md = string.format("[`%s:%s`](%s)", rel_path, format_line_range(start_line, end_line), url)
    vim.fn.setreg("+", md)
    vim.notify(md, vim.log.levels.INFO)
  end
end, { desc = "Copy GitHub permalink (markdown, selection)" })

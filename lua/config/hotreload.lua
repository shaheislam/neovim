-- Hot-reload configuration for Claude Code integration
-- Automatically reloads buffers when files change externally
-- Based on: https://www.anthropic.com/engineering/claude-code-neovim

local M = {}

-- State for file watching
local watchers = {}
local debounce_timer = nil
local DEBOUNCE_MS = 100

-- Helper: Check if buffer should be skipped
local function should_skip_buffer(bufnr)
  -- Skip if buffer is modified (don't lose local changes)
  if vim.bo[bufnr].modified then
    return true
  end

  -- Skip special buffer types
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return true
  end

  -- Skip special URI schemes (diffview://, oil://, etc.)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname:match("^%w+://") then
    return true
  end

  return false
end

-- Reload visible buffers in current tab
local function reload_visible_buffers()
  -- Get all windows in current tab
  local wins = vim.api.nvim_tabpage_list_wins(0)

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not should_skip_buffer(bufnr) then
      -- checktime triggers autoread for this buffer
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("silent! checktime")
      end)
    end
  end
end

-- Debounced reload function
local function debounced_reload()
  if debounce_timer then
    debounce_timer:stop()
  end

  debounce_timer = vim.defer_fn(function()
    reload_visible_buffers()
    debounce_timer = nil
  end, DEBOUNCE_MS)
end

-- Start watching a directory for changes
local function watch_directory(dir)
  if watchers[dir] then
    return -- Already watching
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  local ok, err = handle:start(dir, { recursive = true }, function(err, filename, events)
    if err then
      return
    end

    -- Skip .git directory internals (handled separately for diffview)
    if filename and filename:match("^%.git/") then
      return
    end

    -- Schedule reload on main thread
    vim.schedule(function()
      debounced_reload()
    end)
  end)

  if ok then
    watchers[dir] = handle
  end
end

-- Stop watching a directory
local function unwatch_directory(dir)
  local handle = watchers[dir]
  if handle then
    handle:stop()
    handle:close()
    watchers[dir] = nil
  end
end

-- Stop all watchers
local function stop_all_watchers()
  for dir, handle in pairs(watchers) do
    handle:stop()
    handle:close()
  end
  watchers = {}
end

-- Setup function
function M.setup()
  local augroup = vim.api.nvim_create_augroup("nvim_mini_hotreload", { clear = true })

  -- Autocmd-based reload triggers (supplement file watching)
  -- These handle cases where file watching might miss events
  vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "TermClose" }, {
    group = augroup,
    callback = function()
      -- Small delay to let filesystem settle
      vim.defer_fn(function()
        vim.cmd("silent! checktime")
      end, 50)
    end,
    desc = "Check for external file changes on focus/terminal events",
  })

  -- CursorHold triggers after updatetime (250ms) of no cursor movement
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = augroup,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if not should_skip_buffer(bufnr) then
        vim.cmd("silent! checktime")
      end
    end,
    desc = "Check for external file changes on cursor hold",
  })

  -- Start watching cwd on startup
  vim.api.nvim_create_autocmd("VimEnter", {
    group = augroup,
    callback = function()
      local cwd = vim.fn.getcwd()
      watch_directory(cwd)
    end,
    desc = "Start file watcher on startup",
  })

  -- Update watcher when cwd changes
  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      stop_all_watchers()
      local cwd = vim.fn.getcwd()
      watch_directory(cwd)
    end,
    desc = "Update file watcher on directory change",
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = stop_all_watchers,
    desc = "Stop file watchers on exit",
  })
end

-- Expose for diffview integration
M.watch_directory = watch_directory
M.unwatch_directory = unwatch_directory
M.reload_visible_buffers = reload_visible_buffers

return M

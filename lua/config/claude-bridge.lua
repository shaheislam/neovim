-- Claude Code Bridge - Write editor state for Claude Code consumption
-- Neovim writes to /tmp/nvim-claude-bridge/<hash>/state.json
-- Claude Code's UserPromptSubmit hook reads it before each prompt
--
-- Events: DiagnosticChanged, BufEnter, CursorHold, GitSignsUpdate, NeotestResult
-- Pattern: hotreload.lua (M.setup(), augroup lifecycle, vim.uv timers, VimLeavePre cleanup)

local M = {}

-- Config
local BRIDGE_DIR = "/tmp/nvim-claude-bridge"
local DIAG_DEBOUNCE_MS = 500
local FOCUS_DEBOUNCE_MS = 200
local GIT_DEBOUNCE_MS = 2000
local MAX_ERRORS = 10
local MAX_WARNINGS = 5

-- State
local state_dir = nil
local state_file = nil
local diag_timer = nil
local focus_timer = nil
local git_timer = nil

-- Helper: SHA-256 first 8 chars of cwd for directory isolation
local function project_hash(cwd)
  -- Use vim.fn.sha256 which is built-in
  return vim.fn.sha256(cwd):sub(1, 8)
end

-- Helper: Check if buffer should be skipped (from hotreload.lua pattern)
local function should_skip_buffer(bufnr)
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return true
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" or bufname:match("^%w+://") then
    return true
  end
  return false
end

-- Helper: Get relative path from cwd
local function rel_path(abs_path)
  local cwd = vim.fn.getcwd()
  if abs_path:sub(1, #cwd) == cwd then
    return abs_path:sub(#cwd + 2) -- skip trailing /
  end
  return abs_path
end

-- Helper: Read current state file or return empty table
local function read_state()
  local f = io.open(state_file, "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

-- Helper: Atomic write state (write .tmp then rename)
local function write_state(data)
  if not state_dir then
    return
  end
  -- Ensure dir exists
  vim.fn.mkdir(state_dir, "p")

  data.project = vim.fn.getcwd()
  data.nvim_pid = vim.fn.getpid()

  local tmp = state_file .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return
  end
  f:write(vim.json.encode(data))
  f:close()
  os.rename(tmp, state_file)
end

-- Collect diagnostics (capped, sorted by severity then file)
local function collect_diagnostics()
  local all = vim.diagnostic.get(nil) -- all buffers
  local errors = {}
  local warnings = {}

  for _, d in ipairs(all) do
    local bufnr = d.bufnr
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname ~= "" then
      local entry = {
        file = rel_path(bufname),
        line = d.lnum + 1, -- 0-indexed to 1-indexed
        message = d.message,
        source = d.source or "",
      }
      if d.severity == vim.diagnostic.severity.ERROR then
        if #errors < MAX_ERRORS then
          table.insert(errors, entry)
        end
      elseif d.severity == vim.diagnostic.severity.WARN then
        if #warnings < MAX_WARNINGS then
          table.insert(warnings, entry)
        end
      end
    end
  end

  -- Sort by file then line
  local function sort_fn(a, b)
    if a.file == b.file then
      return a.line < b.line
    end
    return a.file < b.file
  end
  table.sort(errors, sort_fn)
  table.sort(warnings, sort_fn)

  return {
    timestamp = os.time(),
    errors = errors,
    warnings = warnings,
    error_count = #errors,
    warning_count = #warnings,
  }
end

-- Collect focus info (current buffer + cursor position)
local function collect_focus()
  local bufnr = vim.api.nvim_get_current_buf()
  if should_skip_buffer(bufnr) then
    return nil
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)

  return {
    timestamp = os.time(),
    file = rel_path(bufname),
    line = cursor[1],
    filetype = vim.bo[bufnr].filetype,
  }
end

-- Collect git hunks from gitsigns (already computed, no shell out)
local function collect_git_hunks()
  local status = vim.b.gitsigns_status_dict
  if not status then
    return nil
  end

  -- Gather files with changes across all buffers
  local files_changed = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_status = vim.b[bufnr].gitsigns_status_dict
      if buf_status and (buf_status.added or 0) + (buf_status.changed or 0) + (buf_status.removed or 0) > 0 then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name ~= "" then
          table.insert(files_changed, rel_path(name))
        end
      end
    end
  end

  local added = status.added or 0
  local changed = status.changed or 0
  local removed = status.removed or 0

  if added == 0 and changed == 0 and removed == 0 and #files_changed == 0 then
    return nil
  end

  return {
    timestamp = os.time(),
    summary = string.format("+%d ~%d -%d", added, changed, removed),
    files_changed = files_changed,
  }
end

-- Update a specific section in state.json
local function update_section(section, data)
  if not state_file then
    return
  end
  local state = read_state()
  state[section] = data
  write_state(state)
end

-- Debounced diagnostic update
local function on_diagnostics_changed()
  if diag_timer then
    diag_timer:stop()
  end
  diag_timer = vim.defer_fn(function()
    vim.schedule(function()
      update_section("diagnostics", collect_diagnostics())
    end)
    diag_timer = nil
  end, DIAG_DEBOUNCE_MS)
end

-- Debounced focus update
local function on_focus_changed()
  if focus_timer then
    focus_timer:stop()
  end
  focus_timer = vim.defer_fn(function()
    vim.schedule(function()
      local focus = collect_focus()
      if focus then
        update_section("focus", focus)
      end
    end)
    focus_timer = nil
  end, FOCUS_DEBOUNCE_MS)
end

-- Debounced git update
local function on_git_changed()
  if git_timer then
    git_timer:stop()
  end
  git_timer = vim.defer_fn(function()
    vim.schedule(function()
      local hunks = collect_git_hunks()
      if hunks then
        update_section("git_hunks", hunks)
      end
    end)
    git_timer = nil
  end, GIT_DEBOUNCE_MS)
end

-- Cleanup state directory
local function cleanup()
  if state_dir then
    vim.fn.delete(state_dir, "rf")
    state_dir = nil
    state_file = nil
  end
end

function M.setup()
  local cwd = vim.fn.getcwd()
  local hash = project_hash(cwd)
  state_dir = BRIDGE_DIR .. "/" .. hash
  state_file = state_dir .. "/state.json"

  local augroup = vim.api.nvim_create_augroup("nvim_claude_bridge", { clear = true })

  -- Diagnostics (500ms debounce)
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = augroup,
    callback = on_diagnostics_changed,
    desc = "Claude bridge: update diagnostics",
  })

  -- Focus tracking (BufEnter + CursorHold, 200ms debounce)
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold" }, {
    group = augroup,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if not should_skip_buffer(bufnr) then
        on_focus_changed()
      end
    end,
    desc = "Claude bridge: update focus",
  })

  -- Git hunks via gitsigns (2s debounce)
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "GitSignsUpdate",
    callback = on_git_changed,
    desc = "Claude bridge: update git hunks",
  })

  -- Neotest results (immediate)
  -- neotest doesn't fire User:NeotestResult by default, so we hook into its API
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "NeotestResult",
    callback = function()
      -- Read neotest summary if available
      local ok, neotest = pcall(require, "neotest")
      if not ok then
        return
      end

      local adapter_ids = neotest.state.adapter_ids()
      if #adapter_ids == 0 then
        return
      end

      local passed_count = 0
      local failed = {}

      for _, adapter_id in ipairs(adapter_ids) do
        local results = neotest.state.results(adapter_id)
        if results then
          for test_id, result in pairs(results) do
            if result.status == "passed" then
              passed_count = passed_count + 1
            elseif result.status == "failed" then
              -- Extract short name from test_id (last segment)
              local name = test_id:match("[^:]+$") or test_id
              local entry = {
                name = name,
                file = result.output_file and rel_path(result.output_file) or "",
                message = result.short or "",
              }
              table.insert(failed, entry)
            end
          end
        end
      end

      local status = #failed > 0 and "fail" or "pass"
      update_section("tests", {
        timestamp = os.time(),
        status = status,
        failed = failed,
        passed_count = passed_count,
        failed_count = #failed,
      })
    end,
    desc = "Claude bridge: update test results",
  })

  -- Fire NeotestResult from neotest's post_run hook (if neotest is loaded)
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "NeotestRun",
    once = false,
    callback = function()
      -- Delay slightly to let neotest finish processing
      vim.defer_fn(function()
        vim.api.nvim_exec_autocmds("User", { pattern = "NeotestResult" })
      end, 500)
    end,
    desc = "Claude bridge: trigger NeotestResult after test run",
  })

  -- Update state dir if cwd changes
  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      cleanup()
      local new_cwd = vim.fn.getcwd()
      local new_hash = project_hash(new_cwd)
      state_dir = BRIDGE_DIR .. "/" .. new_hash
      state_file = state_dir .. "/state.json"
    end,
    desc = "Claude bridge: update state dir on cwd change",
  })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = cleanup,
    desc = "Claude bridge: cleanup state dir on exit",
  })

  -- Write initial state
  write_state({
    diagnostics = collect_diagnostics(),
    focus = collect_focus(),
  })
end

-- Expose for manual testing
M.collect_diagnostics = collect_diagnostics
M.collect_focus = collect_focus
M.collect_git_hunks = collect_git_hunks

return M

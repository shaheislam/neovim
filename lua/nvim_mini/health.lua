local M = {}

local function check_hotreload(health)
  local ok, hotreload = pcall(require, "config.hotreload")
  if not ok then
    health.error("Failed to load config.hotreload")
    return
  end

  local config = hotreload.get_config()
  if not vim.uv or not vim.uv.new_fs_event then
    health.error("vim.uv filesystem watchers are unavailable")
    return
  end

  health.ok(string.format("hotreload configured (debounce=%dms)", config.debounce_ms))
end

local function check_claude_bridge(health)
  local ok, bridge = pcall(require, "config.claude-bridge")
  if not ok then
    health.error("Failed to load config.claude-bridge")
    return
  end

  local config = bridge.get_config()
  local state_file = bridge.get_state_file()

  if vim.fn.isdirectory(config.bridge_dir) == 1 then
    health.ok("bridge base directory exists: " .. config.bridge_dir)
  else
    health.warn("bridge base directory does not exist yet: " .. config.bridge_dir)
  end

  if state_file and vim.uv.fs_stat(state_file) then
    health.ok("bridge state file is writable: " .. state_file)
  else
    health.warn("bridge state file has not been written yet")
  end
end

local function check_kubectl(health)
  if vim.fn.executable("kubectl") == 1 then
    health.ok("kubectl executable found")
  else
    health.warn("kubectl executable not found; :Kube commands will fail")
  end
end

local function check_git_workflow(health)
  health.start("nvim_mini git workflow")

  if vim.fn.executable("git") == 1 then
    health.ok("git executable found")
  else
    health.error("git executable not found")
  end

  if vim.fn.executable("tmux") == 1 then
    health.ok("tmux executable found")
  else
    health.warn("tmux executable not found; Diffview repo-follow tmux integration is unavailable")
  end

  local diffview_ok = pcall(require, "diffview")
  if diffview_ok then
    health.ok("diffview.nvim can be required")
  else
    health.warn("diffview.nvim is not loaded yet; run after lazy has installed plugins if this is unexpected")
  end

  local workflow_ok = pcall(require, "git.workflow")
  if workflow_ok then
    health.ok("git.workflow helpers load")
  else
    health.error("git.workflow helpers failed to load")
  end

  health.info("Diffview auto-switch: " .. (vim.g.diffview_auto_switch == false and "off" or "on"))
  health.info("Diffview follow-repo: " .. (vim.g.diffview_follow_repo == false and "off" or "on"))

  if vim.env.TMUX then
    health.ok("running inside tmux")
    if vim.env.NVIM_DIFFVIEW_SOCKET then
      health.info("NVIM_DIFFVIEW_SOCKET=" .. vim.env.NVIM_DIFFVIEW_SOCKET)
    else
      health.info("NVIM_DIFFVIEW_SOCKET not set; it is exported while Diffview is open")
    end
  else
    health.info("not running inside tmux")
  end
end

function M.check()
  local health = vim.health
  health.start("nvim_mini")
  check_hotreload(health)
  check_claude_bridge(health)
  check_kubectl(health)
  check_git_workflow(health)
end

return M

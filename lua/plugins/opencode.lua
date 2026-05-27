-- opencode.nvim - AI coding agent integration
-- Connects to the launchd-managed OpenCode server via HTTP + SSE
-- Shares editor context (buffers, selections, diagnostics) with the agent

local opencode_port = 4096
local opencode_ready_delay = 500
local opencode_startup_timeout = 30000
local opencode_startup_poll = 500
local opencode_service = "com.dotfiles.opencode-serve"
local opencode_username = vim.env.OPENCODE_SERVER_USERNAME or "opencode"

local function opencode_password()
  if vim.env.OPENCODE_SERVER_PASSWORD and vim.env.OPENCODE_SERVER_PASSWORD ~= "" then
    return vim.env.OPENCODE_SERVER_PASSWORD
  end

  local state_home = vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")
  local password_file = state_home .. "/opencode/server.password"
  if vim.fn.filereadable(password_file) == 1 then
    return table.concat(vim.fn.readfile(password_file), "")
  end

  return nil
end

local function opencode_env_prefix()
  local password = opencode_password()
  if not password or password == "" then
    return "OPENCODE_SERVER_USERNAME=" .. vim.fn.shellescape(opencode_username) .. " "
  end

  return "OPENCODE_SERVER_USERNAME="
    .. vim.fn.shellescape(opencode_username)
    .. " OPENCODE_SERVER_PASSWORD="
    .. vim.fn.shellescape(password)
    .. " "
end

local function opencode_command()
  return opencode_env_prefix()
    .. "opencode attach http://127.0.0.1:"
    .. opencode_port
    .. " --dir "
    .. vim.fn.shellescape(vim.fn.getcwd())
end

local function opencode_terminal_opts()
  return {
    split = "right",
    width = math.floor(vim.o.columns * 0.35),
  }
end

local function check_opencode_ready(callback)
  local curl_args = {
    "curl",
    "-fsS",
    "--max-time",
    "1",
  }
  local password = opencode_password()
  if password and password ~= "" then
    vim.list_extend(curl_args, { "-u", opencode_username .. ":" .. password })
  end
  table.insert(curl_args, "http://127.0.0.1:" .. opencode_port .. "/path")

  local job = vim.fn.jobstart(curl_args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(code == 0)
      end)
    end,
  })

  if job <= 0 then
    vim.schedule(function()
      callback(false)
    end)
  end
end

local function start_opencode_terminal()
  require("opencode.terminal").open(opencode_command(), opencode_terminal_opts())
end

local function kickstart_opencode_service()
  if vim.fn.has("macunix") ~= 1 then return end

  vim.fn.jobstart({
    "launchctl",
    "kickstart",
    "-k",
    "gui/" .. vim.fn.system({ "id", "-u" }):gsub("%s+", "") .. "/" .. opencode_service,
  }, {
    stdout_buffered = true,
    stderr_buffered = true,
  })
end

local function resolve_opencode_port(callback)
  local kicked = false
  local deadline = vim.uv.now() + opencode_startup_timeout

  local function poll()
    check_opencode_ready(function(ready)
      if ready then
        callback(opencode_port)
        return
      end

      if not kicked then
        kicked = true
        kickstart_opencode_service()
      end

      if vim.uv.now() >= deadline then
        vim.notify("Timed out waiting for OpenCode on port " .. opencode_port, vim.log.levels.ERROR, { title = "opencode" })
        callback(nil)
        return
      end

      vim.defer_fn(poll, opencode_startup_poll)
    end)
  end

  poll()
end

local function opencode_opts()
  return {
    server = {
      port = resolve_opencode_port,
      start = start_opencode_terminal,
      toggle = function()
        require("opencode.terminal").toggle(opencode_command(), opencode_terminal_opts())
      end,
      stop = function()
        require("opencode.terminal").close()
      end,
    },
    events = {
      enabled = true,
      reload = true,
      permissions = {
        enabled = true,
        idle_delay_ms = 1000,
      },
    },
    lsp = {
      enabled = true,
    },
  }
end

local function apply_opencode_opts()
  vim.g.opencode_opts = vim.tbl_deep_extend("force", vim.g.opencode_opts or {}, opencode_opts())

  local config = package.loaded["opencode.config"]
  if config and config.opts then
    config.opts = vim.tbl_deep_extend("force", config.opts, opencode_opts())
  end
end

local function with_opencode_ready(action, on_error)
  local ok, ready = pcall(function()
    return require("opencode.server").get()
  end)

  if not ok then
    if on_error then
      on_error()
    end
    vim.notify("Failed to check OpenCode server: " .. ready, vim.log.levels.ERROR, { title = "opencode" })
    return
  end

  ready
    :next(function()
      vim.defer_fn(function()
        local action_ok, err = pcall(action)
        if not action_ok then
          vim.notify("OpenCode action failed: " .. err, vim.log.levels.ERROR, { title = "opencode" })
        end
      end, opencode_ready_delay)
    end)
    :catch(function(err)
      if on_error then
        on_error()
      end
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

local function ask_with_context(prefix, submit)
  return function()
    local context = require("opencode.context").new()
    with_opencode_ready(function()
      require("opencode").ask(prefix, { submit = submit or false, context = context })
    end, function()
      context:clear()
    end)
  end
end

local function run_command(command)
  return function()
    with_opencode_ready(function()
      require("opencode").command(command)
    end)
  end
end

local function run_prompt(name)
  return function()
    local context = require("opencode.context").new()
    local prompt = require("opencode.config").opts.prompts[name]
    if not prompt then
      with_opencode_ready(function()
        require("opencode").prompt(name, { context = context })
      end, function()
        context:clear()
      end)
      return
    end

    local opts = { submit = prompt.submit, context = context }
    with_opencode_ready(function()
      if prompt.ask then
        require("opencode").ask(prompt.prompt, opts)
      else
        require("opencode").prompt(prompt.prompt, opts)
      end
    end, function()
      context:clear()
    end)
  end
end

local function extend_opencode_publish_timeout()
  local server = require("opencode.server")
  local publish_timeout = 10

  function server:tui_append_prompt(text, callback)
    return self:curl(
      "/tui/publish",
      "POST",
      { type = "tui.prompt.append", properties = { text = text } },
      callback,
      nil,
      { max_time = publish_timeout }
    )
  end

  function server:tui_execute_command(command, callback)
    return self:curl(
      "/tui/publish",
      "POST",
      { type = "tui.command.execute", properties = { command = command } },
      callback,
      nil,
      { max_time = publish_timeout }
    )
  end
end

return {
  {
    "nickjvandyke/opencode.nvim",
    version = "*",
    cmd = { "Opencode" },
    init = apply_opencode_opts,
    keys = {
      -- Toggle opencode terminal
      {
        "<leader>aoc",
        function() require("opencode").toggle() end,
        mode = { "n", "t" },
        desc = "Toggle opencode",
      },
      -- Quick toggle (global shortcut)
      {
        "<C-.>",
        function() require("opencode").toggle() end,
        mode = { "n", "t" },
        desc = "Toggle opencode",
      },
      -- Ask opencode with current context
      {
        "<leader>aoa",
        ask_with_context("@this: "),
        mode = { "n", "x" },
        desc = "Ask opencode",
      },
      -- Quick ask with auto-submit
      {
        "<leader>aos",
        ask_with_context("@this: ", true),
        mode = { "n", "x" },
        desc = "Ask opencode (submit)",
      },
      {
        "<leader>aoB",
        ask_with_context("@buffer: "),
        mode = "n",
        desc = "Ask current buffer",
      },
      {
        "<leader>aoV",
        ask_with_context("@visible: "),
        mode = "n",
        desc = "Ask visible windows",
      },
      {
        "<leader>aoQ",
        ask_with_context("@quickfix: "),
        mode = "n",
        desc = "Ask quickfix list",
      },
      -- Action picker
      {
        "<leader>aox",
        function() require("opencode").select() end,
        mode = { "n", "x" },
        desc = "opencode actions",
      },
      -- Operator-pending mode (select range then type prompt)
      {
        "go",
        function() return require("opencode").operator("@this ") end,
        mode = { "n", "x" },
        desc = "Add range to opencode",
        expr = true,
      },
      {
        "goo",
        function() return require("opencode").operator("@this ") .. "_" end,
        mode = "n",
        desc = "Add line to opencode",
        expr = true,
      },
      -- Named prompts
      {
        "<leader>aoe",
        run_prompt("explain"),
        mode = { "n", "x" },
        desc = "Explain (opencode)",
      },
      {
        "<leader>aof",
        run_prompt("fix"),
        mode = { "n", "x" },
        desc = "Fix diagnostics (opencode)",
      },
      {
        "<leader>aor",
        run_prompt("review"),
        mode = { "n", "x" },
        desc = "Review (opencode)",
      },
      {
        "<leader>aot",
        run_prompt("test"),
        mode = { "n", "x" },
        desc = "Add tests (opencode)",
      },
      {
        "<leader>aod",
        run_prompt("document"),
        mode = { "n", "x" },
        desc = "Document (opencode)",
      },
      {
        "<leader>aoo",
        run_prompt("optimize"),
        mode = { "n", "x" },
        desc = "Optimize (opencode)",
      },
      {
        "<leader>aoi",
        run_prompt("implement"),
        mode = { "n", "x" },
        desc = "Implement (opencode)",
      },
      {
        "<leader>aog",
        run_prompt("diff"),
        mode = { "n", "x" },
        desc = "Review git diff (opencode)",
      },
      {
        "<leader>aoE",
        run_prompt("diagnostics"),
        mode = { "n", "x" },
        desc = "Explain diagnostics (opencode)",
      },
      -- Session and agent controls
      {
        "<leader>aon",
        run_command("session.new"),
        mode = "n",
        desc = "New opencode session",
      },
      {
        "<leader>aop",
        function() require("opencode").select_session() end,
        mode = "n",
        desc = "Pick opencode session",
      },
      {
        "<leader>aom",
        run_command("session.compact"),
        mode = "n",
        desc = "Compact opencode session",
      },
      {
        "<leader>aou",
        run_command("session.undo"),
        mode = "n",
        desc = "Undo opencode action",
      },
      {
        "<leader>aoU",
        run_command("session.redo"),
        mode = "n",
        desc = "Redo opencode action",
      },
      {
        "<leader>aoA",
        run_command("agent.cycle"),
        mode = "n",
        desc = "Cycle opencode agent",
      },
    },
    config = function()
      apply_opencode_opts()
      extend_opencode_publish_timeout()

      -- Required for auto-reload when opencode edits files
      vim.o.autoread = true

      -- Track opencode status for statusline via OpencodeEvent autocmds
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:session.idle",
        callback = function()
          vim.g.opencode_status = "idle"
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:session.busy",
        callback = function()
          vim.g.opencode_status = "busy"
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:file.edited",
        callback = function()
          vim.cmd("checktime")
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:connected",
        callback = function()
          vim.g.opencode_status = "connected"
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "OpencodeEvent:disconnected",
        callback = function()
          vim.g.opencode_status = nil
        end,
      })
    end,
  },
}

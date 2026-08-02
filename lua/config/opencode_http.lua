local M = {}

local function notify(message, level, title)
  vim.notify(message, level or vim.log.levels.INFO, { title = title or "opencode" })
end

local function server_url()
  local url = vim.g.opencode_server_url or vim.env.OPENCODE_SERVER_URL or "http://127.0.0.1:4096"
  return url:gsub("/+$", "")
end

local function server_username()
  return vim.env.OPENCODE_SERVER_USERNAME or "opencode"
end

local function server_password()
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

local function curl_args(path, dir)
  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--max-time",
    "2",
    "--request",
    "POST",
    "--header",
    "Content-Type: application/json",
    "--header",
    "x-opencode-directory: " .. (dir or vim.fn.getcwd()),
    "--data-binary",
    "@-",
  }

  local password = server_password()
  if password and password ~= "" then
    vim.list_extend(args, { "--user", server_username() .. ":" .. password })
  end

  table.insert(args, server_url() .. path)
  return args
end

function M.post(path, body, callback, opts)
  if vim.fn.executable("curl") ~= 1 then
    callback(false, "curl is required to talk to OpenCode")
    return
  end

  local json = vim.json.encode(body)
  local args = curl_args(path, opts and opts.dir)

  if vim.system then
    vim.system(args, { text = true, stdin = json }, function(result)
      vim.schedule(function()
        callback(result.code == 0, (result.stderr or "") .. (result.stdout or ""))
      end)
    end)
    return
  end

  local output = {}
  local job = vim.fn.jobstart(args, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, data or {})
    end,
    on_stderr = function(_, data)
      vim.list_extend(output, data or {})
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(code == 0, table.concat(output, "\n"))
      end)
    end,
  })

  if job <= 0 then
    callback(false, "Failed to start curl")
    return
  end

  vim.fn.chansend(job, json)
  vim.fn.chanclose(job, "stdin")
end

function M.prompt_async(session_id, text, opts, callback)
  opts = opts or {}
  callback = callback or function() end
  if type(session_id) ~= "string" or not session_id:match("^[%w_-]+$") then
    callback(false, "Invalid OpenCode session ID")
    return
  end
  if type(text) ~= "string" or text == "" then
    callback(false, "Missing OpenCode prompt text")
    return
  end

  M.post(
    "/session/" .. session_id .. "/prompt_async",
    { parts = { { type = "text", text = text } } },
    callback,
    { dir = opts.dir }
  )
end

function M.get(path, callback, opts)
  if vim.fn.executable("curl") ~= 1 then
    callback(false, "curl is required to talk to OpenCode")
    return
  end

  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--max-time",
    "2",
    "--header",
    "x-opencode-directory: " .. ((opts and opts.dir) or vim.fn.getcwd()),
  }

  local password = server_password()
  if password and password ~= "" then
    vim.list_extend(args, { "--user", server_username() .. ":" .. password })
  end

  table.insert(args, server_url() .. path)

  if vim.system then
    vim.system(args, { text = true }, function(result)
      vim.schedule(function()
        callback(result.code == 0, (result.stdout or "") .. (result.stderr or ""))
      end)
    end)
    return
  end

  local output = {}
  local job = vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) vim.list_extend(output, data or {}) end,
    on_stderr = function(_, data) vim.list_extend(output, data or {}) end,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(code == 0, table.concat(output, "\n"))
      end)
    end,
  })

  if job <= 0 then
    callback(false, "Failed to start curl")
  end
end

function M.patch(path, body, callback, opts)
  if vim.fn.executable("curl") ~= 1 then
    callback(false, "curl is required to talk to OpenCode")
    return
  end

  local json = vim.json.encode(body)
  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--max-time",
    "2",
    "--request",
    "PATCH",
    "--header",
    "Content-Type: application/json",
    "--header",
    "x-opencode-directory: " .. ((opts and opts.dir) or vim.fn.getcwd()),
    "--data-binary",
    "@-",
  }

  local password = server_password()
  if password and password ~= "" then
    vim.list_extend(args, { "--user", server_username() .. ":" .. password })
  end

  table.insert(args, server_url() .. path)

  if vim.system then
    vim.system(args, { text = true, stdin = json }, function(result)
      vim.schedule(function()
        callback(result.code == 0, (result.stderr or "") .. (result.stdout or ""))
      end)
    end)
    return
  end

  local output = {}
  local job = vim.fn.jobstart(args, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) vim.list_extend(output, data or {}) end,
    on_stderr = function(_, data) vim.list_extend(output, data or {}) end,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(code == 0, table.concat(output, "\n"))
      end)
    end,
  })

  if job <= 0 then
    callback(false, "Failed to start curl")
    return
  end

  vim.fn.chansend(job, json)
  vim.fn.chanclose(job, "stdin")
end

local function is_json_null(value)
  return value == nil or value == vim.NIL
end

function M.canonical(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local absolute = vim.fn.fnamemodify(path, ":p")
  local resolved = vim.uv.fs_realpath(absolute) or vim.fn.resolve(absolute)
  if resolved ~= "/" then
    resolved = resolved:gsub("/+$", "")
  end
  return resolved
end

local canonical = M.canonical

local function pane_title_for_session(title)
  if type(title) ~= "string" or title == "" or title:find("[\128-\255]") then
    return nil
  end
  if #title > 40 then
    title = title:sub(1, 37) .. "..."
  end
  return "OC | " .. title
end

local function valid_root_session(session, directory)
  return type(session) == "table"
    and type(session.id) == "string"
    and session.id:match("^[%w_-]+$") ~= nil
    and type(session.title) == "string"
    and type(session.directory) == "string"
    and canonical(session.directory) == directory
    and is_json_null(session.parentID)
    and is_json_null(session.parent_id)
    and is_json_null(session.archived)
    and type(session.time) == "table"
    and is_json_null(session.time.archived)
end

local function same_attach(left, right)
  return type(left) == "table"
    and type(right) == "table"
    and left.pane == right.pane
    and left.cwd == right.cwd
    and left.title == right.title
end

-- Lists root sessions (per the /session?roots=true contract) whose directory
-- matches `dir`. Used by send_with_model's session targeting.
local function list_root_sessions(dir, callback)
  M.get("/session?roots=true&limit=1000", function(ok, output)
    if not ok then
      callback(nil, "Could not list OpenCode sessions")
      return
    end
    local parse_ok, sessions = pcall(vim.json.decode, output)
    if not parse_ok or type(sessions) ~= "table" or not vim.islist(sessions) then
      callback(nil, "Could not parse OpenCode sessions")
      return
    end
    if #sessions >= 1000 then
      callback(nil, "OpenCode session list is saturated")
      return
    end
    local matches = {}
    for _, session in ipairs(sessions) do
      if valid_root_session(session, dir) then
        table.insert(matches, session)
      end
    end
    callback(matches)
  end, { dir = dir })
end

-- The split (opened via <leader>aoc, or `ocv attach --dir <dir>`) is what
-- registers a root session for a project directory. When nothing has been
-- opened yet there is no session to target, so open it here and poll until
-- one appears rather than failing outright.
local ensure_open_fn
local ensure_open_poll_interval_ms = 400
local ensure_open_timeout_ms = 10000

function M.set_ensure_open(fn)
  ensure_open_fn = fn
end

local function ensure_session_then(dir, on_ready, on_timeout)
  if not ensure_open_fn then
    on_timeout()
    return
  end

  ensure_open_fn(dir)
  local deadline = vim.uv.now() + ensure_open_timeout_ms

  local function poll()
    list_root_sessions(dir, function(matches)
      if matches and #matches >= 1 then
        on_ready(matches)
        return
      end
      if vim.uv.now() >= deadline then
        on_timeout()
        return
      end
      vim.defer_fn(poll, ensure_open_poll_interval_ms)
    end)
  end

  poll()
end

-- NOTE: there is deliberately no HTTP append_prompt here anymore. OpenCode's
-- TUI broadcasts `tui.prompt.append` (and `tui.command.execute`) to every
-- client attached to the same project directory, so two tmux windows on the
-- same repo would both receive one append. Composer writes now go through
-- config.opencode_prompt, which targets the exact terminal owned by this
-- Neovim process. publish_command below remains directory-broadcast and must
-- not be used for prompt append/submit.

function M.publish_command(command, callback)
  if not command or command == "" then
    if callback then callback(false, "Missing OpenCode TUI command") end
    return
  end

  M.post("/tui/publish", { type = "tui.command.execute", properties = { command = command } }, function(ok, output)
    if callback then callback(ok, output) end
  end)
end

function M.fork_session(session_id, opts, callback)
  opts = opts or {}
  local dir = opts.dir or vim.fn.getcwd()
  local body = {}
  if opts.message_id and opts.message_id ~= "" then
    body.messageID = opts.message_id
  end

  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--max-time",
    "5",
    "--request",
    "POST",
    "--header",
    "Content-Type: application/json",
    "--header",
    "x-opencode-directory: " .. dir,
    "--data-binary",
    "@-",
  }

  local password = server_password()
  if password and password ~= "" then
    vim.list_extend(args, { "--user", server_username() .. ":" .. password })
  end

  table.insert(args, server_url() .. "/session/" .. session_id .. "/fork")

  local json_body = vim.json.encode(body)

  local function handle(code, stdout, stderr)
    if code ~= 0 then
      callback(nil, (stderr or "") .. (stdout or ""))
      return
    end
    local ok, decoded = pcall(vim.json.decode, stdout or "")
    if ok and decoded and decoded.id then
      callback(decoded.id, nil)
    else
      callback(nil, "unexpected fork response: " .. (stdout or ""))
    end
  end

  if vim.system then
    vim.system(args, { text = true, stdin = json_body }, function(result)
      vim.schedule(function()
        handle(result.code, result.stdout, result.stderr)
      end)
    end)
    return
  end

  local out, err = {}, {}
  local job = vim.fn.jobstart(args, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) vim.list_extend(out, data or {}) end,
    on_stderr = function(_, data) vim.list_extend(err, data or {}) end,
    on_exit = function(_, code)
      vim.schedule(function()
        handle(code, table.concat(out, "\n"), table.concat(err, "\n"))
      end)
    end,
  })

  if job <= 0 then
    callback(nil, "Failed to start curl for fork")
    return
  end

  vim.fn.chansend(job, json_body)
  vim.fn.chanclose(job, "stdin")
end

function M.get_models(callback)
  M.get("/config", function(ok, output)
    if not ok then
      callback(nil, "Could not fetch OpenCode config")
      return
    end
    local parse_ok, cfg = pcall(vim.json.decode, output)
    if not parse_ok or not cfg then
      callback(nil, "Could not parse OpenCode config")
      return
    end
    local models = {}
    for provider_id, provider_cfg in pairs(cfg.provider or {}) do
      for model_id, model_cfg in pairs((provider_cfg or {}).models or {}) do
        local name = (type(model_cfg) == "table" and model_cfg.name) or model_id
        table.insert(models, {
          label = provider_id .. " / " .. name,
          provider = provider_id,
          model = model_id,
        })
      end
    end
    table.sort(models, function(a, b) return a.label < b.label end)
    callback(models, nil)
  end)
end

function M.send_with_model(text, provider_id, model_id, opts)
  opts = opts or {}
  if not text or text == "" then
    notify("No text to send", vim.log.levels.WARN, opts.title)
    return
  end

  local tmux = require("config.opencode_tmux")
  local target = tmux.resolve_attach()
  -- A same-window tmux OpenCode pane is only registered when OpenCode runs
  -- directly in a tmux pane. opencode.nvim deliberately skips that
  -- registration when it runs OpenCode nested in its own terminal, so fall
  -- back to matching by directory alone in that case.
  local pane_identified = type(target) == "table"
    and type(target.pane) == "string"
    and type(target.cwd) == "string"
    and type(target.title) == "string"
    and target.title ~= "OpenCode"
    and pane_title_for_session(target.title:match("^OC | (.*)$")) ~= nil

  local dir = pane_identified and target.cwd or canonical(vim.fn.getcwd())
  if not dir then
    notify("Could not resolve the OpenCode project directory", vim.log.levels.ERROR, opts.title)
    return
  end

  local function submit_to(session_id)
    local body = {
      model = { providerID = provider_id, modelID = model_id },
      parts = { { type = "text", text = text } },
    }

    M.post("/session/" .. session_id .. "/prompt_async", body, function(post_ok, post_output)
      if post_ok then
        notify(opts.success or "Sent to OpenCode", vim.log.levels.INFO, opts.title)
        if opts.on_success then opts.on_success() end
        return
      end
      local message = (post_output or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if message == "" then message = "Could not send to OpenCode" end
      notify(message, vim.log.levels.ERROR, opts.title)
    end, { dir = dir })
  end

  local function proceed_with_matches(matches)
    if #matches ~= 1 then
      local message = pane_identified and "Could not uniquely identify the visible OpenCode session"
        or ("Could not uniquely identify the OpenCode session for " .. dir)
      notify(message, vim.log.levels.ERROR, opts.title)
      return
    end

    if pane_identified then
      local current_target = tmux.resolve_attach()
      if not same_attach(target, current_target) then
        notify("The visible OpenCode session changed before submission", vim.log.levels.ERROR, opts.title)
        return
      end
    end

    submit_to(matches[1].id)
  end

  list_root_sessions(dir, function(matches, err)
    if not matches then
      notify(err, vim.log.levels.ERROR, opts.title)
      return
    end

    local filtered = {}
    for _, session in ipairs(matches) do
      if not pane_identified or pane_title_for_session(session.title) == target.title then
        table.insert(filtered, session)
      end
    end

    -- No tmux pane and no registered session for this project: the split
    -- (<leader>aoc) has likely never been opened. Open it and retry once a
    -- session appears rather than failing outright.
    if #filtered == 0 and not pane_identified then
      ensure_session_then(dir, proceed_with_matches, function()
        notify("OpenCode session did not start in time", vim.log.levels.ERROR, opts.title)
      end)
      return
    end

    proceed_with_matches(filtered)
  end)
end

return M

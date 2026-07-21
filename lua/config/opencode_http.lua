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

function M.append_prompt(text, opts)
  opts = opts or {}
  if not text or text == "" then
    notify("No text to send", vim.log.levels.WARN, opts.title)
    return
  end

  M.post("/tui/publish", { type = "tui.prompt.append", properties = { text = text } }, function(ok, output)
    if ok then
      notify(opts.success or "Sent text to OpenCode", vim.log.levels.INFO, opts.title)
      if opts.on_success then opts.on_success() end
      return
    end

    if opts.fallback_clipboard then
      vim.fn.setreg("+", text)
      notify("OpenCode HTTP send failed; copied text instead", vim.log.levels.WARN, opts.title)
      return
    end

    local message = (output or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if message == "" then message = "Could not reach OpenCode at " .. server_url() end
    notify(message, vim.log.levels.ERROR, opts.title)
  end, { dir = opts.dir })
end

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

local function is_json_null(value)
  return value == nil or value == vim.NIL
end

local function canonical(path)
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

function M.send_with_model(text, provider_id, model_id, opts)
  opts = opts or {}
  if not text or text == "" then
    notify("No text to send", vim.log.levels.WARN, opts.title)
    return
  end

  local tmux = require("config.opencode_tmux")
  local target = tmux.resolve_attach()
  if
    type(target) ~= "table"
    or type(target.pane) ~= "string"
    or type(target.cwd) ~= "string"
    or type(target.title) ~= "string"
  then
    notify("No unique same-window OpenCode pane found", vim.log.levels.ERROR, opts.title)
    return
  end
  if target.title == "OpenCode" or not pane_title_for_session(target.title:match("^OC | (.*)$")) then
    notify("The visible OpenCode session cannot be identified safely", vim.log.levels.ERROR, opts.title)
    return
  end

  M.get("/session?roots=true&limit=1000", function(ok, output)
    if not ok then
      notify("Could not list OpenCode sessions", vim.log.levels.ERROR, opts.title)
      return
    end

    local parse_ok, sessions = pcall(vim.json.decode, output)
    if not parse_ok or type(sessions) ~= "table" or not vim.islist(sessions) then
      notify("Could not parse OpenCode sessions", vim.log.levels.ERROR, opts.title)
      return
    end
    if #sessions >= 1000 then
      notify("OpenCode session list is saturated", vim.log.levels.ERROR, opts.title)
      return
    end

    local matches = {}
    for _, session in ipairs(sessions) do
      if valid_root_session(session, target.cwd) and pane_title_for_session(session.title) == target.title then
        table.insert(matches, session)
      end
    end
    if #matches ~= 1 then
      notify("Could not uniquely identify the visible OpenCode session", vim.log.levels.ERROR, opts.title)
      return
    end

    local current_target = tmux.resolve_attach()
    if not same_attach(target, current_target) then
      notify("The visible OpenCode session changed before submission", vim.log.levels.ERROR, opts.title)
      return
    end

    local session_id = matches[1].id
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
    end, { dir = target.cwd })
  end, { dir = target.cwd })
end

return M

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

local function curl_args(path)
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
    "x-opencode-directory: " .. vim.fn.getcwd(),
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

function M.post(path, body, callback)
  if vim.fn.executable("curl") ~= 1 then
    callback(false, "curl is required to talk to OpenCode")
    return
  end

  local json = vim.json.encode(body)
  local args = curl_args(path)

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
  end)
end

return M

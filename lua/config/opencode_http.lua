local M = {}

local function noop() end

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

local function curl_args(method, path, body, opts)
  opts = opts or {}
  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--max-time",
    tostring(opts.timeout or 2),
    "--request",
    method,
    "--header",
    "x-opencode-directory: " .. (opts.dir or vim.fn.getcwd()),
  }
  if body ~= nil then
    vim.list_extend(args, { "--header", "Content-Type: application/json", "--data-binary", "@-" })
  end

  local password = server_password()
  if password and password ~= "" then
    vim.list_extend(args, { "--user", server_username() .. ":" .. password })
  end

  table.insert(args, server_url() .. path)
  return args
end

function M.request(method, path, body, callback, opts)
	if vim.fn.executable("curl") ~= 1 then
		callback(false, "curl is required to talk to OpenCode")
		return noop
	end

  method = method:upper()
	local json = body ~= nil and vim.json.encode(body) or nil
	local args = curl_args(method, path, body, opts)
	local done = false
	local stopped = false
	local function complete(ok, output)
		if done then
			return
		end
		done = true
		vim.schedule(function() callback(ok, output) end)
	end

	if vim.system then
		local process
		process = vim.system(args, { text = true, stdin = json }, function(result)
			complete(result.code == 0, (result.stdout or "") .. (result.stderr or ""))
		end)
		return function()
			if done or stopped then
				return
			end
			stopped = true
			if process then
				process:kill(15)
			end
		end
	end

  local out, err = {}, {}
  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(out, data or {})
    end,
    on_stderr = function(_, data)
      vim.list_extend(err, data or {})
    end,
		on_exit = function(_, code)
			complete(code == 0, table.concat(out, "\n") .. table.concat(err, "\n"))
		end,
  }
  if json ~= nil then
    job_opts.stdin = "pipe"
  end
  local job = vim.fn.jobstart(args, job_opts)

	if job <= 0 then
		done = true
		callback(false, "Failed to start curl")
		return noop
	end

  if json ~= nil then
    vim.fn.chansend(job, json)
		vim.fn.chanclose(job, "stdin")
	end

	return function()
		if done or stopped then
			return
		end
		stopped = true
		vim.fn.jobstop(job)
	end
end

function M.post(path, body, callback, opts)
	return M.request("POST", path, body, callback, opts)
end

function M.prompt_async(session_id, text, opts, callback)
  opts = opts or {}
  callback = callback or function() end
	if type(session_id) ~= "string" or not session_id:match("^[%w_-]+$") then
		callback(false, "Invalid OpenCode session ID")
		return noop
	end
	if type(text) ~= "string" or text == "" then
		callback(false, "Missing OpenCode prompt text")
		return noop
	end

	return M.post(
    "/session/" .. session_id .. "/prompt_async",
    { parts = { { type = "text", text = text } } },
    callback,
    { dir = opts.dir }
  )
end

function M.abort(session_id, callback, opts)
	callback = callback or noop
	if type(session_id) ~= "string" or not session_id:match("^[%w_-]+$") then
		callback(false, "Invalid OpenCode session ID")
		return noop
	end
	return M.post("/session/" .. session_id .. "/abort", nil, callback, opts)
end

function M.get(path, callback, opts)
	return M.request("GET", path, nil, callback, opts)
end

function M.patch(path, body, callback, opts)
	return M.request("PATCH", path, body, callback, opts)
end

function M.delete(path, callback, opts)
	return M.request("DELETE", path, nil, callback, opts)
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

-- NOTE: there is deliberately no HTTP append_prompt here anymore. OpenCode's
-- TUI broadcasts `tui.prompt.append` (and `tui.command.execute`) to every
-- client attached to the same project directory, so two tmux windows on the
-- same repo would both receive one append. Composer writes now go through
-- config.opencode_prompt, which targets the exact terminal owned by this
-- Neovim process. Session selection likewise restarts the exact owned
-- terminal instead of publishing a shared TUI event.

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
      callback(decoded.id, nil, decoded)
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

return M

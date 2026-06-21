local M = {}

local cache_ttl_ms = 5000
local db_session_limit = 50
local cache = {
	sessions = nil,
	sessions_at = 0,
	messages = {},
}

---@class OpenCodeCommandResult
---@field code integer
---@field stdout string
---@field stderr string

---@class OpenCodeSession
---@field id string
---@field title? string
---@field slug? string
---@field directory? string
---@field time? table

---@class OpenCodeMessage
---@field info table
---@field parts OpenCodePart[]

---@class OpenCodePart
---@field id? string
---@field type? string
---@field text? string
---@field tool? string
---@field state? table

local function opencode_db_path()
	return vim.env.OPENCODE_DB_PATH or vim.fn.expand("~/.local/share/opencode/opencode.db")
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "opencode" })
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
		"1.5",
		"--header",
		"Accept: application/json",
		"--header",
		"x-opencode-directory: " .. vim.fn.getcwd(),
	}

	local password = server_password()
	if password and password ~= "" then
		vim.list_extend(args, { "--user", server_username() .. ":" .. password })
	end

	table.insert(args, server_url() .. path)
	return args
end

local function sql_literal(value)
	return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function decode_json_value(value)
	if value == vim.NIL or value == nil or value == "" then
		return nil
	end
	if type(value) ~= "string" then
		return value
	end

	local ok, decoded = pcall(vim.json.decode, value)
	if ok then
		return decoded
	end
	return value
end

local function as_table(value)
	if type(value) == "table" then
		return value
	end
	return {}
end

---@param args string[]
---@param callback fun(result?: OpenCodeCommandResult, err?: string)
---@param opts? { executable?: string, start_error?: string }
local function run_command(args, callback, opts)
	opts = opts or {}
	local executable = opts.executable or args[1]
	if vim.fn.executable(executable) ~= 1 then
		callback(nil, executable .. " is required")
		return
	end

	if vim.system then
		vim.system(args, { text = true }, function(result)
			vim.schedule(function()
				callback({
					code = result.code or 0,
					stdout = result.stdout or "",
					stderr = result.stderr or "",
				})
			end)
		end)
		return
	end

	local stdout = {}
	local stderr = {}
	local job = vim.fn.jobstart(args, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			vim.list_extend(stdout, data or {})
		end,
		on_stderr = function(_, data)
			vim.list_extend(stderr, data or {})
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				callback({
					code = code or 0,
					stdout = table.concat(stdout, "\n"),
					stderr = table.concat(stderr, "\n"),
				})
			end)
		end,
	})

	if job <= 0 then
		callback(nil, opts.start_error or ("Failed to start " .. executable))
	end
end

local function run_sql(sql, callback)
	local db = opencode_db_path()
	if vim.fn.filereadable(db) ~= 1 then
		callback(nil, "OpenCode database not found: " .. db)
		return
	end

	local args = { "sqlite3", "-json", db, sql }
	run_command(args, function(result, err)
		if not result then
			callback(nil, err or "Failed to start sqlite3")
			return
		end
		if result.code ~= 0 then
			local message = vim.trim(result.stderr .. result.stdout)
			callback(nil, message ~= "" and message or "OpenCode database query failed")
			return
		end

		local raw = vim.trim(result.stdout)
		if raw == "" then
			raw = "[]"
		end
		local ok, rows = pcall(vim.json.decode, raw)
		if not ok then
			callback(nil, "Failed to decode OpenCode database response")
			return
		end
		callback(rows)
	end, { executable = "sqlite3", start_error = "Failed to start sqlite3" })
end

local function sort_sessions(sessions)
	table.sort(sessions, function(a, b)
		local a_updated = a.time and a.time.updated or 0
		local b_updated = b.time and b.time.updated or 0
		return a_updated > b_updated
	end)
end

local function fetch_sessions_from_db(callback)
	run_sql(
		[[
select
  id,
  project_id as projectID,
  slug,
  directory,
  path,
  title,
  version,
  agent,
  model,
  cost,
  tokens_input,
  tokens_output,
  tokens_reasoning,
  tokens_cache_read,
  tokens_cache_write,
  summary_additions,
  summary_deletions,
  summary_files,
  time_created,
  time_updated
from session
where time_archived is null
order by time_updated desc
limit ]] .. db_session_limit .. [[
]],
		function(rows, err)
			if not rows then
				callback(nil, err)
				return
			end

			local sessions = {}
			for _, row in ipairs(rows) do
				table.insert(sessions, {
					id = row.id,
					projectID = row.projectID,
					slug = row.slug,
					directory = row.directory,
					path = row.path,
					title = row.title,
					version = row.version,
					agent = row.agent,
					model = decode_json_value(row.model),
					cost = row.cost or 0,
					tokens = {
						input = row.tokens_input or 0,
						output = row.tokens_output or 0,
						reasoning = row.tokens_reasoning or 0,
						cache = {
							read = row.tokens_cache_read or 0,
							write = row.tokens_cache_write or 0,
						},
					},
					summary = {
						additions = row.summary_additions or 0,
						deletions = row.summary_deletions or 0,
						files = row.summary_files or 0,
					},
					time = {
						created = row.time_created,
						updated = row.time_updated,
					},
				})
			end
			callback(sessions)
		end
	)
end

local function fetch_messages_from_db(session_id, callback)
	run_sql(
		[[
select
  m.id as message_id,
  m.session_id,
  m.time_created as message_time_created,
  m.time_updated as message_time_updated,
  m.data as message_data,
  p.id as part_id,
  p.time_created as part_time_created,
  p.time_updated as part_time_updated,
  p.data as part_data
from message m
left join part p on p.message_id = m.id
where m.session_id = ]] .. sql_literal(session_id) .. [[
order by m.time_created asc, m.id asc, p.time_created asc, p.id asc
]],
		function(rows, err)
			if not rows then
				callback(nil, err)
				return
			end

			local messages = {}
			local by_id = {}
			for _, row in ipairs(rows) do
				local message = by_id[row.message_id]
				if not message then
					local info = as_table(decode_json_value(row.message_data))
					info.id = row.message_id
					info.sessionID = row.session_id
					info.time = info.time or {}
					info.time.created = info.time.created or row.message_time_created
					info.time.updated = info.time.updated or row.message_time_updated
					message = { info = info, parts = {} }
					by_id[row.message_id] = message
					table.insert(messages, message)
				end

				if row.part_id and row.part_data then
					local part = decode_json_value(row.part_data)
					if type(part) == "table" then
						part.id = row.part_id
						part.messageID = row.message_id
						part.sessionID = row.session_id
						part.time = part.time or {}
						part.time.start = part.time.start or row.part_time_created
						part.time.end_time = part.time.end_time or row.part_time_updated
						table.insert(message.parts, part)
					end
				end
			end

			callback(messages)
		end
	)
end

local function decode_json(raw, path, callback)
	local ok, decoded = pcall(vim.json.decode, raw or "")
	if not ok then
		callback(nil, "Failed to decode OpenCode response from " .. path)
		return
	end

	callback(decoded)
end

function M.get(path, callback)
	local args = curl_args(path)
	run_command(args, function(result, err)
		if not result then
			callback(nil, err or "Failed to start curl")
			return
		end
		if result.code ~= 0 then
			local message = result.stderr .. result.stdout
			callback(nil, vim.trim(message) ~= "" and vim.trim(message) or "Could not reach OpenCode")
			return
		end
		decode_json(result.stdout, path, callback)
	end, { executable = "curl", start_error = "Failed to start curl" })
end

local function fresh(timestamp)
	return timestamp > 0 and (vim.uv.now() - timestamp) < cache_ttl_ms
end

local function store_sessions(sessions)
	sort_sessions(sessions)
	cache.sessions = vim.deepcopy(sessions)
	cache.sessions_at = vim.uv.now()
	return sessions
end

local function store_messages(session_id, messages)
	cache.messages[session_id] = {
		at = vim.uv.now(),
		messages = vim.deepcopy(messages),
	}
	return messages
end

function M.sessions(callback, opts)
	opts = opts or {}
	if not opts.refresh and cache.sessions and fresh(cache.sessions_at) then
		callback(vim.deepcopy(cache.sessions))
		return
	end

	M.get("/session", function(http_sessions, http_err)
		if not http_sessions then
			fetch_sessions_from_db(function(db_sessions, db_err)
				if not db_sessions then
					callback(nil, http_err or db_err)
					return
				end

			callback(store_sessions(db_sessions))
			end)
			return
		end

		callback(store_sessions(http_sessions))
	end)
end

function M.latest_session(callback, opts)
	M.sessions(function(sessions, err)
		if not sessions then
			callback(nil, err)
			return
		end
		if #sessions == 0 then
			callback(nil, "No OpenCode sessions found")
			return
		end
		callback(sessions[1])
	end, opts)
end

function M.messages(session_id, callback, opts)
	opts = opts or {}
	if not session_id or session_id == "" then
		callback(nil, "Missing OpenCode session id")
		return
	end

	local cached = cache.messages[session_id]
	if not opts.refresh and cached and fresh(cached.at) then
		callback(vim.deepcopy(cached.messages))
		return
	end

	M.get("/session/" .. session_id .. "/message", function(http_messages, http_err)
		if not http_messages then
			fetch_messages_from_db(session_id, function(db_messages, db_err)
				if not db_messages then
					callback(nil, http_err or db_err)
					return
				end
				callback(store_messages(session_id, db_messages))
			end)
			return
		end
		callback(store_messages(session_id, http_messages))
	end)
end

function M.notify_error(err)
	notify(err or "OpenCode request failed", vim.log.levels.ERROR)
end

return M

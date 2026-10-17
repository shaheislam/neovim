local M = {}
local adapter = require("config.opencode_terminal")
local pending = {}
local remembered = {}
local header = "let g:opencode_session_snapshot = "

local function valid_id(id)
	return type(id) == "string" and id:match("^[%w_-]+$") ~= nil
end

local function snapshot()
	local bindings = require("config.opencode_handoff").active_bindings()
	local saved = {}
	for dir, owner in pairs(adapter.session_snapshot()) do
		local binding = bindings[dir]
		local previous = remembered[dir]
		local id = owner.session_id
		if previous and previous.generation == owner.generation then
			id = previous.session_id or id
		end
		if binding and binding.generation == owner.generation then
			id = binding.sessionID
		end
		remembered[dir] = { generation = owner.generation, session_id = id }
		if valid_id(id) then
			saved[dir] = id
		end
	end
	return saved
end

local function save()
	local path = vim.v.this_session
	if path == "" or vim.fn.filereadable(path) ~= 1 or vim.g.SessionLoad or #pending > 0 then
		return
	end
	local lines = vim.fn.readfile(path)
	for i = #lines, 1, -1 do
		if vim.startswith(lines[i], header) then
			table.remove(lines, i)
		end
	end
	table.insert(lines, 2, header .. "json_decode(" .. vim.fn.string(vim.json.encode(snapshot())) .. ")")
	vim.fn.writefile(lines, path)
end

local function prepare()
	pending = {}
	local seen = {}
	local lines = vim.fn.readfile(vim.v.this_session)
	local height = vim.o.lines
	for _, line in ipairs(lines) do
		height = math.max(height, tonumber(line:match("^keepjumps (%d+)")) or 0)
	end
	for _, line in ipairs(lines) do
		local escaped = line:match("^badd %+%d+ (term://.*)$") or line:match("^  silent file (term://.*)$")
		local name = escaped and escaped:gsub("\\(.)", "%1")
		local dir, command
		if name then
			dir, command = name:match("^term://(.-)//%d+:(.*)$")
		end
		if
			name
			and not seen[name]
			and dir
			and (command:match("^ocv attach ") or command:match("^opencode attach "))
		then
			seen[name] = true
			dir = vim.uv.fs_realpath(vim.fn.expand(dir)) or vim.fn.expand(dir)
			local buf = vim.fn.bufadd(name)
			if not adapter.is_buffer(buf) then
				-- Neovim's terminal BufReadCmd skips jobstart when this title exists.
				vim.b[buf].term_title = "OpenCode restore"
				vim.bo[buf].buftype = "nofile"
				vim.bo[buf].bufhidden = "hide"
				vim.bo[buf].swapfile = false
				vim.fn.bufload(buf)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({ "" }, height))
			end
			table.insert(pending, { dir = dir, buf = buf })
		end
	end
end

local function restore()
	local saved = vim.g.opencode_session_snapshot or {}
	vim.g.opencode_session_snapshot = nil
	if #pending == 0 then
		return
	end
	local ok, lazy = pcall(require, "lazy")
	if ok then
		lazy.load({ plugins = { "opencode.nvim" } })
	end
	local focus = vim.api.nvim_get_current_win()
	local placeholders = pending
	pending = {}
	for _, item in ipairs(placeholders) do
		local restored, err = pcall(function()
			local id = saved[item.dir]
			if id ~= nil and not valid_id(id) then
				error("Invalid saved session ID for " .. item.dir)
			end
			local context = valid_id(id) and { session_id = id } or { restore_latest = true }
			local term = adapter.start(item.dir, context)
			for _, win in ipairs(vim.fn.win_findbuf(item.buf)) do
				vim.api.nvim_win_set_buf(win, term.bufnr)
				term.window = win
			end
			if item.buf ~= term.bufnr and vim.api.nvim_buf_is_valid(item.buf) then
				vim.api.nvim_buf_delete(item.buf, { force = true })
			end
		end)
		if not restored then
			vim.notify("OpenCode session restore failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end
	if vim.api.nvim_win_is_valid(focus) then
		vim.api.nvim_set_current_win(focus)
	end
	M.restored = true
end

function M.setup()
	local group = vim.api.nvim_create_augroup("nvim_mini_opencode_session", { clear = true })
	vim.api.nvim_create_autocmd("SessionWritePost", { group = group, callback = save })
	vim.api.nvim_create_autocmd("SessionLoadPre", { group = group, callback = prepare })
	vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = restore })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "OpencodeHandoffEvent:binding_changed", "Obsession" },
		callback = save,
	})
end

return M

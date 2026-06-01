local M = {}

local scopes = {
	all = "All messages",
	prompts = "User prompts",
	assistant = "Assistant output",
	reasoning = "Reasoning",
	tools = "Tool calls",
	tool_output = "Tool output",
}

local function to_text(value)
	if value == nil then
		return ""
	end
	if type(value) == "string" then
		return value
	end
	local ok, encoded = pcall(vim.json.encode, value)
	if ok then
		return encoded
	end
	return vim.inspect(value)
end

local function one_line(value, max_len)
	local text = to_text(value):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	max_len = max_len or 180
	if #text > max_len then
		return text:sub(1, max_len - 3) .. "..."
	end
	return text
end

local function timestamp(ms)
	if not ms then
		return ""
	end
	return os.date("%Y-%m-%d %H:%M", math.floor(ms / 1000))
end

local function selected_items(selected, entry_map)
	local utils = require("fzf-lua.utils")
	local items = {}
	for _, entry in ipairs(selected or {}) do
		local key = utils.strip_ansi_coloring(entry)
		local item = entry_map[key]
		if item then
			table.insert(items, item)
		end
	end
	return items
end

local function item_payload(item)
	local header = ("[%s %s] %s"):format(item.role, item.kind, item.time)
	if item.session and item.session.title then
		header = header .. " | " .. item.session.title
	end
	if item.tool and item.tool ~= "" then
		header = header .. " " .. item.tool
	end
	if item.title and item.title ~= "" then
		header = header .. " - " .. item.title
	end
	return header .. "\n" .. item.text
end

local function send_to_prompt(items)
	if #items == 0 then
		return
	end
	local payload = table.concat(vim.tbl_map(item_payload, items), "\n\n")
	require("config.opencode_http").append_prompt(payload .. "\n", {
		title = "opencode",
		success = "Sent OpenCode selection to prompt",
		fallback_clipboard = true,
	})
end

local function yank_items(items)
	if #items == 0 then
		return
	end
	local payload = table.concat(vim.tbl_map(item_payload, items), "\n\n")
	vim.fn.setreg("+", payload)
	vim.notify("Copied OpenCode selection", vim.log.levels.INFO, { title = "opencode" })
end

local function switch_tui_session(item)
	if not item or not item.session or not item.session.id then
		return
	end
	require("config.opencode_http").post("/tui/select-session", { sessionID = item.session.id }, function(ok, output)
		if ok then
			vim.notify(
				"Switched OpenCode pane to " .. (item.session.title or item.session.id),
				vim.log.levels.INFO,
				{ title = "opencode" }
			)
			return
		end
		local message = vim.trim(output or "")
		if message == "" then
			message = "Could not switch OpenCode session"
		end
		vim.notify(message, vim.log.levels.ERROR, { title = "opencode" })
	end)
end

local function tool_text(part, mode)
	local state = part.state or {}
	local chunks = {}
	if mode ~= "output" then
		if state.title then
			table.insert(chunks, "title: " .. to_text(state.title))
		end
		if state.input then
			table.insert(chunks, "input:\n" .. to_text(state.input))
		end
	end
	if mode ~= "input" and state.output then
		table.insert(chunks, "output:\n" .. to_text(state.output))
	end
	return table.concat(chunks, "\n\n")
end

local function include_part(scope, role, part)
	if scope == "prompts" then
		return role == "user" and part.type == "text"
	elseif scope == "assistant" then
		return role == "assistant" and part.type == "text"
	elseif scope == "reasoning" then
		return part.type == "reasoning"
	elseif scope == "tools" then
		return part.type == "tool"
	elseif scope == "tool_output" then
		return part.type == "tool" and part.state and part.state.output ~= nil
	end
	return part.type == "text" or part.type == "reasoning" or part.type == "tool"
end

local function part_content(scope, part)
	if part.type == "tool" then
		return tool_text(part, scope == "tool_output" and "output" or nil)
	end
	return part.text or ""
end

local function build_items(session, messages, scope)
	local items = {}
	for message_idx, message in ipairs(messages or {}) do
		local info = message.info or {}
		local role = info.role or "unknown"
		for part_idx, part in ipairs(message.parts or {}) do
			if include_part(scope, role, part) then
				local text = part_content(scope, part)
				if text ~= "" then
					table.insert(items, {
						session = session,
						messages = messages,
						message_idx = message_idx,
						part_idx = part_idx,
						message_id = info.id or part.messageID,
						part_id = part.id,
						role = role,
						kind = part.type or "unknown",
						tool = part.tool,
						title = part.state and part.state.title or nil,
						time = timestamp((part.time and part.time.start) or (info.time and info.time.created)),
						text = text,
					})
				end
			end
		end
	end
	return items
end

local function append_lines(lines, text)
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, line)
	end
end

local function transcript_name(session)
	local slug = session.slug or session.title or session.id or "session"
	slug = slug:gsub("[%s/\\:]+", "-"):gsub("[^%w%._%-]", "")
	if slug == "" then
		slug = session.id or "session"
	end
	return "opencode://" .. slug
end

local function open_transcript(item)
	if not item or not item.session or not item.messages then
		return
	end

	local return_target = require("config.return_target")
	local target = return_target.capture() or return_target.last()
	local session = item.session
	local lines = {
		"OpenCode Transcript",
		"Session: " .. (session.title or session.id or "unknown"),
		"ID: " .. (session.id or "unknown"),
		"",
	}
	local target_line = 1

	for message_idx, message in ipairs(item.messages) do
		local info = message.info or {}
		table.insert(
			lines,
			("[%s] %s %s"):format(info.role or "unknown", timestamp(info.time and info.time.created), info.id or "")
		)
		for part_idx, part in ipairs(message.parts or {}) do
			local line_nr = #lines + 1
			local label = part.tool and (part.type .. ":" .. part.tool) or (part.type or "unknown")
			table.insert(lines, ("  - %s %s"):format(label, part.id or ""))
			if message_idx == item.message_idx and part_idx == item.part_idx then
				target_line = line_nr
			end
			local text = part.type == "tool" and tool_text(part) or (part.text or "")
			if text ~= "" then
				append_lines(lines, vim.trim(text))
			end
			table.insert(lines, "")
		end
	end

	local existing = vim.fn.bufnr(transcript_name(session))
	local buf = existing > 0 and existing or vim.api.nvim_create_buf(true, false)
	vim.bo[buf].modifiable = true
	vim.bo[buf].readonly = false
	if existing <= 0 then
		vim.api.nvim_buf_set_name(buf, transcript_name(session))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "opencode-transcript"
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_win_set_cursor(0, { math.max(target_line, 1), 0 })
	vim.cmd("normal! zz")

	vim.keymap.set("n", "q", function()
		return_target.delete_transient_buffer(buf, target)
	end, { buffer = buf, silent = true, desc = "Close transcript" })
	vim.keymap.set("n", "r", function()
		require("config.opencode_pickers").messages("all", { session = session, refresh = true })
	end, { buffer = buf, silent = true, desc = "Refresh OpenCode transcript" })
end

local function open_message_picker(items, scope, opts)
	opts = opts or {}
	local fzf = require("fzf-lua")
	local label = opts.label or scopes[scope] or scopes.all
	if #items == 0 then
		vim.notify("No OpenCode " .. label:lower() .. " found", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local entries = {}
	local entry_map = {}
	for idx, item in ipairs(items) do
		local entry = ("%04d  %-9s %-11s %-15s %s"):format(
			idx,
			item.role,
			item.kind,
			item.tool or item.time,
			one_line(item.title or item.text)
		)
		table.insert(entries, entry)
		entry_map[entry] = item
	end

	local function first_item(selected)
		return selected_items(selected, entry_map)[1]
	end

	fzf.fzf_exec(entries, {
		prompt = "OpenCode " .. label .. "> ",
		fzf_opts = {
			["--multi"] = true,
			["--header"] = "Enter: jump transcript | C-a: append | C-y: copy | C-o: open session | C-s: sessions | C-r: refresh",
		},
		actions = {
			["default"] = function(selected)
				local item = first_item(selected)
				if item then
					vim.schedule(function()
						open_transcript(item)
					end)
				end
			end,
			["ctrl-a"] = function(selected)
				send_to_prompt(selected_items(selected, entry_map))
			end,
			["ctrl-y"] = function(selected)
				yank_items(selected_items(selected, entry_map))
			end,
			["ctrl-o"] = function(selected)
				switch_tui_session(first_item(selected))
			end,
			["ctrl-s"] = function()
				vim.schedule(function()
					M.sessions(scope)
				end)
			end,
			["ctrl-r"] = function()
				vim.schedule(function()
					if opts.all_sessions then
						M.all_sessions(scope, { refresh = true })
					else
						M.messages(scope, { session = opts.session, refresh = true })
					end
				end)
			end,
		},
	})
end

function M.messages(scope, opts)
	scope = scope or "all"
	opts = opts or {}
	local api = require("config.opencode_messages")

	local function fetch_for_session(session)
		api.messages(session.id, function(messages, err)
			if not messages then
				api.notify_error(err)
				return
			end
			open_message_picker(build_items(session, messages, scope), scope, { session = session })
		end, { refresh = opts.refresh })
	end

	if opts.session then
		fetch_for_session(opts.session)
		return
	end

	api.latest_session(function(session, err)
		if not session then
			api.notify_error(err)
			return
		end
		fetch_for_session(session)
	end, { refresh = opts.refresh })
end

function M.all_sessions(scope, opts)
	scope = scope or "all"
	opts = opts or {}
	local api = require("config.opencode_messages")
	api.sessions(function(sessions, err)
		if not sessions then
			api.notify_error(err)
			return
		end
		if #sessions == 0 then
			vim.notify("No OpenCode sessions found", vim.log.levels.WARN, { title = "opencode" })
			return
		end

		local pending = #sessions
		local all_items = {}
		for _, session in ipairs(sessions) do
			api.messages(session.id, function(messages)
				if messages then
					vim.list_extend(all_items, build_items(session, messages, scope))
				end
				pending = pending - 1
				if pending == 0 then
					open_message_picker(
						all_items,
						scope,
						{ label = "All sessions " .. (scopes[scope] or scopes.all), all_sessions = true }
					)
				end
			end, { refresh = opts.refresh })
		end
	end, { refresh = opts.refresh })
end

function M.sessions(scope)
	scope = scope or "all"
	local api = require("config.opencode_messages")
	api.sessions(function(sessions, err)
		if not sessions then
			api.notify_error(err)
			return
		end
		if #sessions == 0 then
			vim.notify("No OpenCode sessions found", vim.log.levels.WARN, { title = "opencode" })
			return
		end

		local fzf = require("fzf-lua")
		local entries = {}
		local entry_map = {}
		for idx, session in ipairs(sessions) do
			local entry = ("%04d  %s  %s  %s"):format(
				idx,
				timestamp(session.time and session.time.updated),
				session.agent or "",
				session.title or session.id
			)
			table.insert(entries, entry)
			entry_map[entry] = session
		end

		fzf.fzf_exec(entries, {
			prompt = "OpenCode Sessions> ",
			fzf_opts = { ["--header"] = "Enter: search selected session | C-o: switch live pane" },
			actions = {
				["default"] = function(selected)
					local item = selected_items(selected, entry_map)[1]
					if not item then
						return
					end
					vim.schedule(function()
						M.messages(scope, { session = item })
					end)
				end,
				["ctrl-o"] = function(selected)
					local item = selected_items(selected, entry_map)[1]
					if item then
						switch_tui_session({ session = item })
					end
				end,
			},
		})
	end)
end

function M.all()
	M.messages("all")
end
function M.prompts()
	M.messages("prompts")
end
function M.assistant()
	M.messages("assistant")
end
function M.reasoning()
	M.messages("reasoning")
end
function M.tools()
	M.messages("tools")
end
function M.tool_output()
	M.messages("tool_output")
end

return M

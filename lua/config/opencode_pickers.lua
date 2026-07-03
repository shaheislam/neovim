local M = {}

local scopes = {
	all = "All messages",
	prompts = "User prompts",
	assistant = "Assistant output",
	reasoning = "Reasoning",
	tools = "Tool calls",
	tool_output = "Tool output",
}

local scope_order = { "all", "prompts", "assistant", "reasoning", "tools", "tool_output" }

local part_filters = {
	all = function(_, part)
		return part.type == "text" or part.type == "reasoning" or part.type == "tool"
	end,
	prompts = function(role, part)
		return role == "user" and part.type == "text"
	end,
	assistant = function(role, part)
		return role == "assistant" and part.type == "text"
	end,
	reasoning = function(_, part)
		return part.type == "reasoning"
	end,
	tools = function(_, part)
		return part.type == "tool"
	end,
	tool_output = function(_, part)
		return part.type == "tool" and part.state and part.state.output ~= nil
	end,
}

local resolve_timeline_anchor
local surrounding_payload

---@class OpenCodePickerItem
---@field session OpenCodeSession
---@field messages OpenCodeMessage[]
---@field message_idx integer
---@field part_idx integer
---@field message_id? string
---@field part_id? string
---@field role string
---@field kind string
---@field tool? string
---@field title? string
---@field time string
---@field text string

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

local function session_label(session, max_len)
	local label = session and (session.title or session.slug or session.id) or "unknown"
	return one_line(label, max_len or 32)
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

local function append_lines(lines, text)
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, line)
	end
end

local function tui_error(message)
	return message .. "\nHint: requires an active OpenCode TUI/server; restart OpenCode if the TUI command state is stale."
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

local function item_reference(item)
	return table.concat({
		"OpenCode reference",
		"Session: " .. ((item.session and (item.session.title or item.session.id)) or "unknown"),
		"Session ID: " .. ((item.session and item.session.id) or ""),
		"Message ID: " .. (item.message_id or ""),
		"Part ID: " .. (item.part_id or ""),
		("Role/Kind: %s/%s"):format(item.role or "unknown", item.kind or "unknown"),
		"Time: " .. (item.time or ""),
	}, "\n")
end

local function live_sync_label(item)
	local anchor = resolve_timeline_anchor and resolve_timeline_anchor(item) or nil
	if not anchor then
		return "none"
	end
	return anchor.exact and "exact" or "previous prompt"
end

local function preview_lines(item)
	local lines = {
		"# OpenCode Selection",
		"",
		"Session: " .. ((item.session and (item.session.title or item.session.id)) or "unknown"),
		"Session ID: " .. ((item.session and item.session.id) or "unknown"),
		"Role: " .. (item.role or "unknown"),
		"Kind: " .. (item.kind or "unknown"),
		"Time: " .. (item.time or ""),
		"Live sync: " .. live_sync_label(item),
		"Message ID: " .. (item.message_id or ""),
		"Part ID: " .. (item.part_id or ""),
	}

	if item.tool and item.tool ~= "" then
		table.insert(lines, "Tool: " .. item.tool)
	end
	if item.title and item.title ~= "" then
		table.insert(lines, "Title: " .. item.title)
	end

	table.insert(lines, "")
	table.insert(lines, "---")
	table.insert(lines, "")
	append_lines(lines, vim.trim(item.text or ""))
	return lines
end

local function session_preview_lines(session)
	local lines = {
		"# OpenCode Session",
		"",
		"Title: " .. (session.title or session.id or "unknown"),
		"ID: " .. (session.id or ""),
		"Slug: " .. (session.slug or ""),
		"Agent: " .. (session.agent or ""),
		"Created: " .. timestamp(session.time and session.time.created),
		"Updated: " .. timestamp(session.time and session.time.updated),
	}

	if session.model then
		table.insert(lines, "Model: " .. one_line(session.model, 120))
	end
	if session.cost then
		table.insert(lines, ("Cost: $%.4f"):format(session.cost))
	end
	if session.tokens then
		local tokens = session.tokens
		table.insert(
			lines,
			("Tokens: input=%s output=%s reasoning=%s"):format(
				tokens.input or 0,
				tokens.output or 0,
				tokens.reasoning or 0
			)
		)
	end
	if session.summary then
		table.insert(
			lines,
			("Summary: +%s -%s files=%s"):format(
				session.summary.additions or 0,
				session.summary.deletions or 0,
				session.summary.files or 0
			)
		)
	end

	return lines
end

local function preview_command(temp_dir)
	local path = vim.fn.shellescape(temp_dir) .. "/{1}.md"
	if vim.fn.executable("bat") == 1 then
		return "bat --color=always --style=plain --language=markdown " .. path
	end
	return "cat " .. path
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

local function send_context_to_prompt(items)
	if #items == 0 then
		return
	end
	local payload = table.concat(vim.tbl_map(function(item)
		return surrounding_payload(item, 1)
	end, items), "\n\n")
	require("config.opencode_http").append_prompt(payload .. "\n", {
		title = "opencode",
		success = "Sent OpenCode surrounding context to prompt",
		fallback_clipboard = true,
	})
end

local function resume_from_item(item)
	if not item then
		return
	end
	local payload = table.concat({
		"Using this prior OpenCode exchange as context, continue from this point.",
		"Preserve the original intent, avoid repeating completed work, and identify the next concrete action.",
		"",
		surrounding_payload(item, 1),
	}, "\n")
	require("config.opencode_http").append_prompt(payload .. "\n", {
		title = "opencode",
		success = "Sent resume context to OpenCode prompt",
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

local function yank_references(items)
	if #items == 0 then
		return
	end
	local payload = table.concat(vim.tbl_map(item_reference, items), "\n\n")
	vim.fn.setreg("+", payload)
	vim.notify("Copied OpenCode reference", vim.log.levels.INFO, { title = "opencode" })
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

local function timeline_anchor_for_message(message, message_idx)
	local info = message.info or {}
	if info.role ~= "user" then
		return nil
	end

	for _, part in ipairs(message.parts or {}) do
		if part.type == "text" and not part.synthetic and vim.trim(part.text or "") ~= "" then
			return {
				message_idx = message_idx,
				message_id = info.id or part.messageID,
			}
		end
	end

	return nil
end

local function timeline_anchors(messages)
	local anchors = {}
	for message_idx, message in ipairs(messages or {}) do
		local anchor = timeline_anchor_for_message(message, message_idx)
		if anchor and anchor.message_id then
			table.insert(anchors, anchor)
		end
	end
	return anchors
end

resolve_timeline_anchor = function(item)
	if not item or not item.messages then
		return nil
	end

	local anchors = timeline_anchors(item.messages)
	local previous_anchor
	for idx, anchor in ipairs(anchors) do
		anchor.index = idx
		if anchor.message_id == item.message_id then
			anchor.exact = true
			anchor.total = #anchors
			return anchor
		end
		if anchor.message_idx <= item.message_idx then
			previous_anchor = anchor
		else
			break
		end
	end

	if previous_anchor then
		previous_anchor.exact = false
		previous_anchor.total = #anchors
		return previous_anchor
	end

	return nil
end

local function publish_commands(commands, callback)
	local http = require("config.opencode_http")
	local index = 1

	local function next_command()
		local command = commands[index]
		if not command then
			if callback then
				callback(true)
			end
			return
		end

		http.publish_command(command, function(ok, output)
			if not ok then
				if callback then
					callback(false, output)
				end
				return
			end
			index = index + 1
			next_command()
		end)
	end

	next_command()
end

local function sync_live_timeline(item)
	if not item or not item.session or not item.session.id then
		return
	end

	local anchor = resolve_timeline_anchor(item)
	if not anchor then
		vim.notify(tui_error("No OpenCode timeline anchor found for selection"), vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local http = require("config.opencode_http")
		http.post("/tui/select-session", { sessionID = item.session.id }, function(ok, output)
		if not ok then
			local message = vim.trim(output or "")
			if message == "" then
				message = "Could not switch OpenCode session"
			end
			vim.notify(tui_error(message), vim.log.levels.ERROR, { title = "opencode" })
			return
		end

			http.publish_command("session.timeline", function(timeline_ok, timeline_output)
			if not timeline_ok then
				local message = vim.trim(timeline_output or "")
				if message == "" then
					message = "Could not open OpenCode timeline"
				end
				vim.notify(tui_error(message), vim.log.levels.ERROR, { title = "opencode" })
				return
			end

			vim.defer_fn(function()
				local commands = {}
				local from_start = anchor.index - 1
				local from_end = anchor.total - anchor.index
				if from_end < from_start then
					table.insert(commands, "dialog.select.end")
					for _ = 1, from_end do
						table.insert(commands, "dialog.select.prev")
					end
				else
					table.insert(commands, "dialog.select.home")
					for _ = 1, from_start do
						table.insert(commands, "dialog.select.next")
					end
				end

				publish_commands(commands, function(move_ok, move_output)
					if not move_ok then
						local message = vim.trim(move_output or "")
						if message == "" then
							message = "Could not move OpenCode timeline selection"
						end
						vim.notify(tui_error(message), vim.log.levels.ERROR, { title = "opencode" })
						return
					end

					local message = anchor.exact and "Synced live OpenCode pane" or "Synced live OpenCode pane to previous user prompt"
					vim.notify(message, vim.log.levels.INFO, { title = "opencode" })
				end)
			end, 80)
		end)
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
	local filter = part_filters[scope] or part_filters.all
	return filter(role, part)
end

local function part_content(scope, part)
	if part.type == "tool" then
		return tool_text(part, scope == "tool_output" and "output" or nil)
	end
	return part.text or ""
end

local function message_payload(message)
	local info = message.info or {}
	local lines = {
		("[%s] %s %s"):format(info.role or "unknown", timestamp(info.time and info.time.created), info.id or ""),
	}
	for _, part in ipairs(message.parts or {}) do
		local label = part.tool and (part.type .. ":" .. part.tool) or (part.type or "unknown")
		table.insert(lines, "- " .. label .. " " .. (part.id or ""))
		local text = part.type == "tool" and tool_text(part) or (part.text or "")
		if text ~= "" then
			append_lines(lines, vim.trim(text))
		end
		if #lines > 0 then
			table.insert(lines, "")
		end
	end
	return vim.trim(table.concat(lines, "\n"))
end

surrounding_payload = function(item, radius)
	if not item or not item.messages then
		return ""
	end
	radius = radius or 1
	local start_idx = math.max(1, item.message_idx - radius)
	local end_idx = math.min(#item.messages, item.message_idx + radius)
	local lines = {
		"OpenCode surrounding context",
		"Session: " .. ((item.session and (item.session.title or item.session.id)) or "unknown"),
		"Session ID: " .. ((item.session and item.session.id) or ""),
		"Selected message: " .. (item.message_id or ""),
		"",
	}
	for idx = start_idx, end_idx do
		local prefix = idx == item.message_idx and "## Selected" or "## Neighbor"
		table.insert(lines, prefix .. " message " .. idx)
		append_lines(lines, message_payload(item.messages[idx] or {}))
		table.insert(lines, "")
	end
	return vim.trim(table.concat(lines, "\n"))
end

local function build_items(session, messages, scope)
	local items = {}
	for message_idx, message in ipairs(messages or {}) do
		local info = message.info or {}
		local role = info.role or "unknown"
		local previous_tool_group
		for part_idx, part in ipairs(message.parts or {}) do
			if include_part(scope, role, part) then
				local text = part_content(scope, part)
				if text ~= "" then
					local item = {
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
					}

					if scope == "all" and part.type == "tool" then
						local key = (item.tool or "") .. "\0" .. (item.title or "")
						if previous_tool_group and previous_tool_group.key == key then
							previous_tool_group.count = previous_tool_group.count + 1
							previous_tool_group.item.title = (item.title or item.tool or "tool")
								.. (" (grouped x%s) "):format(previous_tool_group.count)
							previous_tool_group.item.text = previous_tool_group.item.text
								.. "\n\n--- grouped repeated tool call ---\n\n"
								.. item.text
						else
							table.insert(items, item)
							previous_tool_group = { key = key, item = item, count = 1 }
						end
					else
						table.insert(items, item)
						previous_tool_group = nil
					end
				end
			end
		end
	end
	return items
end

local function transcript_name(session)
	local slug = session.slug or session.title or session.id or "session"
	slug = slug:gsub("[%s/\\:]+", "-"):gsub("[^%w%._%-]", "")
	if slug == "" then
		slug = session.id or "session"
	end
	return "opencode://" .. slug
end

local function search_transcript_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local entries = {}
	local entry_map = {}
	for idx, line in ipairs(lines) do
		if vim.trim(line) ~= "" then
			local entry = ("%04d  %s"):format(idx, line)
			table.insert(entries, entry)
			entry_map[entry] = idx
		end
	end

	if #entries == 0 then
		vim.notify("No transcript lines to search", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	require("fzf-lua").fzf_exec(entries, {
		prompt = "OpenCode Transcript> ",
		fzf_opts = { ["--header"] = "Enter: jump line" },
		actions = {
			["default"] = function(selected)
				local utils = require("fzf-lua.utils")
				local key = selected and selected[1] and utils.strip_ansi_coloring(selected[1])
				local line_nr = key and entry_map[key]
				if line_nr then
					vim.schedule(function()
						vim.api.nvim_set_current_buf(buf)
						vim.api.nvim_win_set_cursor(0, { line_nr, 0 })
						vim.cmd("normal! zz")
					end)
				end
			end,
		},
	})
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
		"Keys: q close | r refresh | s or / search transcript",
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
	vim.keymap.set("n", "s", function()
		search_transcript_buffer(buf)
	end, { buffer = buf, silent = true, desc = "Search OpenCode transcript" })
	vim.keymap.set("n", "/", function()
		search_transcript_buffer(buf)
	end, { buffer = buf, silent = true, desc = "Search OpenCode transcript" })
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
	local preview_dir = vim.fn.tempname()
	local ok_mkdir = pcall(vim.fn.mkdir, preview_dir, "p")
	if not ok_mkdir then
		vim.notify("Could not create OpenCode preview directory", vim.log.levels.ERROR, { title = "opencode" })
		return
	end
	for idx, item in ipairs(items) do
		local entry
		if opts.all_sessions then
			entry = ("%04d  %-24s %-9s %-11s %-15s %s"):format(
				idx,
				session_label(item.session, 24),
				item.role,
				item.kind,
				item.tool or item.time,
				one_line(item.title or item.text)
			)
		else
			entry = ("%04d  %-9s %-11s %-15s %s"):format(
				idx,
				item.role,
				item.kind,
				item.tool or item.time,
				one_line(item.title or item.text)
			)
		end
		table.insert(entries, entry)
		entry_map[entry] = item
		local ok_write = pcall(vim.fn.writefile, preview_lines(item), ("%s/%04d.md"):format(preview_dir, idx))
		if not ok_write then
			vim.notify("Could not write OpenCode preview", vim.log.levels.ERROR, { title = "opencode" })
			vim.fn.delete(preview_dir, "rf")
			return
		end
	end

	local function first_item(selected)
		return selected_items(selected, entry_map)[1]
	end

	local function reopen(new_scope)
		vim.schedule(function()
			if opts.all_sessions then
				M.all_sessions(new_scope)
			else
				M.messages(new_scope, { session = opts.session })
			end
		end)
	end

	local function pick_scope()
		local scope_entries = {}
		local scope_map = {}
		for _, scope_name in ipairs(scope_order) do
			local entry = ("%-12s %s"):format(scope_name, scopes[scope_name] or scope_name)
			table.insert(scope_entries, entry)
			scope_map[entry] = scope_name
		end

		fzf.fzf_exec(scope_entries, {
			prompt = "OpenCode Scope> ",
			fzf_opts = { ["--header"] = "Enter: reopen picker with selected scope" },
			actions = {
				["default"] = function(selected)
					local utils = require("fzf-lua.utils")
					local key = selected and selected[1] and utils.strip_ansi_coloring(selected[1])
					local new_scope = key and scope_map[key]
					if new_scope then
						reopen(new_scope)
					end
				end,
			},
		})
	end

	local actions = {
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
		["ctrl-x"] = function(selected)
			send_context_to_prompt(selected_items(selected, entry_map))
		end,
		["ctrl-u"] = function(selected)
			resume_from_item(first_item(selected))
		end,
		["ctrl-y"] = function(selected)
			yank_items(selected_items(selected, entry_map))
		end,
		["ctrl-b"] = function(selected)
			yank_references(selected_items(selected, entry_map))
		end,
		["ctrl-o"] = function(selected)
			switch_tui_session(first_item(selected))
		end,
		["ctrl-l"] = function(selected)
			sync_live_timeline(first_item(selected))
		end,
		["alt-l"] = function(selected)
			local item = first_item(selected)
			if item then
				vim.schedule(function()
					open_transcript(item)
				end)
				sync_live_timeline(item)
			end
		end,
		["alt-s"] = function()
			pick_scope()
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
	}

	local scope_actions = {
		["alt-a"] = "all",
		["alt-p"] = "prompts",
		["alt-m"] = "assistant",
		["alt-r"] = "reasoning",
		["alt-t"] = "tools",
		["alt-o"] = "tool_output",
	}
	for key, new_scope in pairs(scope_actions) do
		actions[key] = function()
			reopen(new_scope)
		end
	end

	fzf.fzf_exec(entries, {
		prompt = "OpenCode " .. label .. "> ",
		preview = preview_command(preview_dir),
		winopts = {
			on_close = function()
				vim.fn.delete(preview_dir, "rf")
			end,
		},
		fzf_opts = {
			["--multi"] = true,
			["--header"] = "Enter: transcript | A-l: transcript+live | C-l: live | C-a: append | C-x: context | C-u: resume | C-y: copy | C-b: ref | C-o: session | A-s: scopes | A-a/p/m/r/t/o: scope | C-/: preview",
		},
		actions = actions,
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
		local preview_dir = vim.fn.tempname()
		vim.fn.mkdir(preview_dir, "p")
		for idx, session in ipairs(sessions) do
			local entry = ("%04d  %s  %s  %s"):format(
				idx,
				timestamp(session.time and session.time.updated),
				session.agent or "",
				session.title or session.id
			)
			table.insert(entries, entry)
			entry_map[entry] = session
			vim.fn.writefile(session_preview_lines(session), ("%s/%04d.md"):format(preview_dir, idx))
		end

		fzf.fzf_exec(entries, {
			prompt = "OpenCode Sessions> ",
			preview = preview_command(preview_dir),
			winopts = {
				on_close = function()
					vim.fn.delete(preview_dir, "rf")
				end,
			},
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

-- ============================================================
-- Grep: live ripgrep over session message content
-- ============================================================

local function grep_git_root()
	local git_dir = vim.fs.find(".git", { path = vim.fn.getcwd(), upward = true })[1]
	return git_dir and vim.fn.fnamemodify(git_dir, ":h") or nil
end

local function grep_worktree_roots(callback)
	local root = grep_git_root()
	if not root then
		callback({})
		return
	end
	vim.system({ "git", "-C", root, "worktree", "list", "--porcelain" }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				callback({ root })
				return
			end
			local roots = {}
			for line in (result.stdout or ""):gmatch("[^\n]+") do
				local wt = line:match("^worktree (.+)$")
				if wt then
					table.insert(roots, wt)
				end
			end
			callback(#roots > 0 and roots or { root })
		end)
	end)
end

local function grep_session_matches(session, scope, context)
	local dir = (session.directory or ""):gsub("/+$", "")
	if scope == "worktree" then
		local wt = (context.worktree_root or ""):gsub("/+$", "")
		return dir == wt or vim.startswith(dir, wt .. "/")
	elseif scope == "repo" then
		for _, wt in ipairs(context.worktree_roots or {}) do
			wt = wt:gsub("/+$", "")
			if dir == wt or vim.startswith(dir, wt .. "/") then
				return true
			end
		end
		return false
	end
	return true -- global
end

local function open_grep_picker(items, scope, opts)
	opts = opts or {}
	local fzf = require("fzf-lua")

	if #items == 0 then
		vim.notify("No OpenCode messages to grep", vim.log.levels.WARN, { title = "opencode" })
		return
	end

	local temp_dir = vim.fn.tempname()
	if not pcall(vim.fn.mkdir, temp_dir, "p") then
		vim.notify("Could not create OpenCode grep temp dir", vim.log.levels.ERROR, { title = "opencode" })
		return
	end

	local item_map = {}
	for idx, item in ipairs(items) do
		local key = ("%06d"):format(idx)
		item_map[key] = item
		local session_label = item.session and (item.session.title or item.session.id) or "unknown"
		local header = ("[%s/%s]  %s  |  %s"):format(
			item.role or "?",
			item.kind or "?",
			item.time or "",
			session_label
		)
		if item.tool and item.tool ~= "" then
			header = header .. "  [" .. item.tool .. "]"
		end
		local content = header .. "\n" .. string.rep("─", 60) .. "\n\n" .. vim.trim(item.text or "") .. "\n"
		vim.fn.writefile(vim.split(content, "\n", { plain = true }), temp_dir .. "/" .. key .. ".md")
	end

	local function get_item(selected)
		if not selected or #selected == 0 then
			return nil
		end
		local file_info = require("fzf-lua.path").entry_to_file(selected[1], { cwd = temp_dir })
		if not file_info or not file_info.path then
			return nil
		end
		local key = vim.fn.fnamemodify(file_info.path, ":t:r")
		return item_map[key]
	end

	local function reopen(new_scope, ao)
		local q = ao and ao.__call_opts and ao.__call_opts.query or ""
		vim.schedule(function()
			M.grep({ scope = new_scope, query = q })
		end)
	end

	fzf.live_grep({
		cwd = temp_dir,
		prompt = ("OpenCode Grep (%s)> "):format(scope or "session"),
		query = opts.query or "",
		rg_opts = "--column --line-number --no-heading --color=always --smart-case --max-columns=512",
		winopts = {
			on_close = function()
				vim.fn.delete(temp_dir, "rf")
			end,
		},
		fzf_opts = {
			["--header"] = "Enter: transcript+switch | C-l: switch live | C-a: append | C-y: yank | A-s: session | A-l: worktree | A-r: repo | A-g: global",
		},
		actions = {
			["default"] = function(selected)
				local item = get_item(selected)
				if not item then
					return
				end
				vim.schedule(function()
					open_transcript(item)
					switch_tui_session(item)
				end)
			end,
			["ctrl-l"] = function(selected)
				switch_tui_session(get_item(selected))
			end,
			["ctrl-a"] = function(selected)
				local item = get_item(selected)
				if item then
					send_to_prompt({ item })
				end
			end,
			["ctrl-y"] = function(selected)
				local item = get_item(selected)
				if item then
					yank_items({ item })
				end
			end,
			["alt-s"] = function(_, ao) reopen("session", ao) end,
			["alt-l"] = function(_, ao) reopen("worktree", ao) end,
			["alt-r"] = function(_, ao) reopen("repo", ao) end,
			["alt-g"] = function(_, ao) reopen("global", ao) end,
		},
	})
end

function M.grep(opts)
	opts = opts or {}
	local scope = opts.scope or "session"
	local api = require("config.opencode_messages")

	if scope == "session" then
		api.latest_session(function(session, err)
			if not session then
				api.notify_error(err)
				return
			end
			api.messages(session.id, function(messages, merr)
				if not messages then
					api.notify_error(merr)
					return
				end
				open_grep_picker(build_items(session, messages, "all"), scope, opts)
			end)
		end)
		return
	end

	local function fetch_and_open(context)
		api.sessions(function(sessions, err)
			if not sessions then
				api.notify_error(err)
				return
			end
			local filtered = vim.tbl_filter(function(s)
				return scope == "global" or grep_session_matches(s, scope, context)
			end, sessions)
			if #filtered == 0 then
				vim.notify(
					"No OpenCode sessions match scope: " .. scope,
					vim.log.levels.WARN,
					{ title = "opencode" }
				)
				return
			end
			local pending = #filtered
			local all_items = {}
			for _, session in ipairs(filtered) do
				api.messages(session.id, function(messages)
					if messages then
						vim.list_extend(all_items, build_items(session, messages, "all"))
					end
					pending = pending - 1
					if pending == 0 then
						open_grep_picker(all_items, scope, opts)
					end
				end)
			end
		end)
	end

	if scope == "worktree" then
		fetch_and_open({ worktree_root = grep_git_root() })
	elseif scope == "repo" then
		grep_worktree_roots(function(roots)
			fetch_and_open({ worktree_roots = roots })
		end)
	else
		fetch_and_open({})
	end
end

return M

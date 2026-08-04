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

local session_scopes = {
	["local"] = "Local",
	repo = "Git",
	global = "Global",
}

local session_scope_order = { "local", "repo", "global" }
local aggregate_revision = 0
local aggregate_concurrency = 8

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

local function prompt_payload(item)
	return item_payload(item):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") .. " "
end

local function prompt_lifecycle(prompt, cleanup)
	local stage = { completed = false, transitioned = false }
	local function on_close()
		if cleanup then
			pcall(cleanup)
		end
		vim.schedule(function()
			if not stage.completed and not stage.transitioned and prompt and prompt.owner and prompt.owner.restore then
				prompt.owner.restore()
			end
		end)
	end
	return stage, on_close
end

local function restore_prompt(opts)
	local owner = opts and opts.prompt and opts.prompt.owner
	if owner and owner.restore then
		owner.restore()
	end
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
		"Directory: " .. (session.directory or ""),
		"Project: " .. ((session.project and (session.project.name or session.project.id)) or ""),
		"Project ID: " .. (session.projectID or (session.project and session.project.id) or ""),
		"Project worktree: " .. ((session.project and session.project.worktree) or ""),
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

local function action_query(action_opts, fallback)
	return (action_opts and action_opts.last_query)
		or (action_opts and action_opts.__call_opts and action_opts.__call_opts.query)
		or fallback
		or ""
end

local function canonical(path)
	if not path or path == "" then
		return nil
	end
	local normalized = path == "/" and path or path:gsub("/+$", "")
	local http = require("config.opencode_http")
	local resolved = http.canonical(normalized)
	if resolved ~= normalized or normalized == "/" then
		return resolved
	end

	local current = normalized
	local suffix = {}
	while current ~= "/" do
		local parent, name = current:match("^(.*)/([^/]+)$")
		if not parent or not name then
			break
		end
		if parent == "" then
			parent = "/"
		end
		table.insert(suffix, 1, name)
		local resolved_parent = http.canonical(parent)
		if resolved_parent and resolved_parent ~= parent then
			return (resolved_parent:gsub("/+$", "")) .. "/" .. table.concat(suffix, "/")
		end
		current = parent
	end
	return resolved
end

local function git_root(path)
	local git_dir = vim.fs.find(".git", { path = path, upward = true })[1]
	return git_dir and canonical(vim.fn.fnamemodify(git_dir, ":h")) or nil
end

local function session_context(opts)
	if opts and opts.session_context then
		return opts.session_context
	end
	local cwd = canonical((opts and opts.cwd) or vim.fn.getcwd()) or ((opts and opts.cwd) or vim.fn.getcwd())
	local worktree_root = git_root(cwd)
	return {
		cwd = cwd,
		worktree_root = worktree_root,
		route_dir = worktree_root or cwd,
	}
end

local function path_within(path, root)
	if not path or not root then
		return false
	end
	if root == "/" then
		return vim.startswith(path, "/")
	end
	return path == root or vim.startswith(path, root .. "/")
end

local function resolve_worktree_roots(context, callback, refresh)
	if context.worktree_roots and not refresh then
		callback(context.worktree_roots)
		return
	end
	if not context.worktree_root then
		callback(nil, "Current directory is not in a Git repository")
		return
	end

	vim.system({ "git", "-C", context.worktree_root, "worktree", "list", "--porcelain" }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				callback(nil, "Could not list Git worktrees")
				return
			end

			local roots = {}
			local seen = {}
			for line in (result.stdout or ""):gmatch("[^\n]+") do
				local root = line:match("^worktree (.+)$")
				root = root and canonical(root) or nil
				if root and not seen[root] then
					seen[root] = true
					table.insert(roots, root)
				end
			end
			if #roots == 0 then
				callback(nil, "Could not parse Git worktrees")
				return
			end

			context.worktree_roots = roots
			callback(roots)
		end)
	end)
end

local function session_matches_scope(session, scope, context)
	if scope == "global" then
		return true
	end
	local dir = canonical(session and session.directory)
	if not dir then
		return false
	end
	if scope == "local" then
		return dir == context.cwd
	end
	for _, root in ipairs(context.worktree_roots or {}) do
		if path_within(dir, root) then
			return true
		end
	end
	return false
end

local function live_target_allowed(item, context)
	local dir = canonical(item and item.session and item.session.directory)
	if not dir or not context then
		return false
	end
	if context.worktree_root then
		return path_within(dir, context.worktree_root)
	end
	return dir == context.cwd
end

local function notify_live_route_rejection()
	vim.notify(
		"OpenCode session is outside the current live route",
		vim.log.levels.WARN,
		{ title = "opencode" }
	)
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
	require("config.opencode_prompt").append(payload .. "\n", {
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
	require("config.opencode_prompt").append(payload .. "\n", {
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
	require("config.opencode_prompt").append(payload .. "\n", {
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

local function switch_tui_session(item, context)
	if not item or not item.session or not item.session.id then
		return
	end
	if not live_target_allowed(item, context) then
		notify_live_route_rejection()
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
	end, { dir = context.route_dir })
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

local function sync_live_timeline(item, context)
	if not item or not item.session or not item.session.id then
		return false
	end
	if not live_target_allowed(item, context) then
		notify_live_route_rejection()
		return false
	end

	local anchor = resolve_timeline_anchor(item)
	if not anchor then
		vim.notify(tui_error("No OpenCode timeline anchor found for selection"), vim.log.levels.WARN, { title = "opencode" })
		return false
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

				http.publish_commands(commands, function(move_ok, move_output)
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
				end, { dir = context.route_dir })
			end, 80)
		end, { dir = context.route_dir })
	end, { dir = context.route_dir })
	return true
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

local function opencode_server_url()
	local url = vim.g.opencode_server_url or vim.env.OPENCODE_SERVER_URL or "http://127.0.0.1:4096"
	return url:gsub("/+$", "")
end

local function opencode_bin_path()
	local bin = vim.fn.expand("~/dotfiles/scripts/bin/opencode")
	if vim.fn.executable(bin) == 1 then
		return bin
	end
	local found = vim.fn.exepath("opencode")
	return found ~= "" and found or "opencode"
end

local function fork_pane_launch(fork_session_id, dir, source_session_id)
	if not vim.env.TMUX or vim.env.TMUX == "" then
		vim.notify("forkpane requires a running tmux session", vim.log.levels.ERROR, { title = "opencode" })
		return
	end

	local handoff = dir .. "/.claude/forkpane.local.md"
	pcall(vim.fn.mkdir, vim.fn.fnamemodify(handoff, ":h"), "p")
	pcall(vim.fn.writefile, {
		"# OpenCode Fork Pane Handoff",
		"",
		"- Source session: " .. (source_session_id or ""),
		"- Forked session: " .. fork_session_id,
		"- Source worktree: " .. dir,
	}, handoff)

	local cmd = string.format(
		"tmux split-window -h -c %s -e OPENCODE_TMUX_WRAPPER_ACTIVE=1 %s attach %s --session %s",
		vim.fn.shellescape(dir),
		vim.fn.shellescape(opencode_bin_path()),
		vim.fn.shellescape(opencode_server_url()),
		vim.fn.shellescape(fork_session_id)
	)
	vim.fn.jobstart(cmd, { detach = true })
	vim.notify("Fork launched: " .. fork_session_id, vim.log.levels.INFO, { title = "opencode" })
end

local function fork_worktree_launch(fork_session_id, branch_name, item)
	local dir = (item.session and item.session.directory) or vim.fn.getcwd()
	local source_session_id = (item.session and item.session.id) or ""
	local message_id = item.message_id or ""
	local tmux_pane = vim.env.TMUX_PANE or ""

	local prompt = string.format(
		"Fork OpenCode session '%s' into a fresh worktree for branch '%s'. Continue the conversation in that isolated worktree. Source worktree: %s.",
		source_session_id,
		branch_name,
		dir
	)
	if message_id ~= "" then
		prompt = prompt .. " Fork point message: " .. message_id .. "."
	end

	local env_pairs = {
		{ "WT_AUTO_OPENCODE",            "1" },
		{ "WT_OPENCODE_REQUIRE_TMUX",    "1" },
		{ "WT_OPENCODE_TMUX_PANE",       tmux_pane },
		{ "WT_OPENCODE_SESSION",         fork_session_id },
		{ "WT_OPENCODE_PROMPT",          prompt },
		{ "WT_OPENCODE_FORK_SESSION",    source_session_id },
		{ "WT_OPENCODE_FORKED_SESSION",  fork_session_id },
		{ "WT_OPENCODE_FORK_MESSAGE",    message_id },
		{ "WT_OPENCODE_FORK_SOURCE_DIR", dir },
	}
	local env_str = table.concat(vim.tbl_map(function(p)
		return p[1] .. "=" .. vim.fn.shellescape(p[2])
	end, env_pairs), " ")

	local cmd = string.format(
		"cd %s && env %s wt switch --create %s",
		vim.fn.shellescape(dir),
		env_str,
		vim.fn.shellescape(branch_name)
	)

	vim.notify("Creating fork worktree: " .. branch_name .. "...", vim.log.levels.INFO, { title = "opencode" })
	vim.fn.jobstart({ "fish", "-c", cmd }, {
		on_exit = function(_, code)
			vim.schedule(function()
				if code == 0 then
					vim.notify("Fork worktree created: " .. branch_name, vim.log.levels.INFO, { title = "opencode" })
				else
					vim.notify("gwtfork failed (exit " .. code .. ")", vim.log.levels.ERROR, { title = "opencode" })
				end
			end)
		end,
	})
end

local function fork_pane_from_item(item)
	if not item or not item.session or not item.session.id then
		vim.notify("No session to fork from", vim.log.levels.WARN, { title = "opencode" })
		return
	end
	local dir = (item.session and item.session.directory) or vim.fn.getcwd()
	require("config.opencode_http").fork_session(item.session.id, {
		message_id = item.message_id,
		dir = dir,
	}, function(fork_id, err)
		if not fork_id then
			vim.notify("Fork failed: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "opencode" })
			return
		end
		fork_pane_launch(fork_id, dir, item.session.id)
	end)
end

local function fork_worktree_from_item(item, branch_name)
	if not item or not item.session or not item.session.id then
		vim.notify("No session to fork from", vim.log.levels.WARN, { title = "opencode" })
		return
	end
	local dir = (item.session and item.session.directory) or vim.fn.getcwd()
	require("config.opencode_http").fork_session(item.session.id, {
		message_id = item.message_id,
		dir = dir,
	}, function(fork_id, err)
		if not fork_id then
			vim.notify("Fork failed: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "opencode" })
			return
		end
		fork_worktree_launch(fork_id, branch_name, item)
	end)
end

local function open_message_picker(items, scope, opts)
	opts = vim.tbl_extend("force", {}, opts or {})
	opts.session_scope = opts.session_scope or "local"
	opts.session_context = session_context(opts)
	local fzf = require("fzf-lua")
	local label = opts.label or scopes[scope] or scopes.all
	if #items == 0 and not opts.allow_empty then
		vim.notify("No OpenCode " .. label:lower() .. " found", vim.log.levels.WARN, { title = "opencode" })
		restore_prompt(opts)
		return
	end

	local entries = {}
	local entry_map = {}
	local preview_dir = vim.fn.tempname()
	local ok_mkdir = pcall(vim.fn.mkdir, preview_dir, "p")
	if not ok_mkdir then
		vim.notify("Could not create OpenCode preview directory", vim.log.levels.ERROR, { title = "opencode" })
		restore_prompt(opts)
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
			restore_prompt(opts)
			return
		end
	end

	local function first_item(selected)
		return selected_items(selected, entry_map)[1]
	end
	local stage, on_close = prompt_lifecycle(opts.prompt, function()
		vim.fn.delete(preview_dir, "rf")
	end)

	local function transition(callback)
		stage.transitioned = true
		vim.schedule(callback)
	end

	local function route_opts(action_opts, extra)
		return vim.tbl_extend("force", {
			prompt = opts.prompt,
			query = action_query(action_opts, opts.query),
			session = opts.session,
			session_scope = opts.session_scope,
			session_context = opts.session_context,
		}, extra or {})
	end

	local function launch_scope(new_scope, action_opts)
		if opts.all_sessions then
			M.all_sessions(new_scope, route_opts(action_opts))
		else
			M.messages(new_scope, route_opts(action_opts))
		end
	end

	local function reopen(new_scope, action_opts)
		transition(function() launch_scope(new_scope, action_opts) end)
	end

	local function pick_scope(action_opts)
		local parent_query = action_query(action_opts, opts.query)
		local scope_entries = {}
		local scope_map = {}
		for _, scope_name in ipairs(scope_order) do
			local entry = ("%-12s %s"):format(scope_name, scopes[scope_name] or scope_name)
			table.insert(scope_entries, entry)
			scope_map[entry] = scope_name
		end

		local scope_stage, scope_close = prompt_lifecycle(opts.prompt)
		fzf.fzf_exec(scope_entries, {
			prompt = "OpenCode Scope> ",
			winopts = { on_close = scope_close },
			fzf_opts = { ["--header"] = "Enter: reopen picker with selected scope" },
			actions = {
				["enter"] = function(selected)
					local utils = require("fzf-lua.utils")
					local key = selected and selected[1] and utils.strip_ansi_coloring(selected[1])
					local new_scope = key and scope_map[key]
					if new_scope then
						scope_stage.transitioned = true
						vim.schedule(function() launch_scope(new_scope, { last_query = parent_query }) end)
					end
				end,
			},
		})
	end

	local function launch_location(new_scope, query)
		local function launch()
			M.all_sessions(scope, route_opts({ last_query = query }, { session_scope = new_scope }))
		end
		if new_scope ~= "repo" then
			launch()
			return
		end
		resolve_worktree_roots(opts.session_context, function(_, err)
			if err then
				vim.notify(
					("Git scope unavailable; keeping %s (not widened to Global)"):format(session_scopes[opts.session_scope]),
					vim.log.levels.WARN,
					{ title = "opencode" }
				)
				M.all_sessions(scope, route_opts({ last_query = query }))
				return
			end
			launch()
		end)
	end

	local function pick_location(action_opts)
		local parent_query = action_query(action_opts, opts.query)
		local entries = {}
		local entry_map = {}
		for _, name in ipairs(session_scope_order) do
			local entry = ("%-12s %s sessions"):format(name, session_scopes[name])
			table.insert(entries, entry)
			entry_map[entry] = name
		end
		local location_stage, location_close = prompt_lifecycle(opts.prompt)
		fzf.fzf_exec(entries, {
			prompt = "OpenCode Location> ",
			winopts = { on_close = location_close },
			fzf_opts = { ["--header"] = "Enter: filter aggregate search by location" },
			actions = {
				enter = function(selected)
					local utils = require("fzf-lua.utils")
					local key = selected and selected[1] and utils.strip_ansi_coloring(selected[1])
					local new_scope = key and (entry_map[key] or key:match("^(%S+)"))
					if session_scopes[new_scope] then
						location_stage.transitioned = true
						vim.schedule(function() launch_location(new_scope, parent_query) end)
					end
				end,
			},
		})
	end

	local actions = {
		["default"] = function(selected)
			local item = first_item(selected)
			if not item then return end
			if opts.enter_action then
				opts.enter_action(item)
				return
			end
			vim.schedule(function()
				open_transcript(item)
			end)
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
			switch_tui_session(first_item(selected), opts.session_context)
		end,
		["ctrl-l"] = function(selected)
			sync_live_timeline(first_item(selected), opts.session_context)
		end,
		["ctrl-f"] = function(selected)
			fork_pane_from_item(first_item(selected))
		end,
		["ctrl-w"] = function(selected)
			local item = first_item(selected)
			if not item then return end
			vim.ui.input({ prompt = "Fork branch name: " }, function(branch_name)
				if branch_name and branch_name ~= "" then
					fork_worktree_from_item(item, branch_name)
				end
			end)
		end,
		["alt-l"] = function(selected)
			local item = first_item(selected)
			if item then
				vim.schedule(function()
					open_transcript(item)
				end)
				sync_live_timeline(item, opts.session_context)
			end
		end,
		["alt-s"] = function(_, action_opts)
			transition(function() pick_scope(action_opts) end)
		end,
		["ctrl-s"] = function(_, action_opts)
			transition(function()
				M.sessions(scope, route_opts(action_opts))
			end)
		end,
		["ctrl-r"] = function(_, action_opts)
			transition(function()
				if opts.all_sessions then
					M.all_sessions(scope, route_opts(action_opts, { refresh = true }))
				else
					M.messages(scope, route_opts(action_opts, { refresh = true }))
				end
			end)
		end,
	}
	if opts.prompt then
		actions = {
			["enter"] = function(selected)
				local item = first_item(selected)
				if not item then return end
				stage.completed = true
				opts.prompt.owner.insert(prompt_payload(item))
			end,
			["ctrl-l"] = function(selected)
				if sync_live_timeline(first_item(selected), opts.session_context) then
					stage.completed = true
				end
			end,
			["alt-s"] = function(_, action_opts)
				transition(function() pick_scope(action_opts) end)
			end,
			["ctrl-s"] = function(_, action_opts)
				transition(function() M.sessions(scope, route_opts(action_opts)) end)
			end,
			["ctrl-r"] = function(_, action_opts)
				transition(function()
					if opts.all_sessions then
						M.all_sessions(scope, route_opts(action_opts, { refresh = true }))
					else
						M.messages(scope, route_opts(action_opts, { refresh = true }))
					end
				end)
			end,
		}
	end

	local scope_actions = {
		["alt-a"] = "all",
		["alt-p"] = "prompts",
		["alt-m"] = "assistant",
		["alt-r"] = "reasoning",
		["alt-t"] = "tools",
		["alt-o"] = "tool_output",
	}
	for key, new_scope in pairs(scope_actions) do
		actions[key] = function(_, action_opts)
			reopen(new_scope, action_opts)
		end
	end
	if opts.all_sessions then
		actions["alt-g"] = function(_, action_opts)
			transition(function() pick_location(action_opts) end)
		end
	end

	local header = opts.prompt
			and "Enter: insert | C-l: live | A-s: scopes | A-a/p/m/r/t/o: scope | C-s: sessions | C-r: refresh | C-/: preview"
		or "Enter: transcript | A-l: transcript+live | C-l: live | C-f: forkpane | C-w: gwtfork | C-a: append | C-x: context | C-u: resume | C-y: copy | C-b: ref | C-o: session | A-s: scopes | A-a/p/m/r/t/o: scope | C-/: preview"
	if opts.all_sessions then
		header = header .. " | A-g: location"
	end

	fzf.fzf_exec(entries, {
		prompt = "OpenCode " .. label .. "> ",
		query = opts.query or "",
		preview = preview_command(preview_dir),
		winopts = {
			on_close = on_close,
		},
		fzf_opts = {
			["--multi"] = true,
			["--header"] = header,
		},
		actions = actions,
	})
end

function M.messages(scope, opts)
	scope = scope or "all"
	opts = vim.tbl_extend("force", {}, opts or {})
	opts.session_scope = opts.session_scope or "local"
	opts.session_context = session_context(opts)
	local api = require("config.opencode_messages")

	local function fetch_for_session(session)
		api.messages(session.id, function(messages, err)
			if not messages then
				api.notify_error(err)
				restore_prompt(opts)
				return
			end
			open_message_picker(
				build_items(session, messages, scope),
				scope,
				vim.tbl_extend("force", opts, { session = session })
			)
		end, {
			dir = canonical(session.directory) or opts.session_context.route_dir,
			refresh = opts.refresh,
		})
	end

	if opts.session then
		fetch_for_session(opts.session)
		return
	end

	api.latest_session(function(session, err)
		if not session then
			api.notify_error(err)
			restore_prompt(opts)
			return
		end
		fetch_for_session(session)
	end, { dir = opts.session_context.route_dir, refresh = opts.refresh })
end

function M.all_sessions(scope, opts)
	scope = scope or "all"
	opts = vim.tbl_extend("force", {}, opts or {})
	opts.session_scope = opts.session_scope or "local"
	opts.session_context = session_context(opts)
	aggregate_revision = aggregate_revision + 1
	local revision = aggregate_revision
	local api = require("config.opencode_messages")

	local function open_aggregate(items)
		if revision ~= aggregate_revision then
			return
		end
		open_message_picker(items, scope, vim.tbl_extend("force", opts, {
			label = ("All sessions (%s) %s"):format(session_scopes[opts.session_scope], scopes[scope] or scopes.all),
			all_sessions = true,
			allow_empty = true,
		}))
	end

	local function fetch_catalog()
		api.sessions(function(sessions, err)
			if revision ~= aggregate_revision then
				return
			end
			if not sessions then
				api.notify_error(err)
				restore_prompt(opts)
				return
			end

			local filtered = vim.tbl_filter(function(session)
				return session_matches_scope(session, opts.session_scope, opts.session_context)
			end, sessions)
			if #filtered == 0 then
				open_aggregate({})
				return
			end

			local buckets = {}
			local next_index = 1
			local active = 0
			local remaining = #filtered
			local failed = 0
			local pumping = false
			local opened = false
			local pump

			local function finish()
				if opened or remaining ~= 0 or revision ~= aggregate_revision then
					return
				end
				opened = true
				local items = {}
				for index = 1, #filtered do
					vim.list_extend(items, buckets[index] or {})
				end
				if failed > 0 then
					vim.notify(
						("OpenCode aggregate loaded %d sessions; %d failed"):format(#filtered - failed, failed),
						vim.log.levels.WARN,
						{ title = "opencode" }
					)
				end
				open_aggregate(items)
			end

			pump = function()
				if pumping or revision ~= aggregate_revision then
					return
				end
				pumping = true
				while active < aggregate_concurrency and next_index <= #filtered do
					local index = next_index
					local session = filtered[index]
					next_index = next_index + 1
					active = active + 1
					api.messages(session.id, function(messages)
						if revision ~= aggregate_revision then
							return
						end
						active = active - 1
						remaining = remaining - 1
						if messages then
							buckets[index] = build_items(session, messages, scope)
						else
							failed = failed + 1
						end
						if not pumping then
							if remaining == 0 then
								finish()
							else
								pump()
							end
						end
					end, {
						dir = canonical(session.directory) or opts.session_context.route_dir,
						refresh = opts.refresh,
					})
				end
				pumping = false
				if remaining == 0 then
					finish()
				end
			end

			pump()
		end, {
			catalog = "global",
			dir = opts.session_context.route_dir,
			refresh = opts.refresh,
		})
	end

	if opts.session_scope == "repo" and not opts.session_context.worktree_roots then
		resolve_worktree_roots(opts.session_context, function(_, err)
			if revision ~= aggregate_revision then
				return
			end
			if err then
				vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
				restore_prompt(opts)
				return
			end
			fetch_catalog()
		end)
		return
	end
	fetch_catalog()
end

function M.sessions(scope, opts)
	scope = scope or "all"
	opts = vim.tbl_extend("force", {}, opts or {})
	opts.session_scope = opts.session_scope or "local"
	opts.session_context = session_context(opts)
	local api = require("config.opencode_messages")

	local function fetch_catalog()
	api.sessions(function(sessions, err)
		if not sessions then
			api.notify_error(err)
			restore_prompt(opts)
			return
		end

		sessions = vim.tbl_filter(function(session)
			return session_matches_scope(session, opts.session_scope, opts.session_context)
		end, sessions)

		local fzf = require("fzf-lua")
		local entries = {}
		local entry_map = {}
		local preview_dir = vim.fn.tempname()
		if not pcall(vim.fn.mkdir, preview_dir, "p") then
			vim.notify("Could not create OpenCode preview directory", vim.log.levels.ERROR, { title = "opencode" })
			restore_prompt(opts)
			return
		end
		for idx, session in ipairs(sessions) do
			local project = (session.project and (session.project.name or session.project.id)) or session.projectID or ""
			local entry = ("%04d  %s  %-10s %-18s %-36s %s"):format(
				idx,
				timestamp(session.time and session.time.updated),
				session.agent or "",
				one_line(project, 18),
				one_line(session.directory or "", 36),
				session.title or session.id
			)
			table.insert(entries, entry)
			entry_map[entry] = session
			if not pcall(vim.fn.writefile, session_preview_lines(session), ("%s/%04d.md"):format(preview_dir, idx)) then
				vim.fn.delete(preview_dir, "rf")
				vim.notify("Could not write OpenCode preview", vim.log.levels.ERROR, { title = "opencode" })
				restore_prompt(opts)
				return
			end
		end

		local stage, on_close = prompt_lifecycle(opts.prompt, function()
			vim.fn.delete(preview_dir, "rf")
		end)
		local function route_opts(action_opts, extra)
			return vim.tbl_extend("force", {
				prompt = opts.prompt,
				query = action_query(action_opts, opts.query),
				session_scope = opts.session_scope,
				session_context = opts.session_context,
			}, extra or {})
		end

		local function transition(callback)
			stage.transitioned = true
			vim.schedule(callback)
		end

		local function relaunch(new_scope, action_opts)
			local next_opts = route_opts(action_opts, { session_scope = new_scope })
			if new_scope ~= "repo" then
				transition(function() M.sessions(scope, next_opts) end)
				return
			end
			stage.transitioned = true
			resolve_worktree_roots(opts.session_context, function(_, resolve_err)
				if resolve_err then
					vim.notify(
						("Git scope unavailable; keeping %s (not widened to Global)"):format(session_scopes[opts.session_scope]),
						vim.log.levels.WARN,
						{ title = "opencode" }
					)
					next_opts.session_scope = opts.session_scope
				end
				vim.schedule(function() M.sessions(scope, next_opts) end)
			end, true)
		end

		local actions = {
			["default"] = function(selected)
				local item = selected_items(selected, entry_map)[1]
				if not item then
					return
				end
				transition(function() M.messages(scope, route_opts(nil, { session = item })) end)
			end,
			["ctrl-o"] = function(selected)
				local item = selected_items(selected, entry_map)[1]
				if item then
					switch_tui_session({ session = item }, opts.session_context)
				end
			end,
		}
		if opts.prompt then
			actions = {
				["enter"] = function(selected, action_opts)
					local item = selected_items(selected, entry_map)[1]
					if not item then return end
					transition(function() M.messages(scope, route_opts(action_opts, { session = item })) end)
				end,
			}
		end
		actions["alt-g"] = function(_, action_opts) relaunch("global", action_opts) end
		actions["alt-s"] = function(_, action_opts) relaunch("repo", action_opts) end
		actions["alt-l"] = function(_, action_opts) relaunch("local", action_opts) end

		fzf.fzf_exec(entries, {
			prompt = ("OpenCode Sessions (%s)> "):format(session_scopes[opts.session_scope]),
			query = opts.query or "",
			preview = preview_command(preview_dir),
			winopts = {
				on_close = on_close,
			},
			fzf_opts = {
				["--header"] = opts.prompt
					and "A-g: global | A-s: git | A-l: local | Enter: browse selected session | C-/: preview"
					or "A-g: global | A-s: git | A-l: local | Enter: search selected session | C-o: switch live pane",
			},
			actions = actions,
		})
	end, { catalog = "global", dir = opts.session_context.route_dir, refresh = opts.refresh })
	end

	if opts.session_scope == "repo" and not opts.session_context.worktree_roots then
		resolve_worktree_roots(opts.session_context, function(_, err)
			if err then
				vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
				restore_prompt(opts)
				return
			end
			fetch_catalog()
		end)
		return
	end
	fetch_catalog()
end

function M.all(opts)
	M.messages("all", opts)
end
function M.prompts(opts)
	M.messages("prompts", opts)
end
function M.assistant(opts)
	M.messages("assistant", opts)
end
function M.reasoning(opts)
	M.messages("reasoning", opts)
end
function M.tools(opts)
	M.messages("tools", opts)
end
function M.tool_output(opts)
	M.messages("tool_output", opts)
end

-- ============================================================
-- Grep: live ripgrep over session message content
-- ============================================================

local function grep_session_matches(session, scope, context)
	local dir = canonical(session.directory)
	if scope == "worktree" then
		return path_within(dir, context.worktree_root)
	elseif scope == "repo" then
		for _, wt in ipairs(context.worktree_roots or {}) do
			if path_within(dir, wt) then
				return true
			end
		end
		return false
	end
	return true -- global
end

local function open_grep_picker(items, scope, opts)
	opts = vim.tbl_extend("force", {}, opts or {})
	opts.session_context = session_context(opts)
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
		local q = action_query(ao, opts.query)
		vim.schedule(function()
			M.grep({ scope = new_scope, query = q, session_context = opts.session_context })
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
					switch_tui_session(item, opts.session_context)
				end)
			end,
			["ctrl-l"] = function(selected)
				switch_tui_session(get_item(selected), opts.session_context)
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
	opts = vim.tbl_extend("force", {}, opts or {})
	opts.session_context = session_context(opts)
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
			end, { dir = canonical(session.directory) or opts.session_context.route_dir })
		end, { dir = opts.session_context.route_dir })
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
			local all_items = {}
			local next_index = 1
			local active = 0
			local remaining = #filtered
			local pumping = false
			local opened = false
			local pump

			local function finish()
				if opened or remaining ~= 0 then
					return
				end
				opened = true
				open_grep_picker(all_items, scope, opts)
			end

			pump = function()
				if pumping then
					return
				end
				pumping = true
				while active < aggregate_concurrency and next_index <= #filtered do
					local session = filtered[next_index]
					next_index = next_index + 1
					active = active + 1
					api.messages(session.id, function(messages)
						active = active - 1
						remaining = remaining - 1
						if messages then
							vim.list_extend(all_items, build_items(session, messages, "all"))
						end
						if not pumping then
							if remaining == 0 then
								finish()
							else
								pump()
							end
						end
					end, { dir = canonical(session.directory) or opts.session_context.route_dir })
				end
				pumping = false
				if remaining == 0 then
					finish()
				end
			end

			pump()
		end, { catalog = "global", dir = opts.session_context.route_dir })
	end

	if scope == "worktree" then
		if not opts.session_context.worktree_root then
			vim.notify("Current directory is not in a Git repository", vim.log.levels.WARN, { title = "opencode" })
			return
		end
		fetch_and_open(opts.session_context)
	elseif scope == "repo" then
		resolve_worktree_roots(opts.session_context, function(_, err)
			if err then
				vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
				return
			end
			fetch_and_open(opts.session_context)
		end)
	else
		fetch_and_open(opts.session_context)
	end
end

function M.forkpane()
	local api = require("config.opencode_messages")
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
			open_message_picker(build_items(session, messages, "prompts"), "prompts", {
				session = session,
				label = "Fork Point",
				enter_action = fork_pane_from_item,
			})
		end)
	end)
end

function M.gwtfork()
	vim.ui.input({ prompt = "Fork branch name: " }, function(branch_name)
		if not branch_name or branch_name == "" then
			return
		end
		local api = require("config.opencode_messages")
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
				open_message_picker(build_items(session, messages, "prompts"), "prompts", {
					session = session,
					label = "gwtfork: " .. branch_name,
					enter_action = function(item)
						fork_worktree_from_item(item, branch_name)
					end,
				})
			end)
		end)
	end)
end

return M

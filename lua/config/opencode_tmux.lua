local M = {}

local max_parent_depth = 64

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
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

local function run(args, opts)
	if not vim.system then
		return { code = 1, stdout = "", stderr = "vim.system is unavailable" }
	end
	local ok, process = pcall(vim.system, args, { text = true, stdin = opts and opts.stdin })
	if not ok then
		return { code = 1, stdout = "", stderr = tostring(process) }
	end
	local wait_ok, result = pcall(function()
		return process:wait()
	end)
	if not wait_ok then
		return { code = 1, stdout = "", stderr = tostring(result) }
	end
	return result
end

local function command_is_opencode(command)
	local words = {}
	for word in (command or ""):gmatch("%S+") do
		table.insert(words, word)
	end
	for index, word in ipairs(words) do
		if word:match("scripts/bin/oc$") then
			return true
		end
		local executable = word:match("([^/]+)$")
		if
			(executable == "opencode" or executable == "ocv")
			and (not words[index + 1] or words[index + 1] == "attach")
		then
			return true
		end
	end
	return false
end

local function read_record(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local record = {}
	for _, line in ipairs(lines) do
		local key, value = line:match("^([a-z]+)=(.*)$")
		if key then
			record[key] = value
		end
	end
	if not record.pid or not record.pane or not record.cwd or not record.command then
		return nil
	end
	return record
end

local function attach_records()
	local state_home = vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")
	local directory = state_home .. "/opencode/attaches"
	local ok, iterator = pcall(vim.fs.dir, directory)
	if not ok or not iterator then
		return {}
	end
	local records = {}
	for name, kind in iterator do
		if kind == "file" and name:match("^pane%-.+%.pid$") then
			local record = read_record(directory .. "/" .. name)
			if record then
				table.insert(records, record)
			end
		end
	end
	return records
end

local function source_window()
	local source_pane = vim.env.TMUX_PANE
	if type(source_pane) ~= "string" or not source_pane:match("^%%%d+$") then
		return nil
	end
	local result = run({ "tmux", "display-message", "-p", "-t", source_pane, "#{pane_id}\t#{window_id}" })
	if result.code ~= 0 then
		return nil
	end
	local pane, window = trim(result.stdout):match("^(%%%d+)\t(@%d+)$")
	if pane ~= source_pane then
		return nil
	end
	return window
end

local function window_panes(window)
	local result = run({
		"tmux",
		"list-panes",
		"-t",
		window,
		"-F",
		"#{pane_id}\t#{pane_pid}\t#{pane_current_path}",
	})
	if result.code ~= 0 then
		return nil
	end
	local panes = {}
	for line in (result.stdout or ""):gmatch("[^\r\n]+") do
		local pane, pid, cwd = line:match("^(%%%d+)\t(%d+)\t(.+)$")
		if pane then
			panes[pane] = { pid = pid, cwd = cwd }
		end
	end
	return panes
end

local function pid_belongs_to_pane(pid, pane_pid)
	local current = pid
	local seen = {}
	for _ = 1, max_parent_depth do
		if current == pane_pid then
			return true
		end
		if seen[current] then
			return false
		end
		seen[current] = true
		local result = run({ "ps", "-o", "ppid=", "-p", current })
		current = trim(result.stdout)
		if result.code ~= 0 or not current:match("^%d+$") or current == "0" or current == "1" then
			return false
		end
	end
	return false
end

local function resolve_target(project)
	local window = source_window()
	if not window then
		return nil
	end
	local panes = window_panes(window)
	if not panes then
		return nil
	end

	local candidates = {}
	for _, record in ipairs(attach_records()) do
		local pane = panes[record.pane]
		if
			pane
			and record.pane:match("^%%%d+$")
			and record.pid:match("^%d+$")
			and canonical(record.cwd) == project
			and canonical(pane.cwd) == project
			and command_is_opencode(record.command)
		then
			local live = run({ "ps", "-o", "command=", "-p", record.pid })
			if
				live.code == 0
				and command_is_opencode(trim(live.stdout))
				and pid_belongs_to_pane(record.pid, pane.pid)
			then
				table.insert(candidates, record.pane)
			end
		end
	end
	if #candidates ~= 1 then
		return nil
	end
	return candidates[1]
end

local function notify(message, level, title)
	vim.notify(message, level, { title = title or "opencode" })
end

local function fail_closed(text, opts, message)
	if opts.fallback_clipboard then
		vim.fn.setreg("+", text)
		message = message .. "; copied selection instead"
	end
	notify(message, vim.log.levels.WARN, opts.title)
	return false
end

function M.append_prompt(text, opts)
	opts = opts or {}
	if type(text) ~= "string" or text == "" then
		notify("No text to send", vim.log.levels.WARN, opts.title)
		return false
	end
	if vim.fn.executable("tmux") ~= 1 then
		return fail_closed(text, opts, "tmux is unavailable")
	end

	local project = canonical(opts.dir or vim.fn.getcwd())
	local pane = project and resolve_target(project) or nil
	if not pane then
		return fail_closed(text, opts, "No unique same-window OpenCode pane found")
	end

	local buffer = string.format("opencode-nvim-%d-%s", vim.fn.getpid(), tostring(vim.uv.hrtime()))
	local loaded = run({ "tmux", "load-buffer", "-b", buffer, "-" }, { stdin = text })
	if loaded.code ~= 0 then
		run({ "tmux", "delete-buffer", "-b", buffer })
		return fail_closed(text, opts, "Could not load the OpenCode tmux buffer")
	end
	local pasted = run({ "tmux", "paste-buffer", "-p", "-d", "-b", buffer, "-t", pane })
	if pasted.code ~= 0 then
		run({ "tmux", "delete-buffer", "-b", buffer })
		return fail_closed(text, opts, "Could not paste into the OpenCode pane")
	end

	notify(opts.success or "Sent text to OpenCode", vim.log.levels.INFO, opts.title)
	return true
end

return M

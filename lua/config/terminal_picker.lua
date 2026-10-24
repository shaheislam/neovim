local M = {}
local active
local keys = { ff = true, fF = true, cd = true, fg = true, fr = true, fR = true, fz = true,
	gg = true, gf = true, gl = true, gC = true, gb = true, gs = true, gd = true, gD = true,
	gP = true, gm = true, gx = true }

local function owner(pid)
	if type(pid) ~= "number" or pid <= 1 or pid % 1 ~= 0 then return end
	local processes = {}
	local result = vim.system({ "ps", "-axo", "pid=,ppid=,uid=" }, { text = true }):wait()
	if result.code ~= 0 then return end
	for id, parent, uid in result.stdout:gmatch("(%d+)%s+(%d+)%s+(%d+)") do
		processes[tonumber(id)] = { parent = tonumber(parent), uid = tonumber(uid) }
	end
	local ancestors = {}
	for _ = 1, 64 do
		local process = processes[pid]
		if not process or process.uid ~= vim.uv.getuid() then break end
		ancestors[pid] = true
		pid = process.parent
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local job = vim.b[buf].terminal_job_id
		if vim.bo[buf].buftype == "terminal" and job and vim.fn.jobwait({ job }, 0)[1] == -1 then
			local ok, root = pcall(vim.fn.jobpid, job)
			if ok and ancestors[root] then return win, job end
		end
	end
end

local function editor(tab)
	local function usable(win)
		if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_tabpage(win) ~= tab then return false end
		local buf = vim.api.nvim_win_get_buf(win)
		return vim.api.nvim_win_get_config(win).relative == ""
			and (vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "oil")
			and not vim.wo[win].diff and not vim.wo[win].winfixbuf
	end
	local ok, targets = pcall(require, "config.return_target")
	local last = ok and targets.last()
	if last and usable(last.win) then return last.win end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if usable(win) then return win end
	end
end

local function finish(request)
	if active ~= request then return end
	active = nil
	if request.previous_cwd and vim.api.nvim_win_is_valid(request.target) then
		vim.api.nvim_win_call(request.target, function()
			if vim.fn.getcwd() == request.cwd then
				local command = request.scope == 1 and "lcd" or request.scope == 2 and "tcd" or "cd"
				local cwd = request.scope == 0 and vim.fn.getcwd(-1, -1) or request.previous_cwd
				vim.cmd("noautocmd " .. command .. " " .. vim.fn.fnameescape(cwd))
			end
		end)
	end
	if request.previous_cwd and not request.accepted and vim.api.nvim_win_is_valid(request.source)
		and vim.api.nvim_get_current_tabpage() == request.tab then
		vim.api.nvim_set_current_win(request.source)
		if request.mode:sub(1, 1) == "t" then vim.cmd.startinsert() end
	end
end

local function picker_open()
	local window = package.loaded["fzf-lua.win"]
	local instance = window and window.__SELF()
	return instance and instance.fzf_winid and vim.api.nvim_win_is_valid(instance.fzf_winid)
end

local function after_close(request, revision)
	-- Native actions (including scheduled scope switches) run after on_close.
	vim.schedule(function()
		vim.schedule(function()
			if active ~= request or request.revision ~= revision then return end
			if picker_open() then return end
			finish(request)
		end)
	end)
end

function M.options(opts)
	if not active then return opts end
	opts = opts or {}
	if opts._start == false or opts._terminal_picker then return opts end
	local request = active
	opts = vim.deepcopy(opts)
	opts._terminal_picker = true
	if not request.opened and request.key ~= "fF" then opts.cwd = request.cwd end
	-- Hidden pickers bypass fn_selected, so native actions cannot settle this request.
	opts.no_hide = true
	request.opened = true
	request.revision = request.revision + 1
	local revision = request.revision
	opts.winopts = opts.winopts or {}
	opts.winopts.relative = "editor"
	local close, selected = opts.winopts.on_close, opts.fn_selected
	opts.winopts.on_close = function()
		after_close(request, revision)
		if close then close() end
	end
	opts.fn_selected = function(entries, resolved)
		if owner(request.pid) ~= request.source then return end
		local actions = require("fzf-lua.actions")
		local key = actions.normalize_selected(vim.deepcopy(entries), resolved)
		request.accepted = key ~= nil and key ~= "esc" and key ~= "ctrl-c" and key ~= "ctrl-q"
		return (selected or actions.act)(entries, resolved)
	end
	return opts
end

function M.request(args)
	if type(args) ~= "table" or not keys[args.key] then return "unsupported" end
	if active or picker_open() then return "busy" end
	if type(args.cwd) ~= "string" or not vim.startswith(args.cwd, "/") or vim.fn.isdirectory(args.cwd) ~= 1 then return "invalid cwd" end
	args.cwd = vim.uv.fs_realpath(args.cwd)
	local source, job = owner(args.pid)
	if not source then return "unowned" end
	local tab = vim.api.nvim_win_get_tabpage(source)
	if tab ~= vim.api.nvim_get_current_tabpage() then return "inactive tab" end
	local target = editor(tab)
	if not target then return "no editor window" end
	local request = { source = source, tab = tab, target = target, cwd = args.cwd, key = args.key,
		pid = args.pid, mode = vim.api.nvim_get_mode().mode, revision = 0 }
	active = request
	vim.schedule(function()
		local current, current_job = owner(args.pid)
		if current ~= source or current_job ~= job or vim.api.nvim_get_current_tabpage() ~= tab
			or not vim.api.nvim_win_is_valid(target) or picker_open() then finish(request); return end
		local ok, err = xpcall(function()
			local lazy = package.loaded.lazy
			if lazy then lazy.load({ plugins = { "fzf-lua", "diffview.nvim" } }) end
			-- stopinsert here would override fzf's startinsert after the window switch.
			vim.api.nvim_set_current_win(target)
			request.previous_cwd, request.scope = vim.fn.getcwd(), vim.fn.haslocaldir()
			vim.cmd("noautocmd lcd " .. vim.fn.fnameescape(args.cwd))
			local mapping = vim.fn.maparg((vim.g.mapleader or "\\") .. args.key, "n", false, true)
			assert(type(mapping.callback) == "function", "No native picker callback for " .. args.key)
			mapping.callback()
			if not request.opened then request.accepted = true; after_close(request, request.revision) end
		end, debug.traceback)
		if not ok then
			finish(request)
			vim.notify("Terminal picker: " .. err, vim.log.levels.ERROR)
		end
	end)
	return "queued"
end

return M

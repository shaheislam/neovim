local M = {}

local return_target = require("config.return_target")
local plan_save_prompt = [[HUMAN PLAN SAVE
The human saved the root .plan.md in the Neovim instance handed off from this OpenCode session. Please re-read .plan.md from disk and continue from the latest human direction. Keep the living plan aligned with the worktree and edit .plan.md directly when later agent-authored updates are needed.]]
local plan_notifications = {}

local function result(status, reason)
	return { status = status, reason = reason }
end

local function register_server()
	M._registered_project = M._registered_project or vim.fn.getcwd()
	if vim.v.servername == "" then
		pcall(vim.fn.serverstart)
	end
end

local function can_interrupt_editor()
	return vim.api.nvim_get_mode().mode == "n"
end

local function canonical(path)
	if not path or path == "" then
		return nil
	end

	local absolute = vim.fn.fnamemodify(path, ":p")
	local resolved = vim.uv.fs_realpath(absolute) or vim.fn.resolve(absolute)
	if resolved ~= "/" then
		resolved = resolved:gsub("/+$", "")
	end
	return resolved
end

local function disk_signature(path)
	local stat = path and vim.uv.fs_stat(path) or nil
	if not stat or stat.type ~= "file" then
		return nil
	end

	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return nil
	end
	local content = stat.size > 0 and vim.uv.fs_read(fd, stat.size, 0) or ""
	vim.uv.fs_close(fd)
	if content == nil then
		return nil
	end
	return vim.fn.sha256(content)
end

local function set_plan_provenance(buf, provenance)
	if provenance ~= nil then
		vim.b[buf].agent_plan_provenance = vim.deepcopy(provenance)
	end
end

local function track_plan_buffer(buf, path, provenance)
	local signature = disk_signature(path)
	vim.b[buf].agent_plan_path = path
	vim.b[buf].agent_plan_disk_baseline = signature
	vim.b[buf].agent_plan_last_notified = signature
	vim.b[buf].agent_plan_pending_notification = nil
	vim.b[buf].agent_plan_disk_conflict = nil
	plan_notifications[buf] = nil
	set_plan_provenance(buf, provenance)
end

local function refresh_plan_baseline(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local path = vim.b[buf].agent_plan_path
	if not path or canonical(vim.api.nvim_buf_get_name(buf)) ~= path then
		return
	end

	vim.b[buf].agent_plan_disk_baseline = disk_signature(path)
	vim.b[buf].agent_plan_disk_conflict = nil
end

local function plan_route(project_dir, route)
	if not vim.env.REX_SESSION or not vim.env.REX_BLOCK then
		return nil
	end
	local root = vim.env.DOTFILES_HOME or ((vim.env.HOME or "") .. "/dotfiles")
	local ok, completed = pcall(function()
		return vim.system({ "python3", root .. "/scripts/rex/editor.py", project_dir,
			"--verify-route", vim.json.encode(route) }, { text = true }):wait(5000)
	end)
	return ok and completed and completed.code == 0 and route or nil
end

local function route_for_plan(buf, project_dir)
	local provenance = vim.b[buf].agent_plan_provenance
	if type(provenance) ~= "table" then
		return nil
	end
	if provenance.kind == "native" then
		local ok, route = pcall(require("config.opencode_handoff").resolve_plan_route, provenance)
		return ok and route or nil
	end
	if provenance.kind == "rex" then
		return plan_route(project_dir, provenance)
	end
	return nil
end

local dispatch_plan_notification

dispatch_plan_notification = function(buf, signature)
	if not vim.api.nvim_buf_is_valid(buf) then
		plan_notifications[buf] = nil
		return
	end
	local path = vim.b[buf].agent_plan_path
	local project_dir = path and canonical(vim.fn.fnamemodify(path, ":h")) or nil
	local route = project_dir and route_for_plan(buf, project_dir) or nil
	if not route then
		return
	end

	local notification = plan_notifications[buf] or {}
	plan_notifications[buf] = notification
	notification.inflight = signature
	vim.b[buf].agent_plan_pending_notification = signature
	require("config.opencode_http").prompt_async(route.sessionID, plan_save_prompt, { dir = project_dir }, function(ok)
		if not vim.api.nvim_buf_is_valid(buf) then
			plan_notifications[buf] = nil
			return
		end
		local current = plan_notifications[buf]
		if not current or current.inflight ~= signature then
			return
		end
		current.inflight = nil
		vim.b[buf].agent_plan_pending_notification = nil
		if ok then
			vim.b[buf].agent_plan_last_notified = signature
		end
		local queued = current.queued
		current.queued = nil
		if queued and queued ~= vim.b[buf].agent_plan_last_notified then
			dispatch_plan_notification(buf, queued)
		end
	end)
end

local function notify_plan_save(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local path = vim.b[buf].agent_plan_path
	if not path or canonical(vim.api.nvim_buf_get_name(buf)) ~= path then
		return
	end
	local signature = disk_signature(path)
	if not signature or signature == vim.b[buf].agent_plan_last_notified then
		return
	end
	local notification = plan_notifications[buf]
	if notification and notification.inflight then
		notification.queued = signature ~= notification.inflight and signature or nil
		return
	end
	dispatch_plan_notification(buf, signature)
end

local function find_plan_buffer(path)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and canonical(vim.api.nvim_buf_get_name(buf)) == path then
			return buf
		end
	end
end

local focus_buffer = require("config.bufutil").focus_buffer_preserving_terminal

local function git_succeeds(args)
	return vim.system(args, { text = true }):wait().code == 0
end

local function find_repo_view(lib, project_dir, base)
	local fallback
	for _, view in pairs(lib.views or {}) do
		local tab = view.tabpage
		local root = canonical(view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel)
		if tab and vim.api.nvim_tabpage_is_valid(tab) and root == project_dir then
			if view.rev_arg == base then
				return view
			end
			fallback = fallback or view
		end
	end
	return fallback
end

local function watch_project(project_dir)
	local ok, hotreload = pcall(require, "config.hotreload")
	if ok then
		pcall(hotreload.watch_directory, project_dir)
	end
end

function M.open_diff(project_dir, base)
	if not can_interrupt_editor() then
		return result("deferred", "editor_not_normal")
	end
	if vim.g.opencode_auto_diffview == false then
		return result("refused", "diff_disabled")
	end

	project_dir = canonical(project_dir)
	if not project_dir or vim.fn.isdirectory(project_dir) ~= 1 then
		return result("refused", "invalid_project")
	end
	if not git_succeeds({ "git", "-C", project_dir, "rev-parse", "--is-inside-work-tree" }) then
		return result("refused", "not_git_repository")
	end

	base = vim.trim(base or "")
	base = base ~= "" and base or nil
	if base and not git_succeeds({ "git", "-C", project_dir, "cat-file", "-e", base .. "^{commit}" }) then
		return result("refused", "invalid_base")
	end

	return_target.capture({ force = true })
	local ok, lib = pcall(require, "diffview.lib")
	local view = ok and find_repo_view(lib, project_dir, base) or nil
	if view then
		require("config.diffview_region").focus(view)
		watch_project(project_dir)
		if view.rev_arg == base then
			if view.update_files then
				view:update_files()
			end
			return result("opened", "diff_refreshed")
		end

		if base and view.set_revs then
			local retargeted = pcall(view.set_revs, view, base)
			if retargeted and view.rev_arg == base then
				return result("opened", "diff_retargeted")
			end
		end

		if view.close then
			local closed_ok, closed = pcall(view.close, view)
			if not closed_ok or closed == false then
				return result("refused", "diff_retarget_failed")
			end
		else
			local closed_ok = pcall(vim.cmd, "DiffviewClose")
			if not closed_ok then
				return result("refused", "diff_retarget_failed")
			end
		end
	end

	watch_project(project_dir)
	local opened, success = pcall(function()
		local args = { "-C=" .. project_dir }
		if base then
			args[#args + 1] = base
		end
		local new_view = require("diffview.lib").diffview_open(args)
		return new_view and require("config.diffview_region").open(new_view)
	end)
	if not opened or not success then
		return result("refused", "diff_open_failed")
	end
	return result("opened", "diff_opened")
end

function M.open_plan(project_dir, provenance)
	if not can_interrupt_editor() then
		return result("deferred", "editor_not_normal")
	end

	local root = canonical(project_dir)
	if not root or vim.fn.isdirectory(root) ~= 1 then
		return result("refused", "invalid_project")
	end

	local path = canonical(root .. "/.plan.md")
	local stat = path and vim.uv.fs_stat(path) or nil
	if not stat or stat.type ~= "file" or vim.fn.filereadable(path) ~= 1 then
		return result("refused", "missing_plan")
	end

	local buf = find_plan_buffer(path)
	local created = buf == nil
	if created then
		local opened, err = pcall(vim.cmd, "tabnew " .. vim.fn.fnameescape(path))
		if not opened then
			return result("refused", "plan_open_failed:" .. tostring(err))
		end
		buf = vim.api.nvim_get_current_buf()
		track_plan_buffer(buf, path, provenance)
	else
		if not vim.api.nvim_buf_is_loaded(buf) then
			vim.fn.bufload(buf)
		end
		focus_buffer(buf)
		if vim.b[buf].agent_plan_path ~= path or not vim.b[buf].agent_plan_disk_baseline then
			track_plan_buffer(buf, path, provenance)
		else
			set_plan_provenance(buf, provenance)
		end
	end

	if vim.bo[buf].modified then
		local baseline = vim.b[buf].agent_plan_disk_baseline
		local conflicted = vim.b[buf].agent_plan_disk_conflict == true or disk_signature(path) ~= baseline
		if conflicted then
			vim.b[buf].agent_plan_disk_conflict = true
			return result("refused", "modified_disk_conflict")
		end
		return result("opened", "modified_preserved")
	end

	local disk_changed = disk_signature(path) ~= vim.b[buf].agent_plan_disk_baseline
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("silent! checktime")
	end)
	if disk_changed then
		refresh_plan_baseline(buf)
		return result("opened", "plan_reloaded")
	end
	return result("opened", created and "plan_opened" or "plan_focused")
end

function M.open(project_dir, base)
	return M.open_diff(project_dir, base)
end

function M.open_handoff(options)
	local diff = result("deferred", "diff_not_requested")
	if options.open_diff then
		diff = M.open_diff(options.project_dir, options.base)
	end
	local plan = M.open_plan(options.project_dir, options.provenance)
	return { status = plan.status, reason = plan.reason, diff = diff, plan = plan }
end

M._open_handoff = M.open_handoff

function M.open_from_rex(options)
	if canonical(M._registered_project) ~= canonical(options.project_dir) then
		return result("refused", "editor_project_mismatch")
	end
	return M.open_handoff(options)
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	register_server()
	local group = vim.api.nvim_create_augroup("opencode_diffview_idle", { clear = true })
	vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
		group = group,
		callback = register_server,
		desc = "Register Neovim RPC endpoint for agent handoff",
	})
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		group = group,
		callback = function(event)
			refresh_plan_baseline(event.buf)
			if event.event == "BufReadPost" then
				vim.b[event.buf].agent_plan_last_notified = vim.b[event.buf].agent_plan_disk_baseline
			else
				notify_plan_save(event.buf)
			end
		end,
		desc = "Resolve agent plan disk baseline after explicit read or write",
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			plan_notifications[event.buf] = nil
		end,
		desc = "Forget plan notification state when its buffer is wiped",
	})
end

return M

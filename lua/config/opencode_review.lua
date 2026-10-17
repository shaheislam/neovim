local M = {}

local function notify(text, level)
	vim.notify(text, level or vim.log.levels.INFO, { title = "Agent review" })
end

local function serialize_refresh(view)
	local update, running, pending, callbacks = view.update_files, false, nil, {}
	local function drain()
		if running or not pending then
			return
		end
		local opts, listeners = pending, callbacks
		pending, callbacks, running = nil, {}, true
		update(view, opts, function(err)
			running = false
			for _, callback in ipairs(listeners) do
				callback(err)
			end
			vim.schedule(drain)
		end)
	end
	-- The fork's debounce coalesces starts but permits overlapping async renders.
	view.update_files = function(_, opts, callback)
		if type(opts) == "function" then
			opts, callback = nil, opts
		end
		pending = vim.tbl_extend("force", pending or {}, type(opts) == "table" and opts or {})
		if callback then
			callbacks[#callbacks + 1] = callback
		end
		drain()
	end
end

function M.current(root)
	local ok, lib = pcall(require, "diffview.lib")
	local view = ok and lib.get_current_view and lib.get_current_view() or nil
	local review = view and view.opencode_review
	if review and (not root or review.provenance.project == (vim.uv.fs_realpath(root) or root)) then
		return review, view
	end
end

function M.start(base)
	local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
	if result.code ~= 0 then
		notify("Review requires a Git repository", vim.log.levels.WARN)
		return false
	end
	local root = vim.uv.fs_realpath(vim.trim(result.stdout))
	local provenance = require("config.agent_session").capture(root)
	if not provenance then
		notify("Open the worktree's agent and select a session before starting review", vim.log.levels.WARN)
		return false
	end
	local lib_ok, lib = pcall(require, "diffview.lib")
	for _, view in pairs(lib_ok and lib.views or {}) do
		local review = view.opencode_review
		if review and review.provenance.project == root and (not base or base == "") then
			if not vim.deep_equal(review.provenance, provenance) then
				notify(
					"The review session changed; close its Diffview before starting a new review",
					vim.log.levels.WARN
				)
				return false
			end
			vim.api.nvim_set_current_tabpage(view.tabpage)
			return true
		end
	end
	result = vim.system(
		{ "git", "-C", root, "rev-parse", "--verify", "--end-of-options", (base or "HEAD") .. "^{commit}" },
		{ text = true }
	):wait()
	if result.code ~= 0 then
		notify("Invalid review base: " .. (base or "HEAD"), vim.log.levels.WARN)
		return false
	end
	local sha = vim.trim(result.stdout)
	require("diffview")
	local view = require("diffview.lib").diffview_open({ "-C=" .. root, sha })
	if not view or not view.left or view.left.commit ~= sha then
		return false
	end
	view.opencode_review = { base = sha, provenance = provenance }
	serialize_refresh(view)
	-- The fork normally hides untracked files in commit-to-worktree diffs.
	local show_untracked = view.adapter.show_untracked
	view.adapter.show_untracked = function(adapter, opts)
		return show_untracked(adapter, { dv_opt = opts and opts.dv_opt })
	end
	if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
		view:open()
	else
		view:update_files()
	end
	require("config.hotreload").watch_directory(root)
	notify("Reviewing " .. provenance.sessionID .. " from " .. sha:sub(1, 8) .. "; annotations auto-submit")
	return true
end

-- Review comments keep their original route even after their tab has closed.
function M.submit(items, root)
	local review = M.current(root)
	local provenance
	for _, item in ipairs(items) do
		local captured = item.review or review
		if not captured or (provenance and not vim.deep_equal(provenance, captured.provenance)) then
			notify("Comments belong to different reviews; send them individually", vim.log.levels.WARN)
			return false
		end
		provenance = captured.provenance
	end
	local route = require("config.agent_session").resolve(provenance)
	if not route or route.directory ~= (vim.uv.fs_realpath(root) or root) then
		notify("Comment saved, but its review session is stale; nothing sent", vim.log.levels.WARN)
		return false
	end
	local prompt = require("config.annotations").prompt_for_items(items)
	if not prompt then
		return false
	end
	return require("config.agent_session").submit(provenance, prompt, function(state, err)
		require("config.annotations").update_delivery(root, items, state, err)
		if state == "working" or state == "awaiting_permission" then
			return
		end
		if state == "queued" or state == "submitted" or state == "turn_ended" then
			notify("Review " .. state:gsub("_", " ") .. " · " .. route.sessionID)
		else
			notify(
				"Comment saved; delivery failed ("
					.. state
					.. "): "
					.. tostring(err)
					.. ". Inspect the conversation before retrying with <leader>ano",
				vim.log.levels.WARN
			)
		end
	end)
end

function M.refresh()
	local review, view = M.current()
	if not review or view.left.commit ~= review.base then
		return
	end
	require("config.hotreload").watch_directory(review.provenance.project)
	view:update_files(nil, function()
		require("config.annotations").refresh_all()
	end)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("opencode_review", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "NvimMiniExternalFilesChanged",
		callback = M.refresh,
	})
	vim.api.nvim_create_autocmd({ "TabEnter", "FocusGained", "BufWritePost" }, {
		group = group,
		callback = M.refresh,
	})
	local function start(opts)
		M.start(opts.args ~= "" and opts.args or nil)
	end
	vim.api.nvim_create_user_command(
		"AgentReview",
		start,
		{ nargs = "?", desc = "Review the bound agent against a pinned commit" }
	)
	vim.api.nvim_create_user_command("OpencodeReview", start, { nargs = "?", desc = "Alias for AgentReview" })
	vim.keymap.set("n", "<leader>anr", function()
		M.start()
	end, { desc = "Start live agent review" })
end

return M

local M = {}
local reviews = {}

function M.active(root)
	return root and reviews[vim.uv.fs_realpath(root) or root] or nil
end

function M.rebind(source, target)
	local review = M.active(source.project)
	if review and vim.deep_equal(review.provenance, source) then
		review.provenance = vim.deepcopy(target)
	end
end

local function notify(text, level)
	vim.notify(text, level or vim.log.levels.INFO, { title = "Agent review" })
end

function M.attach(view)
	if view.opencode_review then
		return view.opencode_review
	end
	local directory = view.adapter and view.adapter.ctx.toplevel
	local root = directory and (vim.uv.fs_realpath(directory) or directory)
	local provenance = root and require("config.agent_session").capture(root)
	if not provenance then
		view.annotation_review_error = "No unique live agent session for this repository; annotations are saved locally"
		return
	end
	view.opencode_review = {
		base = require("config.review_context").revision_label(view.left),
		provenance = vim.deepcopy(provenance),
		automatic = true,
	}
	if view.update_files then
		require("config.diffview_region").serialize_refresh(view)
	end
	return view.opencode_review
end

function M.current(root)
	local ok, lib = pcall(require, "diffview.lib")
	local view = ok and lib.tabpage_to_view and lib.tabpage_to_view(vim.api.nvim_get_current_tabpage()) or nil
	if ok and not view then
		for _, candidate in pairs(lib.views or {}) do
			local zoom = candidate.region and candidate.region.zoom
			if zoom and zoom.host == vim.api.nvim_get_current_tabpage() then
				view = candidate
				break
			end
		end
	end
	local review = view and view.opencode_review
	if review and (not root or review.provenance.project == (vim.uv.fs_realpath(root) or root)) then
		return review, view
	end
	local directory = view and view.adapter and view.adapter.ctx.toplevel
	if
		not review
		and directory
		and (not root or (vim.uv.fs_realpath(directory) or directory) == (vim.uv.fs_realpath(root) or root))
	then
		return nil, view
	end
end

function M.start(base, directory, opts)
	local result = vim.system(
		{ "git", "-C", directory or vim.fn.getcwd(), "rev-parse", "--show-toplevel" },
		{ text = true }
	)
		:wait()
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
	base = base ~= "" and base or nil
	local context = not base and M.active(root) or nil
	if context and not vim.deep_equal(context.provenance, provenance) then
		notify(
			"The review session changed; use :AgentReview HEAD to explicitly start a new review",
			vim.log.levels.WARN
		)
		return false
	end
	for _, view in pairs(lib_ok and lib.views or {}) do
		local review = view.opencode_review
		if review and review == context then
			require("config.diffview_region").focus(view)
			view:update_files()
			return true
		end
	end
	result = vim.system({
		"git",
		"-C",
		root,
		"rev-parse",
		"--verify",
		"--end-of-options",
		(context and context.base or base or "HEAD") .. "^{commit}",
	}, { text = true }):wait()
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
	context = context or { base = sha, provenance = provenance }
	reviews[root] = context
	view.opencode_review = context
	if opts and opts.background then
		-- Initial file rendering completes asynchronously after the handoff restores terminal focus.
		view._should_focus_diff = function()
			return false
		end
	end
	require("config.review_progress").attach(view, context)
	require("config.diffview_region").serialize_refresh(view)
	-- The fork normally hides untracked files in commit-to-worktree diffs.
	local show_untracked = view.adapter.show_untracked
	view.adapter.show_untracked = function(adapter, opts)
		return show_untracked(adapter, { dv_opt = opts and opts.dv_opt })
	end
	if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
		if not require("config.diffview_region").open(view) then
			return false
		end
	else
		view:update_files()
	end
	require("config.hotreload").watch_directory(root)
	notify("Reviewing " .. provenance.sessionID .. " from " .. sha:sub(1, 8) .. "; annotations auto-submit")
	return true
end

-- Review comments keep their original route even after their tab has closed.
function M.submit(items, root)
	local review = M.active(root)
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
	end, { return_to_prompt = true })
end

function M.refresh()
	local review, view = M.current()
	if not review or not view.update_files or (not review.automatic and view.left.commit ~= review.base) then
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

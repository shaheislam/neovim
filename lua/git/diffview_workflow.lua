local M = {}

local function current_view()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return nil
	end
	return lib.get_current_view()
end

local function set_diffview_revs(api, revs)
	revs = vim.trim(revs or "")
	if revs == "" then
		vim.notify("Usage: DiffviewSetRevs <rev-range>", vim.log.levels.WARN)
		return
	end

	if not current_view() then
		vim.notify("Open a Diffview first", vim.log.levels.WARN)
		return
	end

	local ok, err = pcall(api.set_revs, revs)
	if not ok then
		vim.notify("Diffview rev retarget failed: " .. tostring(err), vim.log.levels.WARN)
		return
	end

	vim.notify("Diffview revs: " .. revs, vim.log.levels.INFO)
end

local function get_reviewed_paths(selections)
	if not current_view() then
		vim.notify("Open a Diffview first", vim.log.levels.WARN)
		return nil
	end

	return selections.get_paths()
end

local function list_reviewed_files(selections)
	local paths = get_reviewed_paths(selections)
	if not paths then
		return
	end
	if #paths == 0 then
		vim.notify("No reviewed files marked in this Diffview", vim.log.levels.INFO)
		return
	end

	local items = vim.tbl_map(function(path)
		return { filename = path, text = "reviewed" }
	end, paths)
	vim.fn.setqflist({}, " ", {
		title = "Diffview reviewed files",
		items = items,
	})
	vim.cmd("copen")
end

local function clear_reviewed_files(selections)
	local paths = get_reviewed_paths(selections)
	if not paths then
		return
	end
	if #paths == 0 then
		vim.notify("No reviewed files to clear", vim.log.levels.INFO)
		return
	end

	selections.clear()
	vim.notify("Cleared reviewed marks for " .. #paths .. " file(s)", vim.log.levels.INFO)
end

local function diff_files(files)
	if #files ~= 2 then
		vim.notify("Usage: DiffFiles <file1> <file2>", vim.log.levels.ERROR)
		return
	end

	vim.cmd("DiffviewDiffFiles " .. vim.fn.fnameescape(files[1]) .. " " .. vim.fn.fnameescape(files[2]))
end

local function diff_dirs(dirs)
	if #dirs ~= 2 then
		vim.notify("Usage: DiffDirs <dir1> <dir2>", vim.log.levels.ERROR)
		return
	end

	vim.cmd("DiffviewDiffDirs " .. vim.fn.fnameescape(dirs[1]) .. " " .. vim.fn.fnameescape(dirs[2]))
end

function M.scope()
	local view = current_view()
	local directory = view and view.adapter.ctx.toplevel or vim.fn.getcwd()
	local result = vim.system({ "git", "-C", directory, "rev-parse", "--show-toplevel" }, { text = true }):wait()
	if result.code ~= 0 then
		vim.notify("Review scopes require a Git repository", vim.log.levels.WARN)
		return
	end
	local root = vim.trim(result.stdout)
	local context = require("config.review_context")
	local comparison = view and context.comparison(view)
	local owner = view and view.opencode_review and view.opencode_review.provenance
		or require("config.agent_session").capture(root)
	local header = root
		.. " · "
		.. (comparison and (context.revision_label(comparison.a) .. " → " .. context.revision_label(comparison.b)) or "choose comparison")
		.. " · "
		.. (owner and owner.sessionID or "no captured agent")
	local scopes = {
		"Uncommitted · index → working tree",
		"Staged · HEAD → index",
		"Last commit · HEAD^ → HEAD",
		"Branch · merge-base → HEAD",
		"Agent review · pinned commit → working tree",
	}
	local extra = "-C" .. vim.fn.fnameescape(root)
	vim.ui.select(scopes, { prompt = header }, function(choice)
		local diff = require("git.diffview")
		if choice == scopes[1] then
			diff.open(extra)
		elseif choice == scopes[2] then
			diff.open(extra .. " --staged")
		elseif choice == scopes[3] then
			diff.open_commit("HEAD", extra)
		elseif choice == scopes[4] then
			vim.ui.input({ prompt = "Branch comparison base: ", default = "@{upstream}" }, function(base)
				if not base or vim.trim(base) == "" then
					return
				end
				local resolved = vim.system(
					{ "git", "-C", root, "rev-parse", "--verify", "--end-of-options", vim.trim(base) .. "^{commit}" },
					{ text = true }
				):wait()
				if resolved.code == 0 then
					resolved = vim.system(
						{ "git", "-C", root, "merge-base", vim.trim(resolved.stdout), "HEAD" },
						{ text = true }
					)
						:wait()
				end
				if resolved.code ~= 0 then
					vim.notify("No valid merge base for " .. base, vim.log.levels.WARN)
					return
				end
				diff.open_range(vim.trim(resolved.stdout), "HEAD", extra)
			end)
		elseif choice == scopes[5] then
			require("config.opencode_review").start(nil, root)
		end
	end)
end

function M.setup(opts)
	local api = assert(opts and opts.api, "git.diffview_workflow.setup requires api")
	local selections = api.selections
	vim.api.nvim_create_user_command("ReviewScope", M.scope, { desc = "Choose a review comparison without checkout" })

	vim.api.nvim_create_user_command("DiffviewSetRevs", function(command_opts)
		set_diffview_revs(api, command_opts.args)
	end, {
		nargs = 1,
		desc = "Retarget the current Diffview to a new revision range",
	})

	vim.api.nvim_create_user_command("DiffviewReviewedList", function()
		list_reviewed_files(selections)
	end, {
		desc = "List reviewed Diffview files in quickfix",
	})

	vim.api.nvim_create_user_command("DiffviewReviewedClear", function()
		clear_reviewed_files(selections)
	end, {
		desc = "Clear reviewed Diffview file marks",
	})

	vim.api.nvim_create_user_command("DiffFiles", function(command_opts)
		diff_files(command_opts.fargs)
	end, { nargs = "+", complete = "file", desc = "Diff two arbitrary files" })

	vim.api.nvim_create_user_command("DiffDirs", function(command_opts)
		diff_dirs(command_opts.fargs)
	end, { nargs = "+", complete = "dir", desc = "Diff two arbitrary directories" })
end

return M

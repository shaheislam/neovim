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

	vim.cmd("tabnew " .. vim.fn.fnameescape(files[1]))
	vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(files[2]))
end

function M.setup(opts)
	local api = assert(opts and opts.api, "git.diffview_workflow.setup requires api")
	local selections = api.selections

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
end

return M

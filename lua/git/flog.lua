local M = {}

local graph_args = "-auto-update"

local function current_file()
	local file = vim.fn.expand("%")
	if file == "" then
		vim.notify("No current file for Flog path history", vim.log.levels.WARN)
		return nil
	end

	return vim.fn.fnameescape(file)
end

local function flog_format(format)
	local ok, value = pcall(vim.fn["flog#Format"], format)
	if not ok then
		vim.notify("Flog metadata unavailable", vim.log.levels.WARN)
		return ""
	end
	return vim.trim(value or "")
end

function M.open_graph()
	vim.cmd("Flog " .. graph_args)
end

function M.open_graph_split()
	vim.cmd("Flogsplit " .. graph_args)
end

function M.open_current_file_graph()
	local file = current_file()
	if not file then
		return
	end

	vim.cmd("Flog " .. graph_args .. " -path=" .. file)
end

function M.open_current_file_graph_split()
	local file = current_file()
	if not file then
		return
	end

	vim.cmd("Flogsplit " .. graph_args .. " -path=" .. file)
end

function M.open_selected_lines_graph()
	local file = current_file()
	if not file then
		return
	end

	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	vim.cmd(string.format("%d,%dFlog %s -path=%s", start_line, end_line, graph_args, file))
end

function M.open_commit_in_diffview()
	require("git.diffview").open_commit(flog_format("%h"))
end

function M.open_commit_path_in_diffview()
	require("git.diffview").open_commit(flog_format("%h"), flog_format("%P"))
end

function M.open_selection_in_diffview()
	local newer = flog_format("%(h'>)")
	local older = flog_format("%(h'<)")
	require("git.diffview").open_range(older, newer)
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("FlogDiffviewBridge", { clear = true }),
		pattern = "floggraph",
		callback = function(args)
			local opts = { buffer = args.buf, silent = true }
			vim.wo.cursorline = true
			vim.keymap.set("n", "dv", M.open_commit_in_diffview, vim.tbl_extend("force", opts, { desc = "Diffview commit" }))
			vim.keymap.set("n", "dp", M.open_commit_path_in_diffview, vim.tbl_extend("force", opts, { desc = "Diffview commit paths" }))
			vim.keymap.set("v", "dV", M.open_selection_in_diffview, vim.tbl_extend("force", opts, { desc = "Diffview selected range" }))
		end,
	})
end

return M

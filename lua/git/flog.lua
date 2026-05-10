local M = {}

local graph_args = "-auto-update"

local branch_palette = {
	"#9ece6a",
	"#e0af68",
	"#ff9e64",
	"#f7768e",
	"#bb9af7",
	"#7aa2f7",
	"#2ac3de",
	"#7dcfff",
}

local function set_hl(group, opts)
	vim.api.nvim_set_hl(0, group, opts)
end

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

local function flog_hash_at_line(line)
	local ok, commit = pcall(vim.fn["flog#floggraph#commit#GetAtLine"], line)
	if not ok or type(commit) ~= "table" then
		return ""
	end

	return vim.trim(commit.hash or "")
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
	local start_line = vim.fn.line("v")
	local end_line = vim.fn.line(".")
	local top = math.min(start_line, end_line)
	local bottom = math.max(start_line, end_line)

	local newer = flog_hash_at_line(top)
	local older = flog_hash_at_line(bottom)
	require("git.diffview").open_range(older, newer)
end

function M.apply_style()
	set_hl("FlogNormal", { bg = "NONE" })
	set_hl("FlogCursorLine", { bg = "#2a3148" })
	set_hl("FlogEndOfBuffer", { fg = "#1f2335", bg = "NONE" })

	set_hl("flogHash", { fg = "#bb9af7" })
	set_hl("flogAuthor", { fg = "#9ece6a" })
	set_hl("flogDate", { fg = "#ff9e64" })
	set_hl("flogRef", { fg = "#7aa2f7" })
	set_hl("flogRefTag", { fg = "#e0af68", bold = true })
	set_hl("flogRefRemote", { fg = "#2ac3de" })
	set_hl("flogRefHead", { fg = "#f7768e", bold = true })
	set_hl("flogRefHeadArrow", { fg = "#565f89" })
	set_hl("flogRefHeadBranch", { fg = "#c0caf5", bold = true })
	set_hl("flogCollapsedCommit", { fg = "#565f89", italic = true })
	set_hl("flogCommit", { fg = "#c0caf5", bold = true })

	for index, color in ipairs(branch_palette) do
		set_hl("flogBranch" .. index, { fg = color, bold = true })
		set_hl("flogGraphBranch" .. index, { fg = color, bold = true })
	end
	set_hl("flogBranch0", { link = "flogBranch1" })
end

local function configure_graph_window()
	vim.wo.cursorline = true
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	vim.wo.foldcolumn = "0"
	vim.wo.colorcolumn = ""
	vim.wo.list = false
	vim.wo.wrap = false
	vim.wo.winhighlight = "Normal:FlogNormal,CursorLine:FlogCursorLine,EndOfBuffer:FlogEndOfBuffer"
end

function M.setup()
	M.apply_style()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("FlogStyling", { clear = true }),
		callback = M.apply_style,
		desc = "Apply Flog graph styling",
	})

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("FlogDiffviewBridge", { clear = true }),
		pattern = "floggraph",
		callback = function(args)
			local opts = { buffer = args.buf, silent = true }
			M.apply_style()
			configure_graph_window()
			vim.keymap.set("n", "<CR>", M.open_commit_in_diffview, vim.tbl_extend("force", opts, { desc = "Diffview commit" }))
			vim.keymap.set("v", "<CR>", M.open_selection_in_diffview, vim.tbl_extend("force", opts, { desc = "Diffview selected range" }))
		end,
	})
end

return M

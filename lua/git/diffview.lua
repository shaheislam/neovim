local M = {}

local function trim(value)
	return vim.trim(value or "")
end

local function append_extra(args, extra_args)
	if type(extra_args) ~= "string" then
		return args
	end

	extra_args = trim(extra_args)
	if extra_args == "" then
		return args
	end
	return args .. " " .. extra_args
end

function M.open(args)
	args = trim(args)
	if args == "" then
		vim.notify("Diffview requires a revision or range", vim.log.levels.WARN)
		return
	end

	vim.cmd("DiffviewOpen " .. args)
end

function M.open_commit(hash, extra_args)
	hash = trim(hash)
	if hash == "" then
		vim.notify("No commit under cursor", vim.log.levels.WARN)
		return
	end

	M.open(append_extra(vim.fn.fnameescape(hash) .. "^!", extra_args))
end

function M.open_range(base, head, extra_args)
	base = trim(base)
	head = trim(head)
	if base == "" or head == "" then
		vim.notify("Select a commit range first", vim.log.levels.WARN)
		return
	end

	M.open(append_extra(vim.fn.fnameescape(base) .. ".." .. vim.fn.fnameescape(head), extra_args))
end

function M.open_file(revision, file)
	revision = trim(revision)
	file = trim(file)
	if file == "" then
		vim.notify("No file to compare", vim.log.levels.WARN)
		return
	end

	M.open(append_extra(revision == "" and "" or vim.fn.fnameescape(revision), "-- " .. vim.fn.fnameescape(file)))
end

return M

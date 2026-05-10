local M = {}

local function trim(value)
	return vim.trim(value or "")
end

local function append_extra(args, extra_args)
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

	M.open(append_extra(hash .. "^!", extra_args))
end

function M.open_range(base, head, extra_args)
	base = trim(base)
	head = trim(head)
	if base == "" or head == "" then
		vim.notify("Select a commit range first", vim.log.levels.WARN)
		return
	end

	M.open(append_extra(base .. ".." .. head, extra_args))
end

return M

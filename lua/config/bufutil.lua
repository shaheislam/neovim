local M = {}

---@param bufnr? integer
---@return boolean
function M.is_uri_buffer(bufnr)
	bufnr = bufnr or 0
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name:match("^%w+://") ~= nil
end

---@param bufnr? integer
---@return boolean
function M.is_diffview_buffer(bufnr)
	bufnr = bufnr or 0
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "Commit Info" or name:match("^diffview://") then
		return true
	end
	local ft = vim.bo[bufnr].filetype
	return ft == "DiffviewFiles" or ft == "DiffviewFileHistory"
end

---@param bufnr? integer
---@param opts? {allow_modified?: boolean, allow_unnamed?: boolean}
---@return boolean
function M.should_skip_normal_file_buffer(bufnr, opts)
	bufnr = bufnr or 0
	opts = opts or {}
	if not opts.allow_modified and vim.bo[bufnr].modified then
		return true
	end
	if vim.bo[bufnr].buftype ~= "" then
		return true
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return not opts.allow_unnamed
	end
	return M.is_uri_buffer(bufnr)
end

return M

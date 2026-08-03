local M = {}

---Start a pane-local Visual selection when the focused buffer is a terminal.
---@return integer handled 1 when Visual mode was entered, otherwise 0
function M.start_visual()
	if vim.bo.buftype ~= "terminal" then
		return 0
	end

	local keys = vim.api.nvim_replace_termcodes([[<C-\><C-n>v]], true, false, true)
	vim.api.nvim_feedkeys(keys, "nx", false)
	return 1
end

return M

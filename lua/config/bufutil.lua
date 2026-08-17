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

local function is_terminal_win(win)
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.bo[buf].buftype == "terminal"
end

-- Non-floating, unlocked, unmodified code windows in the current tab, left-to-right.
-- Terminal windows (e.g. the opencode AI pane) are never candidates.
local function code_windows_left_to_right()
	local candidates = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if
			vim.api.nvim_win_get_config(win).relative == ""
			and not vim.wo[win].winfixbuf
			and not vim.bo[buf].modified
			and not is_terminal_win(win)
		then
			table.insert(candidates, win)
		end
	end
	table.sort(candidates, function(a, b)
		local pa = vim.api.nvim_win_get_position(a)
		local pb = vim.api.nvim_win_get_position(b)
		if pa[2] ~= pb[2] then
			return pa[2] < pb[2]
		end
		return pa[1] < pb[1]
	end)
	return candidates
end

--- Focus `buf` without ever displaying it in a terminal window (the
--- opencode AI pane). Reuses a window already showing it if one exists,
--- otherwise prefers the left-most safe code window in the current tab,
--- and only opens a new tab if none is available.
---@param buf integer
function M.focus_buffer_preserving_terminal(buf)
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			if vim.api.nvim_win_get_buf(win) == buf then
				vim.api.nvim_set_current_tabpage(tab)
				vim.api.nvim_set_current_win(win)
				return
			end
		end
	end

	local win = code_windows_left_to_right()[1]
	if win then
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_set_current_win(win)
		return
	end

	vim.cmd("tabnew")
	vim.api.nvim_win_set_buf(0, buf)
end

--- Open `path` in a safe code window, or a new tab when every available
--- window is a terminal, locked, or modified. Closing that tab naturally
--- returns to the preserved terminal tab.
---@param path string
---@param line? integer
---@return integer
function M.open_file_preserving_terminal(path, line)
	local buf = vim.fn.bufnr(path)
	if buf < 0 then
		buf = vim.fn.bufadd(path)
	end
	if not vim.api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
	end

	M.focus_buffer_preserving_terminal(buf)
	if line and line > 0 then
		local total = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_win_set_cursor(0, { math.min(line, total), 0 })
		vim.cmd("normal! zz")
	end
	vim.cmd("checktime")
	return 1
end

return M

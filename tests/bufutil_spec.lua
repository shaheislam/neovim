package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function reset_layout()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		vim.wo[win].winfixbuf = false
	end
	vim.cmd("silent! tabonly")
	vim.cmd("silent! only")

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_win_set_buf(win, buf)
	return win, buf
end

local function split_right(buf)
	vim.cmd("rightbelow vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.wo[win].winfixbuf = false
	vim.api.nvim_win_set_buf(win, buf)
	return win
end

local bufutil = dofile("lua/config/bufutil.lua")

do
	local code_win = reset_layout()
	local terminal_buf = vim.api.nvim_create_buf(false, true)
	local terminal_win = split_right(terminal_buf)
	vim.api.nvim_open_term(terminal_buf, {})
	local target = vim.api.nvim_create_buf(true, false)

	bufutil.focus_buffer_preserving_terminal(target)

	eq(vim.api.nvim_win_get_buf(code_win), target, "an unseen file replaces the left code buffer")
	eq(vim.api.nvim_win_get_buf(terminal_win), terminal_buf, "an unseen file never replaces the terminal buffer")
end

do
	local locked_win, locked_buf = reset_layout()
	local code_buf = vim.api.nvim_create_buf(true, false)
	local code_win = split_right(code_buf)
	local terminal_buf = vim.api.nvim_create_buf(false, true)
	local terminal_win = split_right(terminal_buf)
	vim.api.nvim_open_term(terminal_buf, {})
	vim.wo[locked_win].winfixbuf = true
	local target = vim.api.nvim_create_buf(true, false)

	local ok, err = pcall(bufutil.focus_buffer_preserving_terminal, target)

	assert(ok, "a locked left window is skipped: " .. tostring(err))
	eq(vim.api.nvim_win_get_buf(locked_win), locked_buf, "the locked left buffer is preserved")
	eq(vim.api.nvim_win_get_buf(code_win), target, "the next eligible code window receives the file")
	eq(vim.api.nvim_win_get_buf(terminal_win), terminal_buf, "the terminal remains unchanged beside a locked window")
end

do
	local modified_win, modified_buf = reset_layout()
	local code_buf = vim.api.nvim_create_buf(true, false)
	local code_win = split_right(code_buf)
	local terminal_buf = vim.api.nvim_create_buf(false, true)
	local terminal_win = split_right(terminal_buf)
	vim.api.nvim_open_term(terminal_buf, {})
	vim.bo[modified_buf].modified = true
	local target = vim.api.nvim_create_buf(true, false)

	bufutil.focus_buffer_preserving_terminal(target)

	eq(vim.api.nvim_win_get_buf(modified_win), modified_buf, "a modified left buffer remains visible")
	eq(vim.api.nvim_win_get_buf(code_win), target, "the next unmodified code window receives the file")
	eq(vim.api.nvim_win_get_buf(terminal_win), terminal_buf, "the terminal remains unchanged beside modified work")
end

do
	local code_win = reset_layout()
	local terminal_buf = vim.api.nvim_create_buf(false, true)
	local terminal_win = split_right(terminal_buf)
	vim.api.nvim_open_term(terminal_buf, {})
	local path = vim.fn.tempname()
	vim.fn.writefile({ "one", "two", "three" }, path)

	bufutil.open_file_preserving_terminal(path, 2)

	eq(vim.api.nvim_get_current_win(), code_win, "an opened file focuses the safe code window")
	eq(vim.api.nvim_buf_get_name(0), vim.uv.fs_realpath(path), "the safe code window receives the requested file")
	eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the requested line is selected")
	eq(vim.api.nvim_win_get_buf(terminal_win), terminal_buf, "opening a file preserves the terminal buffer")
	vim.fn.delete(path)
end

do
	local _, terminal_buf = reset_layout()
	vim.api.nvim_open_term(terminal_buf, {})
	vim.bo[terminal_buf].bufhidden = "wipe"
	local terminal_tab = vim.api.nvim_get_current_tabpage()
	local path = vim.fn.tempname()
	vim.fn.writefile({ "return target" }, path)

	bufutil.open_file_preserving_terminal(path)

	eq(#vim.api.nvim_list_tabpages(), 2, "a terminal-only layout opens the file in a temporary tab")
	eq(vim.api.nvim_buf_is_valid(terminal_buf), true, "the hidden terminal remains valid")
	eq(vim.api.nvim_buf_get_name(0), vim.uv.fs_realpath(path), "the temporary tab displays the requested file")
	vim.cmd("quit")
	eq(vim.api.nvim_get_current_tabpage(), terminal_tab, "closing the temporary tab returns to the terminal tab")
	eq(vim.api.nvim_get_current_buf(), terminal_buf, "closing the temporary tab restores the terminal buffer")
	vim.fn.delete(path)
end

print("PASS buffer focus preserves terminal, locked windows, and modified work")

local M = {}

local state = {
	last = nil,
	setup = false,
	suspended = false,
}

local excluded_filetypes = {
	["DiffviewFiles"] = true,
	["DiffviewFileHistory"] = true,
	["Trouble"] = true,
	["checkhealth"] = true,
	["fugitive"] = true,
	["fzf"] = true,
	["gitcommit"] = false,
	["help"] = true,
	["lspinfo"] = true,
	["man"] = true,
	["notify-history"] = true,
	["opencode-transcript"] = true,
	["qf"] = true,
}

local excluded_name_patterns = {
	"^diffview://",
	"^fugitive://",
	"^gitsigns://",
	"^noice://",
	"^octo://",
	"^opencode://",
	"^term://",
	"^%[.+%]",
}

local function valid_window(win)
	return win and win > 0 and vim.api.nvim_win_is_valid(win)
end

local function valid_buffer(buf)
	return buf and buf > 0 and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function is_unnamed_empty(buf)
	return vim.api.nvim_buf_get_name(buf) == ""
		and not vim.bo[buf].modified
		and vim.api.nvim_buf_line_count(buf) <= 1
		and (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") == ""
end

local function is_oil_buffer(buf)
	return vim.bo[buf].filetype == "oil" or vim.api.nvim_buf_get_name(buf):match("^oil://") ~= nil
end

function M.is_real_buffer(buf)
	if not valid_buffer(buf) then
		return false
	end
	if is_oil_buffer(buf) then
		return true
	end

	local buftype = vim.bo[buf].buftype
	if buftype ~= "" then
		return false
	end

	local ft = vim.bo[buf].filetype
	if excluded_filetypes[ft] then
		return false
	end

	local name = vim.api.nvim_buf_get_name(buf)
	for _, pattern in ipairs(excluded_name_patterns) do
		if name:match(pattern) then
			return false
		end
	end

	return not is_unnamed_empty(buf)
end

local function make_target(win, buf)
	buf = buf or (valid_window(win) and vim.api.nvim_win_get_buf(win)) or vim.api.nvim_get_current_buf()
	if valid_window(win) and vim.wo[win].diff then
		return nil
	end
	if not M.is_real_buffer(buf) then
		return nil
	end

	return {
		buf = buf,
		win = valid_window(win) and win or nil,
		tab = vim.api.nvim_get_current_tabpage(),
	}
end

function M.capture(opts)
	opts = opts or {}
	if state.suspended and not opts.force then
		return nil
	end
	local target = make_target(vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf())
	if target then
		state.last = target
	end
	return target
end

function M.suspend()
	state.suspended = true
end

function M.resume()
	state.suspended = false
end

function M.last()
	if state.last and M.is_real_buffer(state.last.buf) then
		return state.last
	end
	return nil
end

local function first_real_buffer(exclude)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= exclude and M.is_real_buffer(buf) then
			return { buf = buf }
		end
	end
	return nil
end

local function pick_target(target, exclude)
	if target and target.buf ~= exclude and M.is_real_buffer(target.buf) then
		return target
	end

	local last = M.last()
	if last and last.buf ~= exclude then
		return last
	end

	local alternate = vim.fn.bufnr("#")
	if alternate ~= exclude and M.is_real_buffer(alternate) then
		return { buf = alternate }
	end

	return first_real_buffer(exclude)
end

function M.restore(target, opts)
	opts = opts or {}
	target = pick_target(target, opts.exclude_buf)
	if not target then
		if opts.fallback ~= false then
			vim.cmd.enew()
		end
		return false
	end

	if valid_window(target.win) then
		vim.api.nvim_set_current_win(target.win)
		if vim.api.nvim_win_get_buf(target.win) ~= target.buf then
			vim.api.nvim_win_set_buf(target.win, target.buf)
		end
	else
		local cur_win = vim.api.nvim_get_current_win()
		if not vim.wo[cur_win].winfixbuf then
			vim.api.nvim_set_current_buf(target.buf)
		else
			local found = false
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if not vim.wo[win].winfixbuf then
					vim.api.nvim_set_current_win(win)
					vim.api.nvim_set_current_buf(target.buf)
					found = true
					break
				end
			end
			if not found then
				vim.cmd.enew()
			end
		end
	end

	state.last = target
	return true
end

function M.delete_transient_buffer(buf, target)
	M.restore(target, { exclude_buf = buf })
	if valid_buffer(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

function M.setup()
	if state.setup then
		return
	end
	state.setup = true

	local group = vim.api.nvim_create_augroup("ReturnTargetTracker", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = group,
		callback = function()
			vim.schedule(function()
				M.capture()
			end)
		end,
	})
end

return M

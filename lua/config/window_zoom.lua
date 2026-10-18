-- Track mini.misc's zoom so workspace actions can restore its source first.
local M = {}
local api = vim.api
local source, floating

function M.origin(win)
	if floating and api.nvim_win_is_valid(floating) and (not win or win == floating) then
		return source
	end
end

function M.restore()
	if not M.origin() then
		source, floating = nil, nil
		return false
	end
	local origin, focused = source, api.nvim_get_current_win() == floating
	require("mini.misc").zoom()
	source, floating = nil, nil
	if focused and api.nvim_win_is_valid(origin) then
		api.nvim_set_current_win(origin)
	end
	return true
end

function M.toggle()
	if M.restore() then
		return true
	end
	local ok, misc = pcall(require, "mini.misc")
	if not ok or not misc.zoom then
		return false
	end
	local origin = api.nvim_get_current_win()
	if misc.zoom(nil, { border = "none" }) then
		source, floating = origin, api.nvim_get_current_win()
	end
	return true
end

return M

local M = {}

local function selected_frame(entry)
	local ok_utils, utils = pcall(require, "fzf-lua.utils")
	if ok_utils then entry = utils.strip_ansi_coloring(entry or "") end
	local index = tonumber((entry or ""):match("^%s*(%d+)%."))
	if not index then return nil end

	local ok_dap, dap = pcall(require, "dap")
	local session = ok_dap and dap.session() or nil
	local thread = session and session.threads and session.threads[session.stopped_thread_id]
	return thread and thread.frames and thread.frames[index] or nil
end

function M.frame_location(entry)
	local frame = selected_frame(entry)
	local path = frame and frame.source and frame.source.path
	if not path or path == "" then return nil end
	local is_uri = path:match("^[%a%-]+://")
	if path:match("^file://") then
		local ok, filename = pcall(vim.uri_to_fname, path)
		if not ok then return nil end
		path = filename
		is_uri = false
	elseif not is_uri and not path:match("^/") and not path:match("^%a:[/\\]") then
		path = vim.fs.joinpath(vim.fn.getcwd(), path)
	end
	if not is_uri then path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")) end
	if (frame.line or 0) > 0 then
		path = path .. ":" .. frame.line
		if (frame.column or 0) > 0 then path = path .. ":" .. frame.column end
	end
	return path
end

function M.yank(selected)
	local locations = {}
	for _, entry in ipairs(selected or {}) do
		local location = M.frame_location(entry)
		if location then table.insert(locations, location) end
	end
	if #locations == 0 then return end
	vim.fn.setreg("+", table.concat(locations, "\n"))
	vim.notify(("Yanked %d DAP frame%s"):format(#locations, #locations == 1 and "" or "s"))
end

function M.launch()
	local _, command, opts = require("fzf-lua").dap_frames({ _start = false })
	if not command or not opts then return end
	opts._start = nil
	opts.actions = opts.actions or {}
	opts.actions["ctrl-y"] = M.yank
	return require("fzf-lua.core").fzf_wrap(command, opts, true)
end

return M

-- Ordinary project shell terminal shared by the <leader>ft mapping and the
-- coordinated worktree-startup layout (opencode.lua). Keeping a single cached
-- terminal here (instead of a plugin-file-local closure) lets both callers
-- reuse and reason about the same instance.
local M = {}

local state = { term = nil }

local function resolve_dir(explicit_dir)
	if explicit_dir and explicit_dir ~= "" then
		return explicit_dir
	end

	local cwd = vim.fn.getcwd()
	if vim.bo.filetype == "oil" then
		local ok, oil = pcall(require, "oil")
		if ok and oil then
			local oil_dir = oil.get_current_dir()
			if oil_dir then
				cwd = oil_dir
			end
		end
	end
	return cwd
end

-- Reuse the cached terminal so repeated calls act on the same instance
-- instead of spawning a new shell each time; only recreate it if the target
-- directory changed.
local function ensure_terminal(dir)
	if not state.term or state.term.dir ~= dir then
		local Terminal = require("toggleterm.terminal").Terminal
		state.term = Terminal:new({
			dir = dir,
			direction = "horizontal",
			hidden = false,
		})
	end
	return state.term
end

--- Toggle the ordinary project terminal for the given (or resolved) directory.
--- Preserves the existing <leader>ft close/open behavior.
function M.toggle(explicit_dir)
	local term = ensure_terminal(resolve_dir(explicit_dir))
	term:toggle()
	return term
end

--- Idempotently ensure the ordinary project terminal is open: focuses an
--- already-open terminal instead of reopening it (which would otherwise
--- reset ToggleTerm's remembered origin window and disturb sibling splits).
function M.open(explicit_dir)
	local term = ensure_terminal(resolve_dir(explicit_dir))
	if term:is_open() then
		term:focus()
	else
		term:open()
	end
	return term
end

-- Test-only: clears cached state between test sections.
function M.__reset()
	state.term = nil
end

return M

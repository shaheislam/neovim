-- Registers this Neovim's OCV terminal in the same
-- $XDG_STATE_HOME/opencode/attaches/*.pid schema that
-- scripts/opencode/tmux-open.sh writes for a standalone tmux-hosted OCV pane.
--
-- opencode-resolve-pane.fish only ever discovers OCV clients through those
-- attach records. Neovim launches OCV directly (bypassing tmux-open.sh, since
-- this terminal already owns its split), so without this registration a live
-- Neovim-hosted OCV is invisible to that resolver and a repeated `gwtt`/
-- `C-s b` invocation for the same worktree would build a second, duplicate
-- Neovim+OCV layout instead of reusing the existing one.
local M = {}

local current = nil
local resolve_pid = function(job_id)
	return vim.fn.jobpid(job_id)
end

local function attach_dir()
	local home = vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")
	return home .. "/opencode/attaches"
end

-- Mirrors scripts/opencode/tmux-open.sh's pane_key(): strip the leading `%`
-- and replace anything outside [A-Za-z0-9_.-] with `_`.
local function pane_key(pane)
	local stripped = pane:gsub("^%%", "")
	return "pane-" .. (stripped:gsub("[^%w_.%-]", "_"))
end

--- Best-effort: records this terminal as the OCV attach owner for the
--- current tmux pane. Returns false (never raises) when registration isn't
--- possible - outside tmux, or before the terminal job has actually spawned.
function M.register(term, dir, generation)
	local pane = vim.env.TMUX_PANE
	if not pane or pane == "" then
		return false
	end
	if not term or not term.job_id then
		return false
	end

	local pid = resolve_pid(term.job_id)
	if not pid or pid <= 0 then
		return false
	end

	local dir_path = attach_dir()
	vim.fn.mkdir(dir_path, "p")
	local file = dir_path .. "/" .. pane_key(pane) .. ".pid"
	local tmp = string.format("%s.tmp.%d.%d", file, vim.fn.getpid(), math.floor(vim.uv.hrtime() % 1e9))

	local lines = {
		"pid=" .. tostring(pid),
		"pane=" .. pane,
		"cwd=" .. dir,
		"started=" .. tostring(os.time()),
		"command=" .. (term.cmd or ""),
	}

	if vim.fn.writefile(lines, tmp) ~= 0 then
		return false
	end
	if not os.rename(tmp, file) then
		pcall(vim.fn.delete, tmp)
		return false
	end

	current = { file = file, generation = generation }
	return true
end

--- Removes the attach file this Neovim instance registered, if any.
function M.unregister(generation)
	if not current or current.generation ~= generation then
		return false
	end
	pcall(vim.fn.delete, current.file)
	current = nil
	return true
end

-- Test-only: overrides internal seams that would otherwise require a real
-- running job (jobpid()) to exercise deterministically.
function M.__set_test_hooks(hooks)
	if hooks.resolve_pid then
		resolve_pid = hooks.resolve_pid
	end
end

-- Test-only: clears cached state and hook overrides between test sections.
function M.__reset()
	current = nil
	resolve_pid = function(job_id)
		return vim.fn.jobpid(job_id)
	end
end

return M

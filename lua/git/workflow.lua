-- Shared Git workflow helpers for plugin specs

local function jump_to_first_diff()
	vim.cmd("diffupdate")

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) and vim.wo[win].diff then
			vim.api.nvim_win_call(win, function()
				vim.api.nvim_win_set_cursor(0, { 1, 0 })

				local is_diff_at_top = vim.fn.diff_hlID(1, 1) ~= 0 or vim.fn.diff_filler(1) ~= 0
				if not is_diff_at_top then
					pcall(vim.cmd, "normal! ]c")
				end

				vim.cmd("normal! zz")
			end)
		end
	end
end

-- Clipboard diff utilities
local function compare_clipboard()
	-- Get clipboard content
	local clipboard = vim.fn.getreg("+")
	if clipboard == "" then
		vim.notify("Clipboard is empty", vim.log.levels.WARN)
		return
	end

	-- Store current filetype and buffer for syntax highlighting
	local ft = vim.bo.filetype
	local original_buf = vim.api.nvim_get_current_buf()

	-- Create vertical split with clipboard content
	vim.cmd("vnew")
	local scratch_buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, vim.split(clipboard, "\n"))
	vim.bo[scratch_buf].buftype = "nofile"
	vim.bo[scratch_buf].bufhidden = "wipe"
	vim.bo[scratch_buf].filetype = ft
	vim.cmd("diffthis")

	-- Function to close the diff from the scratch buffer without leaking mappings into the source buffer.
	local function close_diff()
		vim.cmd("diffoff!")
		if vim.api.nvim_buf_is_valid(scratch_buf) then
			vim.cmd("bwipeout " .. scratch_buf)
		end
	end

	vim.keymap.set("n", "q", close_diff, { buffer = scratch_buf, desc = "Close diff" })

	-- Go back to original window and enable diff
	vim.cmd("wincmd p")
	vim.cmd("diffthis")
	vim.defer_fn(jump_to_first_diff, 50)
end

local function compare_clipboard_selection()
	-- Exit visual mode to set the '< and '> marks
	vim.cmd('normal! "vy') -- Also yanks selection to register v as backup

	-- Get clipboard content
	local clipboard = vim.fn.getreg("+")
	if clipboard == "" then
		vim.notify("Clipboard is empty", vim.log.levels.WARN)
		return
	end

	-- Get visual selection using the now-set marks
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)

	if #lines == 0 then
		vim.notify("No selection captured", vim.log.levels.WARN)
		return
	end

	-- Store current filetype
	local ft = vim.bo.filetype

	-- Create new tab with two splits
	vim.cmd("tabnew")
	local buf1 = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf1, 0, -1, false, lines)
	vim.bo[buf1].buftype = "nofile"
	vim.bo[buf1].bufhidden = "wipe"
	vim.bo[buf1].filetype = ft
	vim.cmd("diffthis")

	vim.cmd("vnew")
	local buf2 = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf2, 0, -1, false, vim.split(clipboard, "\n"))
	vim.bo[buf2].buftype = "nofile"
	vim.bo[buf2].bufhidden = "wipe"
	vim.bo[buf2].filetype = ft
	vim.cmd("diffthis")

	-- Add q to close the diff tab from either scratch buffer.
	vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = buf1, desc = "Close diff" })
	vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = buf2, desc = "Close diff" })
	vim.defer_fn(jump_to_first_diff, 50)
end

-- ============================================================================
-- Commit Cycling - Navigate through commit history in Diffview
-- ============================================================================

-- State for tracking current position in commit history
local commit_cycle_state = {
	current_sha = nil, -- Current commit being viewed
	file_path = nil, -- File path for file-scoped navigation
	from_sha = nil, -- Parent commit SHA (FROM)
	to_sha = nil, -- Current commit SHA (TO)
	sha_colors = {}, -- Map: SHA -> color index (for persistent colors)
	next_color_idx = 1, -- Next color to assign from palette
	is_cycling = false, -- Flag to preserve color state during cycling
}

-- Buffer for commit info display
local commit_info_bufnr = nil

-- Cross-worktree merge detection state
local cross_worktree_state = {
	active = false,
	original_cwd = nil,
	main_work_dir = nil,
	main_git_dir = nil,
}

-- Find the repo/worktree root by walking up from dir to find .git.
-- Returns the directory containing .git (the working tree root), or nil.
-- Uses fs_stat only (no subprocess).
local function find_repo_root(dir)
	local d = dir
	while d and d ~= "" and d ~= "/" do
		if vim.uv.fs_stat(d .. "/.git") then
			return d
		end
		local parent = vim.fn.fnamemodify(d, ":h")
		if parent == d then
			break
		end
		d = parent
	end
	return nil
end

-- Check if `path` is equal to or under `root` (path-separator-aware).
-- Avoids false positives like "/dotfiles" matching "/dotfiles-mergeview".
local function path_is_under(path, root)
	if not root or not path then
		return false
	end
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- Get the working directory of the current terminal buffer's shell process.
-- On macOS: queries lsof for the process cwd. On Linux: reads /proc/PID/cwd.
-- Returns nil if not in a terminal buffer or if detection fails.
local function get_terminal_cwd()
	local job_id = vim.b.terminal_job_id
	if not job_id then
		return nil
	end
	local ok, pid = pcall(vim.fn.jobpid, job_id)
	if not ok or not pid or pid <= 0 then
		return nil
	end
	local cwd = nil
	if vim.fn.has("mac") == 1 then
		local out = vim.fn.system("lsof -nP -a -p " .. pid .. " -d cwd -Fn 2>/dev/null")
		-- lsof output: "p<pid>\nn<cwd>\n" — extract the n-prefixed line
		cwd = out:match("\nn(.-)\n") or out:match("\nn(.+)$")
	else
		local out = vim.fn.system("readlink /proc/" .. pid .. "/cwd 2>/dev/null")
		if vim.v.shell_error == 0 then
			cwd = out:gsub("\n$", "")
		end
	end
	if cwd and cwd ~= "" then
		return cwd
	end
	return nil
end

-- Resolve the tmux window ID containing Neovim's pane ($TMUX_PANE).
-- All pane queries are scoped to this window to avoid cross-window/client
-- bleed when multiple clients or windows are attached to the same session.
-- PERF: Cached for session lifetime — window ID never changes for a Neovim instance.
local _cached_window_id = nil
local function get_neovim_window_id()
	if _cached_window_id then
		return _cached_window_id
	end
	if not vim.env.TMUX or not vim.env.TMUX_PANE then
		return nil
	end
	local out = vim.fn.system(
		"tmux display-message -p -t " .. vim.fn.shellescape(vim.env.TMUX_PANE) .. " '#{window_id}' 2>/dev/null"
	)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local wid = out:gsub("\n$", "")
	if wid == "" then
		return nil
	end
	_cached_window_id = wid
	return wid
end

-- Get the cwd of the last-selected pane in Neovim's window.
-- Scoped via window ID derived from $TMUX_PANE (not global {last}).
-- Best for FocusGained: when Neovim just gained focus, {last} within its
-- window = the shell pane the user was just in.
local function get_tmux_last_pane_cwd()
	local wid = get_neovim_window_id()
	if not wid then
		return nil
	end
	-- Target: <window_id>.{last} — the previously selected pane in this window.
	local target = wid .. ".{last}"
	local out = vim.fn.system(
		"tmux display-message -p -t " .. vim.fn.shellescape(target) .. " '#{pane_current_path}' 2>/dev/null"
	)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local path = out:gsub("\n$", "")
	if path == "" then
		return nil
	end
	return path
end

-- Async version of get_tmux_last_pane_cwd: non-blocking tmux IPC.
-- Calls callback(cwd_or_nil) when complete.
local function get_tmux_last_pane_cwd_async(callback)
	local wid = get_neovim_window_id()
	if not wid then
		callback(nil)
		return
	end
	local target = wid .. ".{last}"
	vim.system(
		{ "tmux", "display-message", "-p", "-t", target, "#{pane_current_path}" },
		{ text = true },
		function(result)
			vim.schedule(function()
				if result.code ~= 0 or not result.stdout then
					callback(nil)
					return
				end
				local path = result.stdout:gsub("\n$", "")
				callback(path ~= "" and path or nil)
			end)
		end
	)
end

-- Get the cwd of the currently active (focused) pane in Neovim's window,
-- skipping if it's Neovim's own pane. Scoped to Neovim's window via -t.
-- Best for timer polling: when the user is in a shell pane, the active pane
-- in Neovim's window is the shell (correct). {last} would return Neovim's
-- own pane (wrong), causing the timer to override Fish hook results.
local function get_tmux_active_pane_cwd()
	local wid = get_neovim_window_id()
	if not wid then
		return nil
	end
	local out = vim.fn.system(
		"tmux list-panes -t "
			.. vim.fn.shellescape(wid)
			.. " -F '#{pane_active} #{pane_id} #{pane_current_path}' 2>/dev/null"
	)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	for line in out:gmatch("[^\n]+") do
		local active, pane_id, path = line:match("^(%d) (%%%d+) (.+)$")
		if active == "1" then
			-- Skip if the active pane is Neovim's own pane
			if pane_id == vim.env.TMUX_PANE then
				return nil
			end
			if path == "" then
				return nil
			end
			return path
		end
	end
	return nil
end

-- Async version of get_tmux_active_pane_cwd: non-blocking tmux IPC.
-- PERF: This is the hot path — called every timer tick. Using vim.system()
-- prevents blocking Neovim's UI thread, which is critical when multiple
-- Neovim instances all poll tmux's single-threaded server simultaneously.
-- Calls callback(cwd_or_nil) when complete.
local function get_tmux_active_pane_cwd_async(callback)
	local wid = get_neovim_window_id()
	if not wid then
		callback(nil)
		return
	end
	vim.system(
		{ "tmux", "list-panes", "-t", wid, "-F", "#{pane_active} #{pane_id} #{pane_current_path}" },
		{ text = true },
		function(result)
			vim.schedule(function()
				if result.code ~= 0 or not result.stdout then
					callback(nil)
					return
				end
				for line in result.stdout:gmatch("[^\n]+") do
					local active, pane_id, path = line:match("^(%d) (%%%d+) (.+)$")
					if active == "1" then
						if pane_id == vim.env.TMUX_PANE or path == "" then
							callback(nil)
							return
						end
						callback(path)
						return
					end
				end
				callback(nil)
			end)
		end
	)
end

-- User toggle: set vim.g.diffview_auto_switch = false to disable
-- automatic conflict detection and view switching.
-- Default: true (enabled). Can be toggled at runtime via:
--   :DiffviewAutoSwitchToggle
--   :let g:diffview_auto_switch = v:false
--   :lua vim.g.diffview_auto_switch = false
if vim.g.diffview_auto_switch == nil then
	vim.g.diffview_auto_switch = true
end

vim.api.nvim_create_user_command("DiffviewAutoSwitchToggle", function()
	vim.g.diffview_auto_switch = not vim.g.diffview_auto_switch
	vim.notify("Diffview auto-switch: " .. (vim.g.diffview_auto_switch and "ON" or "OFF"), vim.log.levels.INFO)
end, { desc = "Toggle Diffview automatic conflict detection and view switching" })

-- Repo-following toggle: set vim.g.diffview_follow_repo = false to disable
-- automatic Diffview retargeting when switching to a buffer in a different repo.
-- Default: true (enabled). Toggle at runtime via :DiffviewFollowRepoToggle
if vim.g.diffview_follow_repo == nil then
	vim.g.diffview_follow_repo = true
end

vim.api.nvim_create_user_command("DiffviewFollowRepoToggle", function()
	vim.g.diffview_follow_repo = not vim.g.diffview_follow_repo
	vim.notify("Diffview follow-repo: " .. (vim.g.diffview_follow_repo and "ON" or "OFF"), vim.log.levels.INFO)
end, { desc = "Toggle Diffview automatic repo following on buffer switch" })

-- Git conflict state indicators (files and directories).
-- Interactive rebase creates rebase-merge/ (not just REBASE_HEAD).
-- Cherry-pick/revert sequences create sequencer/.
local CONFLICT_STATE_FILES = {
	"MERGE_HEAD",
	"REBASE_HEAD",
	"CHERRY_PICK_HEAD",
	"REVERT_HEAD",
	"rebase-merge",
	"rebase-apply",
	"sequencer",
}

-- Check if any git conflict/operation state exists in the given git dir.
-- Uses fs_stat only (no subprocess). Returns the indicator name, or nil.
local function check_conflict_state(git_dir)
	for _, fname in ipairs(CONFLICT_STATE_FILES) do
		if vim.uv.fs_stat(git_dir .. fname) then
			return fname
		end
	end
	return nil
end

-- Color palette for persistent commit colors (Rose Pine theme)
local commit_colors = {
	"#ebbcba", -- Rose Pine "rose" (pink)
	"#f6c177", -- Rose Pine "gold" (yellow/amber)
	"#9ccfd8", -- Rose Pine "foam" (cyan/blue)
	"#31748f", -- Rose Pine "pine" (teal)
	"#c4a7e7", -- Rose Pine "iris" (purple)
	"#eb6f92", -- Rose Pine "love" (red)
}

-- Get or assign a persistent color for a commit SHA
local function get_commit_color(sha)
	if not sha then
		return commit_colors[1]
	end

	-- Check if already assigned
	if commit_cycle_state.sha_colors[sha] then
		return commit_colors[commit_cycle_state.sha_colors[sha]]
	end

	-- Assign next color from palette
	local idx = commit_cycle_state.next_color_idx
	commit_cycle_state.sha_colors[sha] = idx
	commit_cycle_state.next_color_idx = (idx % #commit_colors) + 1

	return commit_colors[idx]
end

-- Create or get highlight group for a commit SHA
local function get_commit_hl_group(sha)
	local color = get_commit_color(sha)
	local hl_name = "CommitMsg_" .. sha:sub(1, 7)
	vim.api.nvim_set_hl(0, hl_name, { fg = color, italic = true })
	return hl_name
end

-- Commit info buffer highlight groups (Rose Pine theme)
local function setup_commit_info_highlights()
	vim.api.nvim_set_hl(0, "CommitInfoFrom", { fg = "#eb6f92", bold = true }) -- Rose Pine "love" (red)
	vim.api.nvim_set_hl(0, "CommitInfoTo", { fg = "#31748f", bold = true }) -- Rose Pine "pine" (blue)
	vim.api.nvim_set_hl(0, "CommitInfoSha", { fg = "#9ccfd8" }) -- Rose Pine "foam" (cyan)
	vim.api.nvim_set_hl(0, "CommitInfoDate", { fg = "#c4a7e7" }) -- Rose Pine "iris" (purple)
	vim.api.nvim_set_hl(0, "CommitInfoCheckpoint", { fg = "#7aa2f7", bold = true }) -- Tokyo Night blue
end

-- Set up highlights on load and colorscheme change
setup_commit_info_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "*",
	callback = setup_commit_info_highlights,
})

-- Look up checkpoint metadata for a commit SHA
local function get_checkpoint_info(sha)
	if not sha or #sha < 8 then
		return nil
	end
	-- Check if checkpoint branch exists
	local check = vim.fn.system("MISE_QUIET=1 git show-ref --quiet refs/heads/checkpoints/v1 2>/dev/null; echo $?")
	if vim.trim(check) ~= "0" then
		return nil
	end
	local shard = sha:sub(1, 2) .. "/" .. sha:sub(3, 8)
	local meta = vim.fn.system("MISE_QUIET=1 git show checkpoints/v1:" .. shard .. "/metadata.json 2>/dev/null")
	if meta == "" or meta:match("^fatal") then
		return nil
	end
	local ok, data = pcall(vim.fn.json_decode, meta)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return {
		summary = data.summary or "",
	}
end

-- Checkout to FROM or TO commit
local function checkout_commit(which)
	local sha = which == "from" and commit_cycle_state.from_sha or commit_cycle_state.to_sha
	if not sha then
		vim.notify("No " .. which:upper() .. " commit to checkout", vim.log.levels.WARN)
		return
	end
	local result = vim.fn.system("MISE_QUIET=1 git checkout " .. sha .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("Checked out to " .. sha:sub(1, 7), vim.log.levels.INFO)
	else
		vim.notify("Checkout failed: " .. result, vim.log.levels.ERROR)
	end
end

local function get_remote_base_url()
	local remote = vim.fn.system("MISE_QUIET=1 git remote get-url origin 2>/dev/null"):gsub("%s+$", "")
	if vim.v.shell_error ~= 0 or remote == "" then
		return nil
	end

	remote = remote:gsub("%.git$", "")
	local host, path = remote:match("^git@([^:]+):(.+)$")
	if host and path then
		return "https://" .. host .. "/" .. path
	end

	local https = remote:match("^(https?://.+)$")
	return https
end

local function open_commit_in_browser(sha)
	if not sha or sha == "" then
		vim.notify("No commit under cursor", vim.log.levels.WARN)
		return
	end

	local base_url = get_remote_base_url()
	if not base_url then
		vim.notify("No origin remote URL found", vim.log.levels.WARN)
		return
	end

	local url = base_url .. "/commit/" .. sha
	if vim.ui.open then
		vim.ui.open(url)
	else
		vim.fn.jobstart({ "open", url }, { detach = true })
	end
end

local function copy_commit_hash(sha)
	if not sha or sha == "" then
		vim.notify("No commit under cursor", vim.log.levels.WARN)
		return
	end

	vim.fn.setreg('"', sha)
	vim.fn.setreg("+", sha)
	vim.notify("Copied commit " .. sha:sub(1, 12), vim.log.levels.INFO)
end

-- Show commit info in a split buffer below Diffview
local function show_commit_info_buffer(from_sha, from_msg, from_date, to_sha, to_msg, to_date)
	-- Create buffer if it doesn't exist or was deleted
	if not commit_info_bufnr or not vim.api.nvim_buf_is_valid(commit_info_bufnr) then
		commit_info_bufnr = vim.api.nvim_create_buf(false, true) -- nofile, scratch
		vim.bo[commit_info_bufnr].buftype = "nofile"
		vim.bo[commit_info_bufnr].bufhidden = "hide"
		vim.bo[commit_info_bufnr].swapfile = false
		pcall(vim.api.nvim_buf_set_name, commit_info_bufnr, "Commit Info")
		-- Add keymap: Enter on FROM/TO checks out that commit, Enter on CKPT opens full checkpoint
		vim.keymap.set("n", "<CR>", function()
			local line = vim.fn.line(".")
			if line <= 2 then
				checkout_commit(line == 1 and "from" or "to")
			else
				-- CKPT line: open full checkpoint details
				local sha = commit_cycle_state.to_sha
				if not sha then
					vim.notify("No commit SHA available", vim.log.levels.WARN)
					return
				end
				vim.cmd("botright new")
				vim.fn.termopen("checkpoints show " .. sha, {
					on_exit = function(_, code)
						if code ~= 0 then
							vim.schedule(function()
								vim.notify("No checkpoint for " .. sha:sub(1, 7), vim.log.levels.INFO)
							end)
						end
					end,
				})
				vim.bo.bufhidden = "wipe"
				vim.cmd("startinsert") -- Enter terminal mode so user can scroll
			end
		end, { buffer = commit_info_bufnr, desc = "Checkout commit / Show checkpoint" })
		-- Add keymap to close Diffview with q
		vim.keymap.set("n", "q", "<cmd>DiffviewClose<cr>", {
			buffer = commit_info_bufnr,
			desc = "Close Diffview",
		})
	end

	-- Format content with better layout
	local from_sha_short = from_sha:sub(1, 7)
	local to_sha_short = to_sha:sub(1, 7)
	local lines = {
		"  FROM  " .. from_sha_short .. "  " .. from_date .. "  " .. from_msg,
		"  TO    " .. to_sha_short .. "  " .. to_date .. "  " .. to_msg,
	}
	-- Add checkpoint line (always show — indicator when no data)
	local ckpt = get_checkpoint_info(to_sha)
	if ckpt then
		table.insert(lines, "  CKPT  " .. ckpt.summary)
	else
		table.insert(lines, "  CKPT  —")
	end
	vim.api.nvim_buf_set_lines(commit_info_bufnr, 0, -1, false, lines)

	-- Apply highlights using extmarks
	local ns = vim.api.nvim_create_namespace("commit_info_hl")
	vim.api.nvim_buf_clear_namespace(commit_info_bufnr, ns, 0, -1)

	-- Line 0: FROM - "  FROM  abc1234  2025-12-01 10:30:15 +0000  commit message"
	local from_date_start = 8 + #from_sha_short + 2
	local from_date_end = from_date_start + #from_date
	local from_msg_start = from_date_end + 2
	-- Get dynamic highlight groups for commit messages (persistent colors per SHA)
	local from_msg_hl = get_commit_hl_group(from_sha)
	local to_msg_hl = get_commit_hl_group(to_sha)

	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 0, 2, { end_col = 6, hl_group = "CommitInfoFrom" })
	vim.api.nvim_buf_set_extmark(
		commit_info_bufnr,
		ns,
		0,
		8,
		{ end_col = 8 + #from_sha_short, hl_group = "CommitInfoSha" }
	)
	vim.api.nvim_buf_set_extmark(
		commit_info_bufnr,
		ns,
		0,
		from_date_start,
		{ end_col = from_date_end, hl_group = "CommitInfoDate" }
	)
	vim.api.nvim_buf_set_extmark(
		commit_info_bufnr,
		ns,
		0,
		from_msg_start,
		{ end_col = #lines[1], hl_group = from_msg_hl }
	)

	-- Line 1: TO - "  TO    abc1234  2025-12-01 10:30:15 +0000  commit message"
	local to_date_start = 8 + #to_sha_short + 2
	local to_date_end = to_date_start + #to_date
	local to_msg_start = to_date_end + 2
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 1, 2, { end_col = 4, hl_group = "CommitInfoTo" })
	vim.api.nvim_buf_set_extmark(
		commit_info_bufnr,
		ns,
		1,
		8,
		{ end_col = 8 + #to_sha_short, hl_group = "CommitInfoSha" }
	)
	vim.api.nvim_buf_set_extmark(
		commit_info_bufnr,
		ns,
		1,
		to_date_start,
		{ end_col = to_date_end, hl_group = "CommitInfoDate" }
	)
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 1, to_msg_start, { end_col = #lines[2], hl_group = to_msg_hl })

	-- Line 2: CKPT line (always present)
	if ckpt then
		vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 2, 2, { end_col = 6, hl_group = "CommitInfoCheckpoint" })
		vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 2, 8, { end_col = #lines[3], hl_group = "Comment" })
	else
		vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 2, 2, { end_col = 6, hl_group = "CommitInfoCheckpoint" })
		vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 2, 8, { end_col = #lines[3], hl_group = "NonText" })
	end

	-- Find or create window for the buffer
	local info_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == commit_info_bufnr then
			info_win = win
			break
		end
	end

	-- Calculate visual height accounting for line wrap
	local function calc_visual_height(buf_lines, win_width)
		local height = 0
		for _, line in ipairs(buf_lines) do
			-- Each line takes ceil(display_width / win_width) visual rows, minimum 1
			local display_width = vim.fn.strdisplaywidth(line)
			height = height + math.max(1, math.ceil(display_width / win_width))
		end
		return height
	end

	if info_win then
		-- Window exists — resize to match wrapped content
		local win_width = vim.api.nvim_win_get_width(info_win)
		vim.api.nvim_win_set_height(info_win, calc_visual_height(lines, win_width))
	else
		-- Create horizontal split at bottom
		vim.cmd("botright split")
		vim.api.nvim_win_set_buf(0, commit_info_bufnr)
		vim.wo[0].number = false
		vim.wo[0].relativenumber = false
		vim.wo[0].signcolumn = "no"
		vim.wo[0].cursorline = false
		vim.wo[0].winfixheight = true
		vim.wo[0].wrap = true
		vim.wo[0].linebreak = true
		vim.wo[0].winhighlight = "Normal:NormalFloat" -- Use float background for subtle distinction
		-- Size after options are set so width is accurate
		local win_width = vim.api.nvim_win_get_width(0)
		vim.api.nvim_win_set_height(0, calc_visual_height(lines, win_width))
		-- Return to previous window (Diffview)
		vim.cmd("wincmd p")
	end
end

-- Close the commit info window if open
local function close_commit_info_window()
	if commit_info_bufnr and vim.api.nvim_buf_is_valid(commit_info_bufnr) then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == commit_info_bufnr then
				vim.api.nvim_win_close(win, true)
				break
			end
		end
	end
end

-- Check if in a git repository
local function is_git_repo()
	local result = vim.fn.system("MISE_QUIET=1 git rev-parse --is-inside-work-tree 2>/dev/null")
	return result:match("true") ~= nil
end

-- Get the git dir path (works for both regular repos and worktrees).
-- Handles .git file indirection: parses "gitdir: <path>" for linked worktrees,
-- resolves relative paths against cwd, then canonicalizes with vim.fn.resolve().
-- Returns absolute path with trailing slash, or nil.
local function get_git_dir(cwd)
	cwd = cwd or vim.fn.getcwd()
	local dot_git = cwd .. "/.git"
	local stat = vim.uv.fs_stat(dot_git)
	if not stat then
		return nil
	end

	if stat.type == "directory" then
		return dot_git .. "/"
	end

	-- Worktree: .git is a file with "gitdir: <path>"
	local f = io.open(dot_git, "r")
	if not f then
		return nil
	end
	local line = f:read("*l")
	f:close()

	local gitdir = line and line:match("^gitdir:%s*(.+)$")
	if not gitdir then
		return nil
	end

	-- Resolve relative paths
	if not gitdir:match("^/") then
		gitdir = cwd .. "/" .. gitdir
	end

	return vim.fn.resolve(gitdir) .. "/"
end

-- Resolve the main repo's git dir and working dir from a worktree.
-- Returns { main_git_dir = ".../.git/", main_work_dir = ".../" } or nil.
local function get_main_repo_info(cwd)
	cwd = cwd or vim.fn.getcwd()
	local git_dir = get_git_dir(cwd)
	if not git_dir then
		return nil
	end

	-- Only worktrees have a commondir file
	local commondir_path = git_dir .. "commondir"
	local f = io.open(commondir_path, "r")
	if not f then
		return nil
	end
	local commondir = f:read("*l")
	f:close()

	if not commondir or commondir == "" then
		return nil
	end

	-- commondir is relative to the worktree's git dir (e.g., "../..")
	local main_git_dir
	if commondir:match("^/") then
		main_git_dir = commondir
	else
		main_git_dir = git_dir .. commondir
	end
	main_git_dir = vim.fn.resolve(main_git_dir) .. "/"

	-- Main working dir is the parent of .git/
	local main_work_dir = main_git_dir:gsub("%.git/$", "")

	vim.notify("get_main_repo_info: git_dir=" .. main_git_dir .. " work_dir=" .. main_work_dir, vim.log.levels.DEBUG)
	return {
		main_git_dir = main_git_dir,
		main_work_dir = main_work_dir,
	}
end

-- Get the currently highlighted file path from Diffview's file panel
local function get_diffview_current_file()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return nil
	end

	local view = lib.get_current_view()
	if not view then
		return nil
	end

	local file = view:infer_cur_file()
	if file and file.path then
		return file.path
	end
	return nil
end

-- Get list of commits (file-scoped or repo-scoped)
local function get_commit_list(file_path)
	local cmd
	if file_path then
		cmd = string.format("MISE_QUIET=1 git log --format=%%H --follow -- %s", vim.fn.shellescape(file_path))
	else
		cmd = "MISE_QUIET=1 git log --format=%H"
	end
	local output = vim.fn.system(cmd)
	local commits = {}
	for sha in output:gmatch("%x+") do
		if #sha == 40 then -- Full SHA length
			table.insert(commits, sha)
		end
	end
	return commits
end

-- Get adjacent commit in history
local function get_adjacent_commit(current_sha, direction, file_path)
	local commits = get_commit_list(file_path)
	if #commits == 0 then
		return nil
	end

	-- If no current commit, start from HEAD
	if not current_sha then
		return direction == "prev" and commits[1] or nil
	end

	-- Find current position and get adjacent
	for i, sha in ipairs(commits) do
		-- Match by prefix (short or full SHA)
		if sha:sub(1, #current_sha) == current_sha or current_sha:sub(1, #sha) == sha then
			if direction == "next" then
				return commits[i - 1] -- Newer commit (earlier in list)
			else
				return commits[i + 1] -- Older commit (later in list)
			end
		end
	end
	return nil
end

-- Show commit info buffer for a single commit (resolves parent, formats FROM/TO/CKPT)
local function show_single_commit_info(sha)
	if not sha or sha == "" then
		vim.notify("No commit under cursor", vim.log.levels.WARN)
		return
	end

	local parent_sha = vim.fn.system("MISE_QUIET=1 git rev-parse " .. sha .. "^ 2>/dev/null"):gsub("%s+", "")
	local parent_msg =
		vim.fn.system("MISE_QUIET=1 git log -1 --format=%s " .. parent_sha .. " 2>/dev/null"):gsub("\n", "")
	local parent_date =
		vim.fn.system("MISE_QUIET=1 git log -1 --format=%ci " .. parent_sha .. " 2>/dev/null"):gsub("\n", "")
	local current_msg = vim.fn.system("MISE_QUIET=1 git log -1 --format=%s " .. sha):gsub("\n", "")
	local current_date = vim.fn.system("MISE_QUIET=1 git log -1 --format=%ci " .. sha):gsub("\n", "")

	-- Store SHAs for checkout functionality
	commit_cycle_state.to_sha = sha

	-- Assign colors in order: TO commit first, then FROM
	get_commit_color(sha)

	if parent_sha == "" or parent_sha:match("^fatal") then
		commit_cycle_state.from_sha = nil
		show_commit_info_buffer("(none)", "(root commit)", "", sha, current_msg, current_date)
	else
		commit_cycle_state.from_sha = parent_sha
		get_commit_color(parent_sha)
		show_commit_info_buffer(parent_sha, parent_msg, parent_date, sha, current_msg, current_date)
	end
end

-- Open Diffview for a single commit (comparing to its parent)
local function open_commit_diff(sha, file_path)
	-- Update state
	commit_cycle_state.current_sha = sha
	-- Only update file_path if we're doing file-scoped navigation (not nil)
	if file_path then
		commit_cycle_state.file_path = file_path
	end

	local rev = sha .. "^!"
	local retargeted = false
	local ok_lib, lib = pcall(require, "diffview.lib")
	local ok_api, api = pcall(require, "diffview.api")
	if ok_lib and ok_api and lib.get_current_view() then
		retargeted = pcall(api.set_revs, rev)
		if retargeted then
			vim.defer_fn(function()
				local ok_actions, actions = pcall(require, "diffview.actions")
				local view = lib.get_current_view()
				if ok_actions and view then
					actions.jump_to_first_change(view)
				end
			end, 100)
		end
	end

	if not retargeted then
		-- Set flag to preserve color state during cycling
		commit_cycle_state.is_cycling = true
		-- Close existing Diffview if open
		pcall(vim.cmd, "DiffviewClose")
		commit_cycle_state.is_cycling = false

		-- Open new Diffview (sha^! means compare sha to its parent)
		vim.cmd("DiffviewOpen " .. rev)
	end

	-- Show FROM/TO/CKPT info buffer
	show_single_commit_info(sha)
end

-- Main cycle function
local function cycle_commit(direction, file_scoped)
	if not is_git_repo() then
		vim.notify("Not in a git repository", vim.log.levels.WARN)
		return
	end

	-- Get file path if file-scoped, handling Diffview buffers
	local file_path = nil
	if file_scoped then
		local current_file = vim.fn.expand("%:p")
		-- If in Diffview, get the highlighted file from file panel
		if current_file == "" or current_file:match("^diffview://") or vim.bo.filetype == "DiffviewFiles" then
			file_path = get_diffview_current_file()
			-- Fall back to stored path if no file highlighted
			if not file_path then
				file_path = commit_cycle_state.file_path
			end
		else
			file_path = current_file
		end
	end

	local current = commit_cycle_state.current_sha
	local next_sha = get_adjacent_commit(current, direction, file_path)

	if not next_sha then
		local msg = direction == "next" and "Already at latest commit" or "Already at oldest commit"
		vim.notify(msg, vim.log.levels.INFO)
		return
	end

	open_commit_diff(next_sha, file_path)
end

local M = {
	commit_cycle_state = commit_cycle_state,
	cross_worktree_state = cross_worktree_state,
	jump_to_first_diff = jump_to_first_diff,
	show_single_commit_info = show_single_commit_info,
	close_commit_info_window = close_commit_info_window,
	find_repo_root = find_repo_root,
	path_is_under = path_is_under,
	get_terminal_cwd = get_terminal_cwd,
	get_tmux_last_pane_cwd = get_tmux_last_pane_cwd,
	get_tmux_last_pane_cwd_async = get_tmux_last_pane_cwd_async,
	get_tmux_active_pane_cwd = get_tmux_active_pane_cwd,
	get_tmux_active_pane_cwd_async = get_tmux_active_pane_cwd_async,
	check_conflict_state = check_conflict_state,
	get_git_dir = get_git_dir,
	get_main_repo_info = get_main_repo_info,
	get_diffview_current_file = get_diffview_current_file,
	open_commit_in_browser = open_commit_in_browser,
	copy_commit_hash = copy_commit_hash,
}

local did_setup = false

function M.setup()
	if did_setup then
		return
	end
	did_setup = true

	vim.keymap.set("n", "<leader>gK", compare_clipboard, { desc = "Compare clipboard vs buffer" })
	vim.keymap.set("v", "<leader>gK", compare_clipboard_selection, { desc = "Compare clipboard vs selection" })

	vim.keymap.set("n", "]r", function()
		cycle_commit("next", true)
	end, { desc = "Next commit (file)" })
	vim.keymap.set("n", "[r", function()
		cycle_commit("prev", true)
	end, { desc = "Prev commit (file)" })
	vim.keymap.set("n", "]R", function()
		cycle_commit("next", false)
	end, { desc = "Next commit (repo)" })
	vim.keymap.set("n", "[R", function()
		cycle_commit("prev", false)
	end, { desc = "Prev commit (repo)" })

	vim.keymap.set("n", "gco", function()
		checkout_commit("to")
	end, { desc = "Checkout TO commit" })
	vim.keymap.set("n", "gcO", function()
		checkout_commit("from")
	end, { desc = "Checkout FROM commit" })
end

return M

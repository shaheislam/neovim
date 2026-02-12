-- Git integration for nvim-mini

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

	-- Function to close the diff (works from either buffer)
	local function close_diff()
		vim.cmd("diffoff!")
		-- Close scratch buffer if it exists
		if vim.api.nvim_buf_is_valid(scratch_buf) then
			vim.cmd("bwipeout " .. scratch_buf)
		end
	end

	-- Add q to close the diff on BOTH buffers
	vim.keymap.set("n", "q", close_diff, { buffer = scratch_buf, desc = "Close diff" })
	vim.keymap.set("n", "q", close_diff, { buffer = original_buf, desc = "Close diff" })

	-- Go back to original window and enable diff
	vim.cmd("wincmd p")
	vim.cmd("diffthis")
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

	-- Add q to close the diff tab (works from either buffer)
	vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = buf1, desc = "Close diff" })
	vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = buf2, desc = "Close diff" })
end

-- Clipboard diff keymaps
vim.keymap.set("n", "<leader>gK", compare_clipboard, { desc = "Compare clipboard vs buffer" })
vim.keymap.set("v", "<leader>gK", compare_clipboard_selection, { desc = "Compare clipboard vs selection" })

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

-- Track buffers modified by diff_buf_read for restoration on view_closed
local diffview_modified_bufs = {}

-- Cross-worktree merge detection state
local cross_worktree_state = {
	active = false,
	original_cwd = nil,
	main_work_dir = nil,
	main_git_dir = nil,
}

-- Repo-following state: tracks which repo root Diffview is currently showing,
-- so BufEnter can detect when the user switches to a buffer in a different repo.
local diffview_current_root = nil

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
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 0, 8, { end_col = 8 + #from_sha_short, hl_group = "CommitInfoSha" })
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 0, from_date_start, { end_col = from_date_end, hl_group = "CommitInfoDate" })
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 0, from_msg_start, { end_col = #lines[1], hl_group = from_msg_hl })

	-- Line 1: TO - "  TO    abc1234  2025-12-01 10:30:15 +0000  commit message"
	local to_date_start = 8 + #to_sha_short + 2
	local to_date_end = to_date_start + #to_date
	local to_msg_start = to_date_end + 2
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 1, 2, { end_col = 4, hl_group = "CommitInfoTo" })
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 1, 8, { end_col = 8 + #to_sha_short, hl_group = "CommitInfoSha" })
	vim.api.nvim_buf_set_extmark(commit_info_bufnr, ns, 1, to_date_start, { end_col = to_date_end, hl_group = "CommitInfoDate" })
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
	local parent_sha = vim.fn.system("MISE_QUIET=1 git rev-parse " .. sha .. "^ 2>/dev/null"):gsub("%s+", "")
	local parent_msg = vim.fn.system("MISE_QUIET=1 git log -1 --format=%s " .. parent_sha .. " 2>/dev/null"):gsub("\n", "")
	local parent_date = vim.fn.system("MISE_QUIET=1 git log -1 --format=%ci " .. parent_sha .. " 2>/dev/null"):gsub("\n", "")
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
	-- Set flag to preserve color state during cycling
	commit_cycle_state.is_cycling = true
	-- Close existing Diffview if open
	pcall(vim.cmd, "DiffviewClose")
	commit_cycle_state.is_cycling = false

	-- Update state
	commit_cycle_state.current_sha = sha
	-- Only update file_path if we're doing file-scoped navigation (not nil)
	if file_path then
		commit_cycle_state.file_path = file_path
	end

	-- Open new Diffview (sha^! means compare sha to its parent)
	vim.cmd("DiffviewOpen " .. sha .. "^!")

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

-- Global keymaps for commit cycling (work from any buffer)
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

-- Keymaps for checking out FROM/TO commits
vim.keymap.set("n", "gco", function()
	checkout_commit("to")
end, { desc = "Checkout TO commit" })
vim.keymap.set("n", "gcO", function()
	checkout_commit("from")
end, { desc = "Checkout FROM commit" })

return {
	-- Gitsigns for visual git indicators and inline operations
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("gitsigns").setup({
				count_chars = {
					[1] = "",
					[2] = "₂",
					[3] = "₃",
					[4] = "₄",
					[5] = "₅",
					[6] = "₆",
					[7] = "₇",
					[8] = "₈",
					[9] = "₉",
					["+"] = "₊",
				},
				signs = {
					add = { show_count = true, text = "│" },
					change = { show_count = true, text = "│" },
					delete = { show_count = true, text = "_" },
					topdelete = { show_count = true, text = "‾" },
					changedelete = { show_count = true, text = "~" },
					untracked = { show_count = false, text = "┆" },
				},
				-- Staged signs configuration (shows different signs for staged changes)
				signs_staged = {
					add = { show_count = true, text = "▎" }, -- Left thick bar for staged adds
					change = { show_count = true, text = "▎" }, -- Left thick bar for staged changes
					delete = { show_count = true, text = "▸" }, -- Triangle for staged deletions
					topdelete = { show_count = true, text = "▾" }, -- Down triangle for staged top deletions
					changedelete = { show_count = true, text = "▊" }, -- Block for staged change+delete
				},
				signs_staged_enable = true, -- Enable staged signs display
				numhl = true, -- Line number highlighting
				linehl = false, -- No line background highlighting
				word_diff = true, -- Word-level diff
				max_file_length = 40000, -- Support word diff on larger files

				-- Current line blame in virtual text
				current_line_blame = true,
				current_line_blame_opts = {
					virt_text = true,
					virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
					delay = 1000,
					ignore_whitespace = false,
					virt_text_priority = 100,
				},
				current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",

				on_attach = function(bufnr)
					local gs = package.loaded.gitsigns

					local function map(mode, l, r, opts)
						opts = opts or {}
						opts.buffer = bufnr
						vim.keymap.set(mode, l, r, opts)
					end

					-- Navigation between hunks using new nav_hunk API
					-- Basic navigation (]c and [c for next/previous change)
					map("n", "]c", function()
						if vim.wo.diff then
							return "]c"
						end
						vim.schedule(function()
							gs.nav_hunk("next", { wrap = true })
						end)
						return "<Ignore>"
					end, { expr = true, desc = "Next Git hunk" })

					map("n", "[c", function()
						if vim.wo.diff then
							return "[c"
						end
						vim.schedule(function()
							gs.nav_hunk("prev", { wrap = true })
						end)
						return "<Ignore>"
					end, { expr = true, desc = "Previous Git hunk" })

					-- Advanced navigation commands
					-- Navigate to first/last hunk
					map("n", "[C", function()
						gs.nav_hunk("first")
					end, { desc = "First Git hunk" })

					map("n", "]C", function()
						gs.nav_hunk("last")
					end, { desc = "Last Git hunk" })

					-- Navigate with auto-preview
					map("n", "]p", function()
						gs.nav_hunk("next", { preview = true })
					end, { desc = "Next hunk with preview" })

					map("n", "[p", function()
						gs.nav_hunk("prev", { preview = true })
					end, { desc = "Previous hunk with preview" })

					-- Navigate only between non-contiguous hunks (skip adjacent changes)
					map("n", "]g", function()
						gs.nav_hunk("next", { greedy = false })
					end, { desc = "Next non-contiguous hunk" })

					map("n", "[g", function()
						gs.nav_hunk("prev", { greedy = false })
					end, { desc = "Previous non-contiguous hunk" })

					-- Navigate between staged hunks only
					map("n", "]s", function()
						gs.nav_hunk("next", { target = "staged" })
					end, { desc = "Next staged hunk" })

					map("n", "[s", function()
						gs.nav_hunk("prev", { target = "staged" })
					end, { desc = "Previous staged hunk" })

					-- Navigate between unstaged hunks only
					map("n", "]u", function()
						gs.nav_hunk("next", { target = "unstaged" })
					end, { desc = "Next unstaged hunk" })

					map("n", "[u", function()
						gs.nav_hunk("prev", { target = "unstaged" })
					end, { desc = "Previous unstaged hunk" })

					-- Hunk actions
					map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage hunk" })
					map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset hunk" })
					map("v", "<leader>hs", function()
						gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end, { desc = "Stage selected hunk" })
					map("v", "<leader>hr", function()
						gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end, { desc = "Reset selected hunk" })
					map("n", "<leader>hS", gs.stage_buffer, { desc = "Stage buffer" })
					map("n", "<leader>hu", gs.undo_stage_hunk, { desc = "Undo stage hunk" })

					-- Stage hunk with preview confirmation
					map("n", "<leader>hP", function()
						gs.preview_hunk()
						vim.ui.select({ "Stage", "Cancel" }, {
							prompt = "Stage this hunk?",
						}, function(choice)
							if choice == "Stage" then
								gs.stage_hunk()
								vim.notify("Hunk staged", vim.log.levels.INFO)
							end
						end)
					end, { desc = "Preview and stage hunk" })
					map("n", "<leader>hR", gs.reset_buffer, { desc = "Reset buffer" })
					map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview hunk" })
					map("n", "<leader>hi", gs.preview_hunk_inline, { desc = "Preview hunk inline" })
					map("n", "<leader>hb", function()
						gs.blame_line({ full = true })
					end, { desc = "Blame line (full)" })
					map("n", "<leader>hB", gs.toggle_current_line_blame, { desc = "Toggle blame line" })
					map("n", "<leader>hv", gs.blame, { desc = "Blame buffer (full)" })

					-- Open blame commit in DiffView
					map("n", "<leader>go", function()
						local blame = vim.b.gitsigns_blame_line_dict
						if not blame then
							vim.notify(
								"No blame info available. Enable current_line_blame or run :Gitsigns blame_line first",
								vim.log.levels.WARN
							)
							return
						end

						-- Handle uncommitted changes (boundary)
						if blame.sha == nil or blame.sha:match("^0+$") then
							vim.notify("Line not yet committed", vim.log.levels.INFO)
							return
						end

						-- Open the commit in DiffView using ^! syntax (single commit diff)
						vim.cmd("DiffviewOpen " .. blame.sha .. "^!")
						-- Show FROM/TO/CKPT info buffer
						show_single_commit_info(blame.sha)
					end, { desc = "Open blame commit in DiffView" })

					-- Advanced diff features
					map("n", "<leader>hd", gs.diffthis, { desc = "Diff this" })
					map("n", "<leader>hD", function()
						gs.diffthis("~")
					end, { desc = "Diff this ~" })

					-- Diff against specific revision
					map("n", "<leader>hc", function()
						vim.ui.input({ prompt = "Diff against revision: " }, function(revision)
							if revision then
								gs.diffthis(revision)
							end
						end)
					end, { desc = "Diff against custom revision" })

					-- Show deleted lines as virtual text
					map("n", "<leader>ht", gs.toggle_deleted, { desc = "Toggle deleted" })

					-- Visual diff toggles
					map("n", "<leader>hw", gs.toggle_word_diff, { desc = "Toggle word diff" })
					map("n", "<leader>hL", gs.toggle_linehl, { desc = "Toggle line highlight" })

					-- Yank deleted lines from current hunk
					map("n", "<leader>hy", function()
						-- Get the current hunk
						local hunks = gs.get_hunks(bufnr)
						if not hunks or #hunks == 0 then
							vim.notify("No hunks found", vim.log.levels.WARN)
							return
						end

						-- Find the hunk at cursor position
						local cursor = vim.api.nvim_win_get_cursor(0)
						local current_line = cursor[1]
						local target_hunk = nil

						for _, hunk in ipairs(hunks) do
							-- Check if cursor is within this hunk's range
							if current_line >= hunk.added.start and current_line <= (hunk.added.start + hunk.added.count) then
								target_hunk = hunk
								break
							end
						end

						if not target_hunk then
							vim.notify("No hunk at cursor position", vim.log.levels.WARN)
							return
						end

						-- Extract deleted lines from the hunk
						local deleted_lines = {}
						if target_hunk.removed and target_hunk.removed.count > 0 then
							-- Get the diff for this hunk
							local diff_text = gs.get_hunks(bufnr, { greedy = false })

							-- Get lines from git show for this hunk
							local file_path = vim.api.nvim_buf_get_name(bufnr)
							local git_cmd = string.format(
								"git diff HEAD -- %s | awk '/^@@.*@@/{flag=1; next} flag && /^-/{print substr($0,2)}'",
								vim.fn.shellescape(file_path)
							)

							local handle = io.popen(git_cmd)
							if handle then
								local result = handle:read("*a")
								handle:close()

								for line in result:gmatch("[^\r\n]+") do
									table.insert(deleted_lines, line)
								end
							end
						end

						if #deleted_lines > 0 then
							-- Join deleted lines and copy to clipboard
							local content = table.concat(deleted_lines, "\n")
							vim.fn.setreg('"', content)
							vim.fn.setreg("+", content) -- Also copy to system clipboard
							vim.notify(string.format("Yanked %d deleted line(s)", #deleted_lines), vim.log.levels.INFO)
						else
							vim.notify("No deleted lines in current hunk", vim.log.levels.WARN)
						end
					end, { desc = "Yank deleted lines from hunk" })

					-- Change and reset diff base
					map("n", "<leader>hC", function()
						vim.ui.input({ prompt = "Change diff base to: " }, function(base)
							if base then
								gs.change_base(base, true)
								vim.notify("Diff base changed to: " .. base, vim.log.levels.INFO)
							end
						end)
					end, { desc = "Change diff base" })

					map("n", "<leader>hE", function()
						gs.change_base(nil, true)
						vim.notify("Diff base reset to index", vim.log.levels.INFO)
					end, { desc = "Reset diff base to index" })

					-- Reset buffer to index or base
					map("n", "<leader>hF", function()
						vim.ui.select({ "Index", "HEAD", "HEAD~1" }, {
							prompt = "Reset buffer to:",
						}, function(choice)
							if choice == "Index" then
								gs.reset_buffer_index()
							else
								-- Reset to specific revision
								vim.cmd("Gitsigns reset_buffer " .. choice)
							end
							vim.notify("Buffer reset to " .. choice, vim.log.levels.INFO)
						end)
					end, { desc = "Reset buffer to revision" })

					-- Toggle highlighting features
					map("n", "<leader>hn", gs.toggle_numhl, { desc = "Toggle line number highlighting" })
					map("n", "<leader>hl", gs.toggle_linehl, { desc = "Toggle line highlighting" })
					map("n", "<leader>hw", gs.toggle_word_diff, { desc = "Toggle word diff" })
					map("n", "<leader>hg", gs.toggle_signs, { desc = "Toggle git signs" })

					-- Quickfix/Location list integration
					map("n", "<leader>hq", function()
						gs.setqflist()
					end, { desc = "Send all hunks to quickfix" })
					map("n", "<leader>hQ", function()
						gs.setqflist("all")
					end, { desc = "Send hunks from all buffers to quickfix" })
					map("n", "<leader>hL", function()
						gs.setloclist()
					end, { desc = "Send hunks to location list" })

					-- Text objects for hunks
					-- ih = inside hunk (only the changed lines)
					map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "Inside hunk" })

					-- ah = around hunk (includes context lines)
					map({ "o", "x" }, "ah", function()
						-- Select hunk with surrounding context
						-- This allows operations like yah, dah, cah to include context
						gs.select_hunk({
							-- Include unchanged lines around the hunk
							expand_region = {
								above = 2,  -- Lines above hunk
								below = 2   -- Lines below hunk
							}
						})
					end, { desc = "Around hunk (with context)" })

					-- Additional visual mode hunk selection commands
					map("n", "<leader>hx", function()
						gs.select_hunk({ greedy = true })
					end, { desc = "Select all contiguous hunks" })

					map("n", "<leader>hX", function()
						gs.select_hunk({ greedy = false })
					end, { desc = "Select only current hunk" })

					-- Visual mode: operate on selected hunks
					map("x", "<leader>hs", function()
						local start_line = vim.fn.line("'<")
						local end_line = vim.fn.line("'>")
						gs.stage_hunk({ start_line, end_line })
					end, { desc = "Stage selected lines" })

					map("x", "<leader>hr", function()
						local start_line = vim.fn.line("'<")
						local end_line = vim.fn.line("'>")
						gs.reset_hunk({ start_line, end_line })
					end, { desc = "Reset selected lines" })
				end,
			})

			-- Set word diff highlights
			vim.api.nvim_set_hl(0, "GitSignsChangeInline", { fg = "#ffdb69", bg = "#3a3a2a" })
			vim.api.nvim_set_hl(0, "GitSignsChangeLnInline", { fg = "#ffdb69", bg = "#3a3a2a" })
			vim.api.nvim_set_hl(0, "GitSignsAddInline", { fg = "#9ece6a", bg = "#1f2231" })
			vim.api.nvim_set_hl(0, "GitSignsAddLnInline", { fg = "#9ece6a", bg = "#1f2231" })
			vim.api.nvim_set_hl(0, "GitSignsDeleteInline", { fg = "#f7768e", bg = "#2d202a" })
			vim.api.nvim_set_hl(0, "GitSignsDeleteLnInline", { fg = "#f7768e", bg = "#2d202a" })

			-- Set staged signs highlights - muted but distinct colors
			vim.api.nvim_set_hl(0, "GitSignsStagedAdd", { fg = "#73c991", bold = true }) -- Soft mint green for staged adds
			vim.api.nvim_set_hl(0, "GitSignsStagedChange", { fg = "#e0af68", bold = true }) -- Soft amber for staged changes
			vim.api.nvim_set_hl(0, "GitSignsStagedDelete", { fg = "#bb7a8c", bold = true }) -- Dusty rose for staged deletes
			vim.api.nvim_set_hl(0, "GitSignsStagedTopdelete", { fg = "#bb7a8c", bold = true }) -- Dusty rose for staged topdeletes
			vim.api.nvim_set_hl(0, "GitSignsStagedChangedelete", { fg = "#c8917a", bold = true }) -- Soft terracotta for staged changedeletes
			vim.api.nvim_set_hl(0, "GitSignsStagedAddNr", { fg = "#73c991", bold = true }) -- Soft mint green for line numbers
			vim.api.nvim_set_hl(0, "GitSignsStagedChangeNr", { fg = "#e0af68", bold = true }) -- Soft amber for line numbers
			vim.api.nvim_set_hl(0, "GitSignsStagedDeleteNr", { fg = "#bb7a8c", bold = true }) -- Dusty rose for line numbers

			-- Also set in ColorScheme autocmd for persistence
			vim.api.nvim_create_autocmd("ColorScheme", {
				pattern = "*",
				callback = function()
					vim.api.nvim_set_hl(0, "GitSignsChangeInline", { fg = "#ffdb69", bg = "#3a3a2a" })
					vim.api.nvim_set_hl(0, "GitSignsChangeLnInline", { fg = "#ffdb69", bg = "#3a3a2a" })
					vim.api.nvim_set_hl(0, "GitSignsAddInline", { fg = "#9ece6a", bg = "#1f2231" })
					vim.api.nvim_set_hl(0, "GitSignsAddLnInline", { fg = "#9ece6a", bg = "#1f2231" })
					vim.api.nvim_set_hl(0, "GitSignsDeleteInline", { fg = "#f7768e", bg = "#2d202a" })
					vim.api.nvim_set_hl(0, "GitSignsDeleteLnInline", { fg = "#f7768e", bg = "#2d202a" })

					-- Staged signs highlights
					vim.api.nvim_set_hl(0, "GitSignsStagedAdd", { fg = "#73c991", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedChange", { fg = "#e0af68", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedDelete", { fg = "#bb7a8c", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedTopdelete", { fg = "#bb7a8c", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedChangedelete", { fg = "#c8917a", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedAddNr", { fg = "#73c991", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedChangeNr", { fg = "#e0af68", bold = true })
					vim.api.nvim_set_hl(0, "GitSignsStagedDeleteNr", { fg = "#bb7a8c", bold = true })
				end,
			})
		end,
	},

	-- Diffview for comprehensive git diff and merge conflict resolution
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
		keys = {
			{
				"<leader>gd",
				function()
					if next(require("diffview.lib").views) == nil then
						vim.cmd("DiffviewOpen")
					else
						vim.cmd("DiffviewClose")
					end
				end,
				desc = "Toggle Diffview",
			},
			{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
			{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Repository History" },
			{ "<leader>gm", "<cmd>DiffviewOpen<cr>", desc = "Open Diffview (merge conflicts)" },
			-- Line evolution tracing - normal mode (single line)
			{
				"<leader>gL",
				function()
					local line = vim.fn.line(".")
					local file = vim.fn.expand("%")
					vim.cmd(string.format("DiffviewFileHistory -L%d,%d:%s", line, line, file))
				end,
				desc = "Line history (cursor)",
			},
			-- Line evolution tracing - visual mode (range)
			{
				"<leader>gL",
				function()
					local start_line = vim.fn.line("'<")
					local end_line = vim.fn.line("'>")
					local file = vim.fn.expand("%")
					vim.cmd(string.format("DiffviewFileHistory -L%d,%d:%s", start_line, end_line, file))
				end,
				mode = "v",
				desc = "Line history (selection)",
			},
			-- PR Review - compare current branch against base (with picker if multiple)
			{
				"<leader>gP",
				function()
					local function get_available_bases()
						local candidates = {
							"origin/main",
							"origin/master",
							"origin/develop",
							"origin/dev",
							"origin/staging",
							"origin/production",
							"origin/prod",
							"origin/release",
							"origin/trunk",
						}
						local available = {}
						for _, branch in ipairs(candidates) do
							vim.fn.system("MISE_QUIET=1 git rev-parse --verify " .. branch .. " 2>/dev/null")
							if vim.v.shell_error == 0 then
								table.insert(available, branch)
							end
						end
						return available
					end

					local function open_diff(base)
						vim.cmd("DiffviewOpen " .. base .. "...HEAD")
					end

					local bases = get_available_bases()

					if #bases == 0 then
						vim.notify("No base branches found (main/master/develop/staging)", vim.log.levels.ERROR)
					elseif #bases == 1 then
						open_diff(bases[1])
					else
						vim.ui.select(bases, {
							prompt = "Compare against:",
						}, function(choice)
							if choice then
								open_diff(choice)
							end
						end)
					end
				end,
				desc = "PR preview (vs base)",
			},
			-- Staged changes only
			{ "<leader>gS", "<cmd>DiffviewOpen --staged<cr>", desc = "Staged changes" },
		},
		config = function()
			local actions = require("diffview.actions")

			require("diffview").setup({
				diff_binaries = false, -- Show diffs for binaries
				enhanced_diff_hl = true, -- Better syntax highlighting in diffs
				git_cmd = { "git" },
				hg_cmd = { "hg" },
				use_icons = true, -- File icons in file panel
				show_help_hints = true, -- Show hint popups in file panel
				watch_index = true, -- Update views on index changes

				-- Signs in file panel
				signs = {
					fold_closed = "",
					fold_open = "",
					done = "✓",
				},

				-- File panel configuration
				file_panel = {
					listing_style = "tree", -- tree or list
					tree_options = {
						flatten_dirs = true, -- Flatten single-child directories
						folder_statuses = "only_folded", -- show_folded, never_folded, only_folded
					},
					win_config = {
						position = "left",
						width = 35,
						win_opts = {},
					},
				},

				-- File history panel configuration
				file_history_panel = {
					log_options = {
						git = {
							single_file = {
								diff_merges = "combined",
							},
							multi_file = {
								diff_merges = "first-parent",
							},
						},
					},
					win_config = {
						position = "bottom",
						height = 16,
						win_opts = {},
					},
				},

				-- Default args for common workflows
				default_args = {
					DiffviewOpen = { "--imply-local", "--diff-algorithm=histogram" }, -- LSP works in range diffs
					DiffviewFileHistory = { "--follow" }, -- Follow file renames
				},

				-- Keymaps for diffview windows
				keymaps = {
					disable_defaults = false, -- Keep default keymaps
					view = {
						-- Navigation
						{ "n", "<tab>", actions.select_next_entry, { desc = "Next file" } },
						{ "n", "<s-tab>", actions.select_prev_entry, { desc = "Previous file" } },
						{ "n", "[F", actions.select_first_entry, { desc = "First file" } },
						{ "n", "]F", actions.select_last_entry, { desc = "Last file" } },
						{ "n", "gf", actions.goto_file_edit, { desc = "Go to file" } },
						{ "n", "<C-w><C-f>", actions.goto_file_split, { desc = "Go to file (split)" } },
						{ "n", "<C-w>gf", actions.goto_file_tab, { desc = "Go to file (tab)" } },

						-- Layout and panels
						{ "n", "g<C-x>", actions.cycle_layout, { desc = "Cycle layout" } },
						{ "n", "<leader>e", actions.focus_files, { desc = "Focus file panel" } },
						{ "n", "<leader>b", actions.toggle_files, { desc = "Toggle file panel" } },
						{ "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },

						-- Conflict resolution (single hunk)
						{ "n", "co", actions.conflict_choose("ours"), { desc = "Choose OURS" } },
						{ "n", "ct", actions.conflict_choose("theirs"), { desc = "Choose THEIRS" } },
						{ "n", "cb", actions.conflict_choose("base"), { desc = "Choose BASE" } },
						{ "n", "ca", actions.conflict_choose("all"), { desc = "Choose ALL" } },
						{ "n", "dx", actions.conflict_choose("none"), { desc = "Delete conflict region" } },

						-- Conflict resolution (whole file)
						{ "n", "<leader>cO", actions.conflict_choose_all("ours"), { desc = "Choose OURS (whole file)" } },
						{ "n", "<leader>cT", actions.conflict_choose_all("theirs"), { desc = "Choose THEIRS (whole file)" } },
						{ "n", "<leader>cB", actions.conflict_choose_all("base"), { desc = "Choose BASE (whole file)" } },
						{ "n", "<leader>cA", actions.conflict_choose_all("all"), { desc = "Choose ALL (whole file)" } },
						{ "n", "dX", actions.conflict_choose_all("none"), { desc = "Delete all conflicts" } },

						-- Navigate between conflicts
						{ "n", "[x", actions.prev_conflict, { desc = "Previous conflict" } },
						{ "n", "]x", actions.next_conflict, { desc = "Next conflict" } },
					},
					file_panel = {
						-- Navigation
						{ "n", "j", actions.next_entry, { desc = "Next entry" } },
						{ "n", "<down>", actions.next_entry, { desc = "Next entry" } },
						{ "n", "k", actions.prev_entry, { desc = "Previous entry" } },
						{ "n", "<up>", actions.prev_entry, { desc = "Previous entry" } },

						-- Selection
						{ "n", "<cr>", actions.select_entry, { desc = "Open diff" } },
						{ "n", "o", actions.select_entry, { desc = "Open diff" } },
						{ "n", "l", actions.select_entry, { desc = "Open diff" } },
						{ "n", "<2-LeftMouse>", actions.select_entry, { desc = "Open diff" } },

						-- Focus/toggle
						{ "n", "-", actions.toggle_stage_entry, { desc = "Stage/unstage file" } },
						{ "n", "s", actions.toggle_stage_entry, { desc = "Stage/unstage file" } },
						{ "n", "S", actions.stage_all, { desc = "Stage all" } },
						{ "n", "U", actions.unstage_all, { desc = "Unstage all" } },

						-- File operations
						{ "n", "R", actions.refresh_files, { desc = "Refresh files" } },
						{ "n", "L", actions.open_commit_log, { desc = "Open commit log" } },

						-- Layout and panels
						{ "n", "g<C-x>", actions.cycle_layout, { desc = "Cycle layout" } },
						{ "n", "<leader>e", actions.focus_entry, { desc = "Focus diff entry" } },
						{ "n", "<leader>b", actions.toggle_files, { desc = "Toggle file panel" } },
						{ "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },

						-- Tree options
						{ "n", "i", actions.listing_style, { desc = "Toggle listing style" } },
						{ "n", "f", actions.toggle_flatten_dirs, { desc = "Toggle flatten dirs" } },

						-- Go to file
						{ "n", "gf", actions.goto_file_edit, { desc = "Go to file" } },
						{ "n", "<C-w><C-f>", actions.goto_file_split, { desc = "Go to file (split)" } },
						{ "n", "<C-w>gf", actions.goto_file_tab, { desc = "Go to file (tab)" } },

						-- Conflict resolution (whole file)
						{ "n", "<leader>cO", actions.conflict_choose_all("ours"), { desc = "Choose OURS (whole file)" } },
						{ "n", "<leader>cT", actions.conflict_choose_all("theirs"), { desc = "Choose THEIRS (whole file)" } },
						{ "n", "<leader>cB", actions.conflict_choose_all("base"), { desc = "Choose BASE (whole file)" } },
						{ "n", "<leader>cA", actions.conflict_choose_all("all"), { desc = "Choose ALL (whole file)" } },
						{ "n", "dX", actions.conflict_choose_all("none"), { desc = "Delete all conflicts" } },
					},
					file_history_panel = {
						-- Navigation
						{ "n", "g!", actions.options, { desc = "Options" } },
						{ "n", "<C-A-d>", actions.open_in_diffview, { desc = "Open in diffview" } },

						-- Entry selection
						{ "n", "<cr>", actions.select_entry, { desc = "Open diff" } },
						{ "n", "o", actions.select_entry, { desc = "Open diff" } },
						{ "n", "<2-LeftMouse>", actions.select_entry, { desc = "Open diff" } },

						-- Copy info
						{ "n", "y", actions.copy_hash, { desc = "Copy commit hash" } },

						-- Layout and panels
						{ "n", "g<C-x>", actions.cycle_layout, { desc = "Cycle layout" } },
						{ "n", "<leader>e", actions.focus_entry, { desc = "Focus diff entry" } },
						{ "n", "<leader>b", actions.toggle_files, { desc = "Toggle file panel" } },
						{ "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } },
					},
					option_panel = {
						{ "n", "<tab>", actions.select_entry, { desc = "Select option" } },
						{ "n", "q", actions.close, { desc = "Close panel" } },
					},
				},

				-- View configuration
				view = {
					-- Available layouts:
					-- 'diff1_plain' - Simple diff with no file panel
					-- 'diff2_horizontal' - Two panes horizontally
					-- 'diff2_vertical' - Two panes vertically
					-- 'diff3_horizontal' - Three panes horizontally (useful for merge conflicts)
					-- 'diff3_vertical' - Three panes vertically
					-- 'diff3_mixed' - Mixed layout
					-- 'diff4_mixed' - Four panes (for complex merges with BASE)

					default = {
						-- Layout depends on context:
						-- Normal diff: 'diff2_horizontal'
						-- Merge conflict: 'diff3_horizontal'
						layout = "diff2_horizontal",
						disable_diagnostics = true, -- Disable LSP diagnostics in diff buffers (reduces lag)
						winbar_info = true,
					},
					merge_tool = {
						-- Layout for merge conflicts
						layout = "diff3_horizontal",
						disable_diagnostics = true,
						winbar_info = true,
					},
					file_history = {
						layout = "diff2_horizontal",
						disable_diagnostics = true, -- Disable LSP diagnostics in file history diff buffers
						winbar_info = true,
					},
				},

				-- Lifecycle and buffer hooks
				hooks = {
					-- Called when diffview is opened
					view_opened = function(view)
						vim.notify("Diffview opened", vim.log.levels.DEBUG)
						-- Track which repo root this Diffview is showing (for repo-following)
						diffview_current_root = find_repo_root(vim.fn.getcwd())
						-- Track whether we're in a conflict state (to detect transitions)
						-- Checks MERGE_HEAD, REBASE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD
						local git_path = get_git_dir()
						if git_path then
							view._was_merging = check_conflict_state(git_path) ~= nil
							local handle = vim.uv.new_fs_event()
							if handle then
								local debounce_timer = nil
								local reopening = false
								handle:start(git_path, { recursive = true }, function(err, filename, events)
									if err then return end
									if vim.g.diffview_auto_switch == false then return end
									vim.schedule(function()
										-- Debounce to avoid excessive refreshes
										if debounce_timer then
											debounce_timer:stop()
										end
										debounce_timer = vim.defer_fn(function()
											debounce_timer = nil
											if reopening then return end

											-- Check if conflict state changed
											local is_merging = check_conflict_state(git_path) ~= nil
											if is_merging ~= view._was_merging then
												view._was_merging = is_merging
												-- Reopen Diffview to switch between normal and merge conflict view
												-- Stop watcher first to avoid callback-during-close issues
												reopening = true
												handle:stop()
												view._git_watcher = nil
												pcall(vim.cmd, "DiffviewClose")
												vim.defer_fn(function()
													pcall(vim.cmd, "DiffviewOpen")
													reopening = false
												end, 100)
												return
											end

											-- Normal refresh for non-merge-state changes
											local ok, lib = pcall(require, "diffview.lib")
											if ok then
												local current_view = lib.get_current_view()
												if current_view and current_view.update_files then
													current_view:update_files()
												end
											end
										end, 300)
									end)
								end)
								-- Store handle for cleanup
								view._git_watcher = handle
							end
						end

						-- Cross-worktree merge detection: watch main repo's .git/ for MERGE_HEAD
						local main_info = get_main_repo_info()
						if main_info then
							vim.notify("Cross-worktree: watching " .. main_info.main_git_dir, vim.log.levels.DEBUG)
							local main_handle = vim.uv.new_fs_event()
							if main_handle then
								local main_debounce_timer = nil
								local main_reopening = false
								main_handle:start(main_info.main_git_dir, { recursive = true }, function(err, filename, events)
									if err then
										vim.schedule(function()
											vim.notify("Cross-worktree watcher error: " .. tostring(err), vim.log.levels.ERROR)
										end)
										return
									end
									if vim.g.diffview_auto_switch == false then return end
									vim.schedule(function()
										vim.notify("Cross-worktree fs_event: " .. tostring(filename), vim.log.levels.DEBUG)
									end)
									vim.schedule(function()
										if main_debounce_timer then
											main_debounce_timer:stop()
										end
										main_debounce_timer = vim.defer_fn(function()
											main_debounce_timer = nil
											if main_reopening then return end

											local main_merging = check_conflict_state(main_info.main_git_dir) ~= nil

											if main_merging and not cross_worktree_state.active then
												-- Main repo started a conflict op - switch to show its conflicts
												main_reopening = true
												cross_worktree_state.active = true
												cross_worktree_state.original_cwd = vim.fn.getcwd()
												cross_worktree_state.main_work_dir = main_info.main_work_dir
												cross_worktree_state.main_git_dir = main_info.main_git_dir
												main_handle:stop()
												view._main_repo_watcher = nil
												pcall(vim.cmd, "DiffviewClose")
												vim.defer_fn(function()
													pcall(vim.cmd, "DiffviewOpen -C" .. main_info.main_work_dir)
													main_reopening = false
												end, 100)
											elseif not main_merging and cross_worktree_state.active then
												-- Main repo conflict resolved - switch back to worktree view
												main_reopening = true
												local orig_cwd = cross_worktree_state.original_cwd
												cross_worktree_state.active = false
												cross_worktree_state.original_cwd = nil
												cross_worktree_state.main_work_dir = nil
												cross_worktree_state.main_git_dir = nil
												main_handle:stop()
												view._main_repo_watcher = nil
												pcall(vim.cmd, "DiffviewClose")
												vim.defer_fn(function()
													pcall(vim.cmd, "DiffviewOpen")
													main_reopening = false
												end, 100)
											end
										end, 300)
									end)
								end)
								view._main_repo_watcher = main_handle
							end
						end
					end,
					-- Called when diffview is closed
					view_closed = function(view)
						vim.notify("Diffview closed", vim.log.levels.DEBUG)
						diffview_current_root = nil
						-- Stop git watcher
						if view._git_watcher then
							view._git_watcher:stop()
							view._git_watcher:close()
							view._git_watcher = nil
						end
						-- Stop main repo watcher (cross-worktree)
						if view._main_repo_watcher then
							view._main_repo_watcher:stop()
							view._main_repo_watcher:close()
							view._main_repo_watcher = nil
						end
						-- Reset commit cycling state
						commit_cycle_state.current_sha = nil
						commit_cycle_state.file_path = nil
						commit_cycle_state.from_sha = nil
						commit_cycle_state.to_sha = nil
						-- Only reset colors if user manually closed (not cycling)
						if not commit_cycle_state.is_cycling then
							commit_cycle_state.sha_colors = {}
							commit_cycle_state.next_color_idx = 1
						end
						-- Close commit info window if open
						close_commit_info_window()

						-- Restore treesitter/diagnostics/gitsigns on persisting buffers
						-- (diffview:// buffers are wiped by now; only real files persist)
						vim.schedule(function()
							for bufnr, _ in pairs(diffview_modified_bufs) do
								if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
									-- Re-enable treesitter highlighting
									if vim.treesitter.start then
										pcall(vim.treesitter.start, bufnr)
									end
									-- Re-enable diagnostics
									pcall(vim.diagnostic.enable, true, { bufnr = bufnr })
									-- Re-attach gitsigns
									if package.loaded.gitsigns then
										pcall(require("gitsigns").attach, bufnr)
									end
								end
							end
							diffview_modified_bufs = {}
						end)
					end,
					diff_buf_read = function(bufnr)
						-- Track this buffer for restoration when diffview closes
						diffview_modified_bufs[bufnr] = true

						-- Set local options for diff buffers
						vim.opt_local.wrap = false
						vim.opt_local.list = false
						vim.opt_local.colorcolumn = { 80 }

						-- Reduce redraw cost: disable expensive per-line rendering
						vim.wo.cursorline = false
						vim.wo.relativenumber = false
						vim.wo.signcolumn = "no"
						vim.wo.foldcolumn = "0"
						vim.wo.foldmethod = "manual"
						vim.wo.statuscolumn = "%{v:lnum} "

						-- Detach gitsigns from diff buffers (prevents blame/word_diff per-buffer)
						vim.defer_fn(function()
							if package.loaded.gitsigns then
								local ok, err = pcall(require("gitsigns").detach, bufnr)
								if not ok then
									vim.notify("gitsigns detach failed: " .. tostring(err), vim.log.levels.DEBUG)
								end
							end
						end, 50)

						-- Stop treesitter highlighting in diff buffers (diffview uses its own highlighting)
						vim.defer_fn(function()
							if vim.treesitter.stop then
								local ok, err = pcall(vim.treesitter.stop, bufnr)
								if not ok then
									vim.notify("treesitter stop failed (buf " .. bufnr .. "): " .. tostring(err), vim.log.levels.DEBUG)
								end
							end
						end, 50)

						-- Disable diagnostics per-buffer (more reliable than view config alone)
						local ok, err = pcall(vim.diagnostic.enable, false, { bufnr = bufnr })
						if not ok then
							vim.notify("diagnostic disable failed (buf " .. bufnr .. "): " .. tostring(err), vim.log.levels.DEBUG)
						end

						-- Detach terraform-ls from diff buffers (crashes on diffview:// URIs).
						-- Other LSP clients are NOT detached to avoid reattachment issues
						-- when diffview closes; the is_diff_buf() guards in lsp.lua prevent
						-- their expensive per-cursor operations instead.
						vim.defer_fn(function()
							local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "terraformls" })
							for _, client in ipairs(clients) do
								local ok, err = pcall(vim.lsp.buf_detach_client, bufnr, client.id)
								if not ok then
									vim.notify("LSP detach failed (terraformls, buf " .. bufnr .. "): " .. tostring(err), vim.log.levels.DEBUG)
								end
							end
						end, 100)

						-- Ensure q closes diffview in ALL diff buffers (including index)
						vim.keymap.set("n", "q", "<cmd>DiffviewClose<cr>", {
							buffer = bufnr,
							desc = "Close Diffview",
						})
					end,
				},
			})

			-- Shared conflict-state polling: checks local + cross-worktree git conflict files
			-- (MERGE_HEAD, REBASE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD)
			-- Returns true if a reopen was triggered (caller should return early)
			-- Respects vim.g.diffview_auto_switch toggle.
			local function poll_merge_state()
				if vim.g.diffview_auto_switch == false then
					return false
				end
				local ok, lib = pcall(require, 'diffview.lib')
				if not ok then
					return false
				end
				local view = lib.get_current_view()
				if not view then
					return false
				end

				local git_path = get_git_dir()
				if not git_path then
					return false
				end

				-- Check local worktree conflict state (merge, rebase, cherry-pick, revert)
				local is_conflicting = check_conflict_state(git_path) ~= nil
				if view._was_merging ~= nil and is_conflicting ~= view._was_merging then
					view._was_merging = is_conflicting
					pcall(vim.cmd, 'DiffviewClose')
					vim.defer_fn(function()
						pcall(vim.cmd, 'DiffviewOpen')
					end, 100)
					return true
				end

				-- Cross-worktree: check if main repo started/finished a conflict
				local main_info = get_main_repo_info()
				if main_info then
					local main_conflicting = check_conflict_state(main_info.main_git_dir) ~= nil
					if main_conflicting and not cross_worktree_state.active then
						cross_worktree_state.active = true
						cross_worktree_state.original_cwd = vim.fn.getcwd()
						cross_worktree_state.main_work_dir = main_info.main_work_dir
						cross_worktree_state.main_git_dir = main_info.main_git_dir
						diffview_current_root = main_info.main_work_dir:gsub("/$", "")
						pcall(vim.cmd, 'DiffviewClose')
						vim.defer_fn(function()
							pcall(vim.cmd, 'DiffviewOpen -C' .. main_info.main_work_dir)
						end, 100)
						return true
					elseif not main_conflicting and cross_worktree_state.active then
						cross_worktree_state.active = false
						cross_worktree_state.original_cwd = nil
						cross_worktree_state.main_work_dir = nil
						cross_worktree_state.main_git_dir = nil
						diffview_current_root = find_repo_root(vim.fn.getcwd())
						pcall(vim.cmd, 'DiffviewClose')
						vim.defer_fn(function()
							pcall(vim.cmd, 'DiffviewOpen')
						end, 100)
						return true
					end
				end

				return false
			end

			-- Detection event autocmds. All bail early if Diffview isn't open
			-- (poll_merge_state checks lib.get_current_view(); explicit guards below).
			--
			-- fs_event watchers (view_opened) remain the primary detection mechanism;
			-- these autocmds are fallbacks for when fs_event misses changes, which
			-- occurs on macOS when FSEvents coalesces rapid .git/ writes (kernel
			-- batches events within ~1s; git merge writes multiple files in quick
			-- succession, so individual file events may be dropped or merged).
			--
			-- ModeChanged is intentionally not used: the only mode transition that
			-- matters for conflict detection is leaving terminal mode (where git
			-- commands run), which TermLeave already covers. Normal/insert/visual
			-- transitions don't create or resolve git conflicts.
			--
			-- Debounce rationale:
			--   200ms (terminal/focus events): git merge writes MERGE_HEAD within
			--     ~50ms of exit; 200ms provides margin for slow I/O.
			--   500ms (WinEnter): fires frequently during window navigation; 500ms
			--     batches rapid switches into one check. Worst-case: 500ms delay.
			--   800ms (retry): one-shot second check after the initial 200ms to
			--     cover FSEvents coalescing. Total ~1s from event, bounded.
			local dv_focus_group = vim.api.nvim_create_augroup('diffview_focus_refresh', { clear = true })

			-- Poll with bounded retry: initial check + one-shot retry at 800ms.
			-- Covers FSEvents coalescing where the first fs_stat misses a slow write.
			local function poll_with_retry()
				if poll_merge_state() then
					return
				end
				-- Refresh files immediately for non-conflict git changes
				local ok, lib = pcall(require, 'diffview.lib')
				if ok then
					local view = lib.get_current_view()
					if view and view.update_files then
						view:update_files()
					end
				end
				-- Bounded retry: re-check once at ~1s total from event
				vim.defer_fn(function()
					poll_merge_state()
				end, 800)
			end

			-- FocusGained: catches external app switches (tmux pane, terminal app focus)
			vim.api.nvim_create_autocmd('FocusGained', {
				group = dv_focus_group,
				callback = function()
					vim.defer_fn(poll_with_retry, 200)
				end,
				desc = 'Refresh Diffview on focus gain (conflict detection)',
			})

			-- TermLeave/TermClose: detect conflicts started from :terminal splits.
			-- TermLeave fires on Ctrl-\ Ctrl-n (leaving terminal mode).
			-- TermClose fires when the terminal job exits.
			-- Together they cover intra-Neovim gaps where FocusGained doesn't fire.
			for _, event in ipairs({ 'TermLeave', 'TermClose' }) do
				vim.api.nvim_create_autocmd(event, {
					group = dv_focus_group,
					callback = function()
						vim.defer_fn(poll_with_retry, 200)
					end,
					desc = 'Refresh Diffview on ' .. event .. ' (conflict detection)',
				})
			end

			-- WinEnter: catch-all for any window switch while Diffview is open.
			-- Subsumes BufEnter/BufWinEnter since WinEnter fires on all window
			-- transitions. Scoped: bails immediately if no Diffview view is open.
			local win_enter_timer = nil
			vim.api.nvim_create_autocmd('WinEnter', {
				group = dv_focus_group,
				callback = function()
					-- Only check if Diffview is currently open
					local ok, lib = pcall(require, 'diffview.lib')
					if not ok or not lib.get_current_view() then
						return
					end
					-- Debounce: skip if recently checked
					if win_enter_timer then
						return
					end
					win_enter_timer = vim.defer_fn(function()
						win_enter_timer = nil
						poll_merge_state()
					end, 500)
				end,
				desc = 'Poll conflict state on window switch while Diffview is open',
			})

			-- BufEnter: repo-following — when the user switches to a buffer in a
			-- different git repo, retarget Diffview to show that repo's changes.
			-- Skips Diffview's own buffers (diffview://) and terminal buffers (term://).
			-- Debounced at 300ms to avoid thrashing during rapid buffer switches.
			local buf_enter_timer = nil
			local buf_enter_switching = false
			vim.api.nvim_create_autocmd('BufEnter', {
				group = dv_focus_group,
				callback = function()
					if vim.g.diffview_follow_repo == false then
						return
					end
					if buf_enter_switching then
						return
					end

					local ok, lib = pcall(require, 'diffview.lib')
					if not ok or not lib.get_current_view() then
						return
					end

					local bufname = vim.api.nvim_buf_get_name(0)
					if bufname == "" or bufname:match("^diffview://") or bufname:match("^term://") then
						return
					end

					if buf_enter_timer then
						return
					end
					buf_enter_timer = vim.defer_fn(function()
						buf_enter_timer = nil
						local buf_dir = vim.fn.fnamemodify(bufname, ":h")
						local buf_root = find_repo_root(buf_dir)
						if not buf_root then
							return
						end
						if diffview_current_root and buf_root ~= diffview_current_root then
							buf_enter_switching = true
							diffview_current_root = buf_root
							pcall(vim.cmd, 'DiffviewClose')
							vim.defer_fn(function()
								pcall(vim.cmd, 'DiffviewOpen -C' .. buf_root)
								buf_enter_switching = false
							end, 100)
						end
					end, 300)
				end,
				desc = 'Follow buffer repo: retarget Diffview when switching to a different repo',
			})

			-- Arbitrary file comparison command (VSCode-style syntax)
			vim.api.nvim_create_user_command("DiffFiles", function(opts)
				local args = vim.split(opts.args, " ")
				if #args ~= 2 then
					vim.notify("Usage: DiffFiles <file1> <file2>", vim.log.levels.ERROR)
					return
				end
				vim.cmd("tabnew " .. vim.fn.fnameescape(args[1]))
				vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(args[2]))
			end, { nargs = "+", complete = "file", desc = "Diff two arbitrary files" })

			-- Keymap for interactive file comparison
			vim.keymap.set("n", "<leader>gF", function()
				vim.ui.input({ prompt = "File 1: ", completion = "file" }, function(file1)
					if file1 then
						vim.ui.input({ prompt = "File 2: ", completion = "file" }, function(file2)
							if file2 then
								vim.cmd("DiffFiles " .. file1 .. " " .. file2)
							end
						end)
					end
				end)
			end, { desc = "Diff two files" })
		end,
	},

	-- Fugitive for comprehensive Git integration
	{
		"tpope/vim-fugitive",
		cmd = { "Git", "G", "Gread", "Gwrite", "Gdiffsplit", "Gvdiffsplit", "Gedit", "Gsplit", "GBrowse" },
		keys = {
			{
				"<leader>gp",
				function()
					vim.cmd("belowright 15split")
					vim.cmd("Git push")
				end,
				desc = "Git push",
			},
			{
				"<leader>gc",
				function()
					vim.cmd("belowright split")
					vim.cmd("Git commit")
				end,
				desc = "Git commit",
			},
			{ "<leader>gB", "<cmd>GBrowse<cr>", desc = "Open in GitHub/GitLab" },
		},
		init = function()
			-- Command-line abbreviations for Git commands (init runs before plugin loads)
			vim.cmd([[
				" Base command
				cnoreabbrev <expr> G getcmdtype() == ':' && getcmdline() == 'G' ? 'Git' : 'G'

				" User-requested abbreviations
				cnoreabbrev <expr> gst getcmdtype() == ':' && getcmdline() == 'gst' ? 'Git status' : 'gst'
				cnoreabbrev <expr> gco getcmdtype() == ':' && getcmdline() == 'gco' ? 'Git checkout' : 'gco'
				cnoreabbrev <expr> gpo getcmdtype() == ':' && getcmdline() == 'gpo' ? 'Git push origin' : 'gpo'
				cnoreabbrev <expr> gpof getcmdtype() == ':' && getcmdline() == 'gpof' ? 'Git push origin --force-with-lease' : 'gpof'
				cnoreabbrev <expr> gll getcmdtype() == ':' && getcmdline() == 'gll' ? 'Git pull' : 'gll'

				" Basic operations
				cnoreabbrev <expr> ga getcmdtype() == ':' && getcmdline() == 'ga' ? 'Git add' : 'ga'
				cnoreabbrev <expr> gaa getcmdtype() == ':' && getcmdline() == 'gaa' ? 'Git add --all' : 'gaa'
				cnoreabbrev <expr> gc getcmdtype() == ':' && getcmdline() == 'gc' ? 'Git commit' : 'gc'
				cnoreabbrev <expr> gca getcmdtype() == ':' && getcmdline() == 'gca' ? 'Git commit --amend' : 'gca'
				cnoreabbrev <expr> gcm getcmdtype() == ':' && getcmdline() == 'gcm' ? 'Git commit -m' : 'gcm'

				" Viewing changes
				cnoreabbrev <expr> gd getcmdtype() == ':' && getcmdline() == 'gd' ? 'Git diff' : 'gd'
				cnoreabbrev <expr> gds getcmdtype() == ':' && getcmdline() == 'gds' ? 'Git diff --staged' : 'gds'
				cnoreabbrev <expr> gl getcmdtype() == ':' && getcmdline() == 'gl' ? 'Git log' : 'gl'
				cnoreabbrev <expr> glo getcmdtype() == ':' && getcmdline() == 'glo' ? 'Git log --oneline -20' : 'glo'
				cnoreabbrev <expr> glg getcmdtype() == ':' && getcmdline() == 'glg' ? 'Git log --graph --oneline' : 'glg'

				" Branch operations
				cnoreabbrev <expr> gb getcmdtype() == ':' && getcmdline() == 'gb' ? 'Git branch' : 'gb'
				cnoreabbrev <expr> gbd getcmdtype() == ':' && getcmdline() == 'gbd' ? 'Git branch -d' : 'gbd'
				cnoreabbrev <expr> gbD getcmdtype() == ':' && getcmdline() == 'gbD' ? 'Git branch -D' : 'gbD'
				cnoreabbrev <expr> gsw getcmdtype() == ':' && getcmdline() == 'gsw' ? 'Git switch' : 'gsw'

				" Push/Pull operations
				cnoreabbrev <expr> gp getcmdtype() == ':' && getcmdline() == 'gp' ? 'Git push' : 'gp'
				cnoreabbrev <expr> gpf getcmdtype() == ':' && getcmdline() == 'gpf' ? 'Git push --force-with-lease' : 'gpf'
				cnoreabbrev <expr> gpu getcmdtype() == ':' && getcmdline() == 'gpu' ? 'Git push -u origin HEAD' : 'gpu'

				" Advanced operations
				cnoreabbrev <expr> gf getcmdtype() == ':' && getcmdline() == 'gf' ? 'Git fetch' : 'gf'
				cnoreabbrev <expr> gfa getcmdtype() == ':' && getcmdline() == 'gfa' ? 'Git fetch --all' : 'gfa'
				cnoreabbrev <expr> gm getcmdtype() == ':' && getcmdline() == 'gm' ? 'Git merge' : 'gm'
				cnoreabbrev <expr> gr getcmdtype() == ':' && getcmdline() == 'gr' ? 'Git rebase' : 'gr'
				cnoreabbrev <expr> gri getcmdtype() == ':' && getcmdline() == 'gri' ? 'Git rebase -i' : 'gri'
				cnoreabbrev <expr> gsh getcmdtype() == ':' && getcmdline() == 'gsh' ? 'Git stash' : 'gsh'
				cnoreabbrev <expr> gshp getcmdtype() == ':' && getcmdline() == 'gshp' ? 'Git stash pop' : 'gshp'
				cnoreabbrev <expr> gcp getcmdtype() == ':' && getcmdline() == 'gcp' ? 'Git cherry-pick' : 'gcp'
				cnoreabbrev <expr> grh getcmdtype() == ':' && getcmdline() == 'grh' ? 'Git reset HEAD' : 'grh'
				cnoreabbrev <expr> grhh getcmdtype() == ':' && getcmdline() == 'grhh' ? 'Git reset --hard HEAD' : 'grhh'
			]])
		end,
		config = function()
			-- Configure Ivy-style appearance for fugitive buffers
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "fugitive",
				callback = function(args)
					-- Ivy-style minimal appearance
					vim.wo.number = false
					vim.wo.relativenumber = false
					vim.wo.signcolumn = "no"
					vim.wo.foldcolumn = "0"
					vim.wo.wrap = false
					vim.wo.cursorline = true
					vim.wo.statusline = " Git " -- Minimal status line

					-- Buffer-local keymaps for Ivy-style navigation
					local opts = { buffer = args.buf, silent = true }
					vim.keymap.set("n", "q", "<cmd>close<cr>", vim.tbl_extend("force", opts, { desc = "Close" }))
					vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", vim.tbl_extend("force", opts, { desc = "Close" }))
					vim.keymap.set("n", "r", "<cmd>edit<cr>", vim.tbl_extend("force", opts, { desc = "Refresh" }))
					vim.keymap.set("n", "<CR>", "<CR>", vim.tbl_extend("force", opts, { desc = "Select/Open" }))
				end,
				group = vim.api.nvim_create_augroup("FugitiveIvyStyle", { clear = true }),
			})

			-- Auto-style git commit buffers
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "gitcommit",
				callback = function(args)
					vim.wo.number = true
					vim.wo.relativenumber = false
					vim.wo.signcolumn = "no"
					vim.wo.colorcolumn = "72"
					vim.bo.textwidth = 72

					-- Commit buffer keymaps
					local opts = { buffer = args.buf, silent = true }
					vim.keymap.set("n", "q", "<cmd>close<cr>", vim.tbl_extend("force", opts, { desc = "Cancel commit" }))
				end,
				group = vim.api.nvim_create_augroup("GitCommitStyle", { clear = true }),
			})
		end,
	},
}

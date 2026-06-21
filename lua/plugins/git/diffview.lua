-- Diffview for comprehensive git diff and merge conflict resolution

local workflow = require("git.workflow")
local return_target = require("config.return_target")
local git_command = require("git.command")
local commit_cycle_state = workflow.commit_cycle_state
local cross_worktree_state = workflow.cross_worktree_state
local close_commit_info_window = workflow.close_commit_info_window
local find_repo_root = workflow.find_repo_root
local path_is_under = workflow.path_is_under
local get_terminal_cwd = workflow.get_terminal_cwd
local get_tmux_last_pane_cwd = workflow.get_tmux_last_pane_cwd
local get_tmux_last_pane_cwd_async = workflow.get_tmux_last_pane_cwd_async
local get_tmux_active_pane_cwd = workflow.get_tmux_active_pane_cwd
local get_tmux_active_pane_cwd_async = workflow.get_tmux_active_pane_cwd_async
local check_conflict_state = workflow.check_conflict_state
local get_git_dir = workflow.get_git_dir
local get_main_repo_info = workflow.get_main_repo_info

local diffview_modified_bufs = {}
local diffview_current_root = nil
local diffview_return_target = nil
local diffview_suppress_restore = false
local follow_rpc_seq = 0
local follow_timer_seen_seq = 0

local function close_diffview_restore()
	vim.cmd("DiffviewClose")
end

local function diffview_internal_reopen(command)
	diffview_suppress_restore = true
	pcall(vim.cmd, "DiffviewClose")
	vim.defer_fn(function()
		pcall(vim.cmd, command)
		diffview_suppress_restore = false
	end, 100)
end

local function capture_return()
	diffview_return_target = return_target.capture({ force = true }) or return_target.last()
end

return {
	"dlyongemallo/diffview.nvim",
	dependencies = { "nvim-lua/plenary.nvim" },
	cmd = {
		"DiffviewOpen",
		"DiffviewToggle",
		"DiffviewFileHistory",
		"DiffviewDiffFiles",
		"DiffviewLog",
		"DiffviewClose",
		"DiffviewToggleFiles",
		"DiffviewFocusFiles",
		"DiffFiles",
	},
	keys = {
		{
			"<leader>gd",
			function()
				if next(require("diffview.lib").views) == nil then
					capture_return()
					vim.cmd("DiffviewOpen")
				else
					close_diffview_restore()
				end
			end,
			desc = "Toggle Diffview",
		},
		{
			"<leader>gh",
			function()
				capture_return()
				vim.cmd("DiffviewFileHistory %")
			end,
			desc = "File History",
		},
		{
			"<leader>gH",
			function()
				capture_return()
				vim.cmd("DiffviewFileHistory")
			end,
			desc = "Repository History",
		},
		{
			"<leader>gm",
			function()
				capture_return()
				vim.cmd("DiffviewOpen")
			end,
			desc = "Open Diffview (merge conflicts)",
		},
		-- Line evolution tracing - normal mode (single line)
		{
			"<leader>gL",
			function()
				local line = vim.fn.line(".")
				local file = vim.fn.expand("%")
				capture_return()
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
				capture_return()
				vim.cmd(string.format("DiffviewFileHistory -L%d,%d:%s", start_line, end_line, file))
			end,
			mode = "v",
			desc = "Line history (selection)",
		},
		-- PR Review - compare current branch against base (with picker if multiple)
		{
			"<leader>gP",
			function()
				local function add_unique(list, seen, branch)
					branch = vim.trim(branch or "")
					if branch == "" or seen[branch] then
						return
					end

					if git_command.succeeds({ "rev-parse", "--verify", branch }) then
						seen[branch] = true
						table.insert(list, branch)
					end
				end

				local function get_available_bases()
					local available = {}
					local seen = {}

					local _, upstream = git_command.output({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" })
					add_unique(available, seen, upstream)

					local _, default_branch = git_command.output({ "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
					add_unique(available, seen, default_branch)

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
					for _, branch in ipairs(candidates) do
						add_unique(available, seen, branch)
					end
					return available
				end

				local function open_diff(base)
					capture_return()
					vim.cmd("DiffviewOpen " .. vim.fn.fnameescape(base .. "...HEAD"))
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
		{
			"<leader>gS",
			function()
				capture_return()
				vim.cmd("DiffviewOpen --staged")
			end,
			desc = "Staged changes",
		},
		{
			"<leader>gT",
			function()
				capture_return()
				vim.cmd("DiffviewFileHistory -g --range=stash")
			end,
			desc = "Stash history",
		},
		{
			"<leader>gR",
			function()
				vim.ui.input({ prompt = "Diffview rev range: " }, function(input)
					if not input or vim.trim(input) == "" then
						return
					end
					vim.cmd("DiffviewSetRevs " .. input)
				end)
			end,
			desc = "Retarget Diffview revs",
		},
		{ "<leader>gr", "<cmd>DiffviewReviewedList<cr>", desc = "Reviewed files" },
		{ "<leader>gX", "<cmd>DiffviewReviewedClear<cr>", desc = "Clear reviewed files" },
		{
			"<leader>gF",
			function()
				vim.ui.input({ prompt = "File 1: ", completion = "file" }, function(file1)
					if not file1 or file1 == "" then
						return
					end
					vim.ui.input({ prompt = "File 2: ", completion = "file" }, function(file2)
						if file2 and file2 ~= "" then
							vim.cmd("DiffFiles " .. vim.fn.fnameescape(file1) .. " " .. vim.fn.fnameescape(file2))
						end
					end)
				end)
			end,
			desc = "Diff two files",
		},
	},
	config = function()
		local actions = require("diffview.actions")
		local api = require("diffview.api")
		local function jump_to_first_change()
			local ok, lib = pcall(require, "diffview.lib")
			local view = ok and lib.get_current_view() or nil
			if not view then
				vim.notify("Open a Diffview first", vim.log.levels.WARN)
				return
			end

			actions.jump_to_first_change(view)
		end

		local function diffview_auto_switch_enabled()
			return vim.g.diffview_auto_switch ~= false
		end

		-- Forward declarations: auto-follow functions referenced in
		-- view_opened/view_closed callbacks below.  The callbacks are inline
		-- closures (function(view) start_follow_timer() end) so Lua captures
		-- the upvalue *slot*, not the current value — the actual lookup happens
		-- at call-time (view open/close), by which point these are assigned.
		local check_tmux_pane_and_retarget
		local follow_timer = nil
		local follow_timer_refs = 0
		local start_follow_timer
		local stop_follow_timer
		local gutter_ns = vim.api.nvim_create_namespace("diffview_gutter_signs")
		local word_change_ns = vim.api.nvim_create_namespace("diffview_word_changes")

		local function is_old_diff_side(winid)
			local win_pos = vim.fn.win_screenpos(winid)
			local win_col = win_pos[2] or 0
			local rightmost_col = win_col

			for _, other_winid in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(other_winid) and vim.wo[other_winid].diff then
					local other_pos = vim.fn.win_screenpos(other_winid)
					rightmost_col = math.max(rightmost_col, other_pos[2] or 0)
				end
			end

			return win_col < rightmost_col
		end

		local function refresh_diffview_gutters(bufnr)
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			vim.api.nvim_buf_clear_namespace(bufnr, gutter_ns, 0, -1)
			local placed = {}

			for _, ns in pairs(vim.api.nvim_get_namespaces()) do
				if ns ~= gutter_ns then
					local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, bufnr, ns, 0, -1, { details = true })
					if ok then
						for _, mark in ipairs(marks) do
							local row = mark[2]
							local details = mark[4]
							local line_hl = details and details.line_hl_group
							local gutter_hl

							if line_hl == "DiffviewDiffDelete" or line_hl == "DiffviewDiffAddAsDelete" then
								gutter_hl = "DiffviewGutterDelete"
							elseif line_hl == "DiffviewDiffChange" or line_hl == "DiffviewDiffText" then
								gutter_hl = "DiffviewGutterChange"
							end

							if gutter_hl and not placed[row] then
								vim.api.nvim_buf_set_extmark(bufnr, gutter_ns, row, 0, {
									sign_text = "▎",
									sign_hl_group = gutter_hl,
									priority = 300,
								})
								placed[row] = true
							end
						end
					end
				end
			end

			local current_win = vim.api.nvim_get_current_win()
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
					pcall(vim.api.nvim_set_current_win, winid)
					local old_diff_side = is_old_diff_side(winid)
					for row = 0, vim.api.nvim_buf_line_count(bufnr) - 1 do
						if not placed[row] then
							local diff_hl_id = vim.fn.diff_hlID(row + 1, 1)
							local diff_hl = diff_hl_id > 0 and vim.fn.synIDattr(diff_hl_id, "name") or ""
							local gutter_hl

							if diff_hl == "DiffAdd" or diff_hl == "DiffviewDiffAdd" then
								gutter_hl = old_diff_side and "DiffviewGutterDelete" or "DiffviewGutterAdd"
							elseif diff_hl == "DiffDelete" or diff_hl == "DiffviewDiffDelete" then
								gutter_hl = "DiffviewGutterDelete"
							elseif
								diff_hl == "DiffChange"
								or diff_hl == "DiffText"
								or diff_hl == "DiffviewDiffChange"
							then
								gutter_hl = "DiffviewGutterChange"
							end

							if gutter_hl then
								vim.api.nvim_buf_set_extmark(bufnr, gutter_ns, row, 0, {
									sign_text = "▎",
									sign_hl_group = gutter_hl,
									priority = 300,
								})
								placed[row] = true
							end
						end
					end
				end
			end
			pcall(vim.api.nvim_set_current_win, current_win)
		end

		local function refresh_diffview_word_changes(bufnr)
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			vim.api.nvim_buf_clear_namespace(bufnr, word_change_ns, 0, -1)

			local current_win = vim.api.nvim_get_current_win()
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
					pcall(vim.api.nvim_set_current_win, winid)
					local word_hl = is_old_diff_side(winid) and "DiffviewWordDelete" or "DiffviewWordChange"

					for row = 0, vim.api.nvim_buf_line_count(bufnr) - 1 do
						local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
						local content_len = #(line:match("%S.*%S") or line:match("%S") or "")
						if content_len > 0 then
							local spans = {}
							local span_start = nil
							local changed_cols = 0

							for col = 1, #line + 1 do
								local diff_hl_id = vim.fn.diff_hlID(row + 1, col)
								local diff_hl = diff_hl_id > 0 and vim.fn.synIDattr(diff_hl_id, "name") or ""
								local is_changed_word = diff_hl == "DiffText" or diff_hl == "DiffviewDiffText"

								if is_changed_word and not span_start then
									span_start = col - 1
								elseif not is_changed_word and span_start then
									local span_end = col - 1
									changed_cols = changed_cols + span_end - span_start
									table.insert(spans, { span_start, span_end })
									span_start = nil
								end
							end

							-- If almost the whole line changed, keep it transparent; only partial edits get yellow.
							if changed_cols > 0 and changed_cols < content_len * 0.75 then
								for _, span in ipairs(spans) do
									vim.api.nvim_buf_set_extmark(bufnr, word_change_ns, row, span[1], {
										end_col = span[2],
										hl_group = word_hl,
										priority = 400,
									})
								end
							end
						end
					end
				end
			end
			pcall(vim.api.nvim_set_current_win, current_win)
		end

		local function configure_diffview_gutter_window(winid)
			vim.api.nvim_set_option_value("signcolumn", "yes:1", { win = winid })
			vim.api.nvim_set_option_value("statuscolumn", "%=%l %s", { win = winid })
		end

		local function refresh_visible_diffview_gutters()
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(winid) and vim.wo[winid].diff then
					configure_diffview_gutter_window(winid)
					local bufnr = vim.api.nvim_win_get_buf(winid)
					refresh_diffview_gutters(bufnr)
					refresh_diffview_word_changes(bufnr)
				end
			end
		end

		require("diffview").setup({
			diff_binaries = false, -- Show diffs for binaries
			enhanced_diff_hl = false, -- Disabled: adds per-line extra highlight pass; treesitter is stopped in diff_buf_read anyway
			git_cmd = { "git" },
			hg_cmd = { "hg" },
			use_icons = true, -- File icons in file panel
			show_help_hints = true, -- Show hint popups in file panel
			watch_index = true, -- Update views on index changes
			diffopt = { algorithm = "histogram", linematch = 60 }, -- Cleaner hunk boundaries and intra-line pairing
			persist_selections = { enabled = true }, -- Keep reviewed-file marks across reopen/restart

			-- Signs in file panel
			signs = {
				fold_closed = "▸",
				fold_open = "▾",
				done = "✓",
				selected_file = "●",
				unselected_file = "○",
				selected_dir = "●",
				partially_selected_dir = "◐",
				unselected_dir = "○",
			},

			status_icons = {
				A = "+",
				["?"] = "?",
				M = "~",
				R = "→",
				C = "=",
				T = "T",
				U = "!",
				X = "X",
				D = "-",
				B = "B",
				["!"] = "!",
			},

			-- File panel configuration
			file_panel = {
				listing_style = "tree", -- tree or list
				tree_options = {
					flatten_dirs = true, -- Flatten single-child directories
					folder_statuses = "only_folded", -- show_folded, never_folded, only_folded
					folder_count_style = "grouped",
					folder_trailing_slash = true,
				},
				list_options = {
					path_style = "basename",
				},
				win_config = {
					position = "left",
					width = "auto",
					win_opts = {},
				},
				show_branch_name = true,
				mark_placement = "sign_column",
			},

			-- File history panel configuration
			file_history_panel = {
				stat_style = "both",
				date_format = "relative",
				commit_format = { "hash", "subject", "author", "date", "ref", "status", "files", "stats" },
				log_options = {
					git = {
						single_file = {
							-- Combined merge diffs can omit raw file entries for some commits,
							-- which makes DiffView skip them in per-file history.
							diff_merges = "first-parent",
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
				show = true,
				commit_subject_max_length = 72,
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
					{ "n", "g0", jump_to_first_change, { desc = "First change" } },
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
					{ "n", "q", close_diffview_restore, { desc = "Close Diffview" } },

					-- Conflict resolution (single hunk)
					{ "n", "co", actions.conflict_choose("ours"), { desc = "Choose OURS" } },
					{ "n", "ct", actions.conflict_choose("theirs"), { desc = "Choose THEIRS" } },
					{ "n", "cb", actions.conflict_choose("base"), { desc = "Choose BASE" } },
					{ "n", "ca", actions.conflict_choose("all"), { desc = "Choose ALL" } },
					{ "n", "dx", actions.conflict_choose("none"), { desc = "Delete conflict region" } },

					-- Conflict resolution (whole file)
					{ "n", "<leader>cO", actions.conflict_choose_all("ours"), { desc = "Choose OURS (whole file)" } },
					{
						"n",
						"<leader>cT",
						actions.conflict_choose_all("theirs"),
						{ desc = "Choose THEIRS (whole file)" },
					},
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
					{ "n", "q", close_diffview_restore, { desc = "Close Diffview" } },

					-- Tree options
					{ "n", "i", actions.listing_style, { desc = "Toggle listing style" } },
					{ "n", "f", actions.toggle_flatten_dirs, { desc = "Toggle flatten dirs" } },

					-- Go to file
					{ "n", "gf", actions.goto_file_edit, { desc = "Go to file" } },
					{ "n", "<C-w><C-f>", actions.goto_file_split, { desc = "Go to file (split)" } },
					{ "n", "<C-w>gf", actions.goto_file_tab, { desc = "Go to file (tab)" } },

					-- Conflict resolution (whole file)
					{ "n", "<leader>cO", actions.conflict_choose_all("ours"), { desc = "Choose OURS (whole file)" } },
					{
						"n",
						"<leader>cT",
						actions.conflict_choose_all("theirs"),
						{ desc = "Choose THEIRS (whole file)" },
					},
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
					{ "n", "q", close_diffview_restore, { desc = "Close Diffview" } },
				},
				option_panel = {
					{ "n", "<tab>", actions.select_entry, { desc = "Select option" } },
					{ "n", "q", actions.close, { desc = "Close panel" } },
				},
			},

			-- View configuration
			view = {
				foldlevel = 99, -- Preserve the existing "mostly expanded" diff experience on the newer fork.
				-- Available layouts:
				-- 'diff1_plain' - Simple diff with no file panel
				-- 'diff1_inline' - Unified inline diff in a single window
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
					pin_local = false,
				},
				cycle_layouts = {
					default = { "diff2_horizontal", "diff2_vertical", "diff1_inline" },
					merge_tool = { "diff3_horizontal", "diff3_vertical", "diff3_mixed", "diff4_mixed", "diff1_plain" },
				},
				inline = {
					style = "unified",
					deletion_highlight = "hanging",
					deletion_treesitter = true,
				},
			},

			-- Lifecycle and buffer hooks
			hooks = {
				-- Called when diffview is opened
				view_opened = function(view)
					diffview_return_target = diffview_return_target or return_target.last()
					return_target.suspend()
					vim.notify("Diffview opened", vim.log.levels.DEBUG)
					vim.defer_fn(refresh_visible_diffview_gutters, 100)
					vim.defer_fn(refresh_visible_diffview_gutters, 400)
					-- Disable incline globally while DiffView is open.
					-- The filetype-based exclusion (DiffviewFiles/DiffviewFileHistory)
					-- only catches the file panel, not the actual diff buffer views
					-- which have no special filetype. incline's render() fires on
					-- every redraw (every scroll frame), so this is critical for perf.
					pcall(function()
						require("incline").disable()
					end)
					-- Track which repo root this Diffview is showing (for repo-following).
					-- Read directly from Diffview's adapter context — this correctly
					-- reflects the -C<path> flag used by retarget_diffview, without
					-- needing a module-level override variable.
					local toplevel = view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel
					if toplevel then
						diffview_current_root = vim.fn.resolve(toplevel):gsub("/$", "")
					else
						-- Fallback for non-git adapters (hg) or unexpected states.
						-- getcwd(0, 0) = current window in current tab, respects :lcd/:tcd.
						local root = find_repo_root(vim.fn.getcwd(0, 0))
						diffview_current_root = root and vim.fn.resolve(root):gsub("/$", "") or nil
					end
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
								if err then
									return
								end
								if not diffview_auto_switch_enabled() then
									return
								end
								vim.schedule(function()
									-- Debounce to avoid excessive refreshes
									if debounce_timer then
										debounce_timer:stop()
									end
									debounce_timer = vim.defer_fn(function()
										debounce_timer = nil
										if not diffview_auto_switch_enabled() then
											return
										end
										if reopening then
											return
										end

										-- Check if conflict state changed
										local is_merging = check_conflict_state(git_path) ~= nil
										if is_merging ~= view._was_merging then
											view._was_merging = is_merging
											-- Reopen Diffview to switch between normal and merge conflict view
											-- Stop watcher first to avoid callback-during-close issues
											reopening = true
											handle:stop()
											view._git_watcher = nil
											diffview_internal_reopen("DiffviewOpen")
											vim.defer_fn(function()
												reopening = false
											end, 120)
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
							main_handle:start(
								main_info.main_git_dir,
								{ recursive = true },
								function(err, filename, events)
									if err then
										vim.schedule(function()
											vim.notify(
												"Cross-worktree watcher error: " .. tostring(err),
												vim.log.levels.ERROR
											)
										end)
										return
									end
									if not diffview_auto_switch_enabled() then
										return
									end
									vim.schedule(function()
										vim.notify(
											"Cross-worktree fs_event: " .. tostring(filename),
											vim.log.levels.DEBUG
										)
									end)
									vim.schedule(function()
										if main_debounce_timer then
											main_debounce_timer:stop()
										end
										main_debounce_timer = vim.defer_fn(function()
											main_debounce_timer = nil
											if not diffview_auto_switch_enabled() then
												return
											end
											if main_reopening then
												return
											end

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
											diffview_internal_reopen(
												"DiffviewOpen -C" .. vim.fn.fnameescape(main_info.main_work_dir)
											)
												vim.defer_fn(function()
													main_reopening = false
												end, 120)
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
												diffview_internal_reopen("DiffviewOpen")
												vim.defer_fn(function()
													main_reopening = false
												end, 120)
											end
										end, 300)
									end)
								end
							)
							view._main_repo_watcher = main_handle
						end
					end

					-- Start timer polling for tmux pane cwd changes (2s interval).
					-- Also expose Neovim socket to tmux so Fish hook can find us.
					-- Design constraint: one Diffview-owning Neovim per tmux session.
					-- NVIM_DIFFVIEW_SOCKET is session-scoped; if two Neovims open
					-- Diffview in the same session, the last one wins (last-writer-wins).
					-- Per-pane namespacing would break the Fish hook (it wouldn't know
					-- which pane has Neovim). This is acceptable: the user interacts
					-- with one Diffview at a time.
					start_follow_timer()
					if vim.env.TMUX then
						-- Ensure Neovim has a server socket for RPC discovery.
						if vim.v.servername == "" then
							vim.fn.serverstart()
						end
						vim.fn.system(
							"tmux set-environment NVIM_DIFFVIEW_SOCKET " .. vim.fn.shellescape(vim.v.servername)
						)
					end
				end,
				-- Called when diffview is closed
				view_closed = function(view)
					vim.notify("Diffview closed", vim.log.levels.DEBUG)
					-- Re-enable incline (disabled in view_opened for scroll perf)
					pcall(function()
						require("incline").enable()
					end)
					diffview_current_root = nil
					-- Stop follow timer (ref-counted: only stops on last view close).
					-- Only remove tmux socket when no views remain.
					stop_follow_timer()
					if vim.env.TMUX and follow_timer_refs == 0 then
						vim.fn.system("tmux set-environment -u NVIM_DIFFVIEW_SOCKET 2>/dev/null")
					end
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

					-- Restore treesitter/diagnostics/gitsigns/window-opts on persisting buffers
					-- (diffview:// buffers are wiped by now; only real files persist)
					vim.schedule(function()
						for bufnr, prior in pairs(diffview_modified_bufs) do
							if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
								-- Re-enable treesitter highlighting
								if vim.treesitter.start then
									pcall(vim.treesitter.start, bufnr)
								end
								-- Re-enable diagnostics
								pcall(vim.diagnostic.enable, true, { bufnr = bufnr })
								-- Restore blink.pairs and indent guide to exact prior state
								vim.b[bufnr].blink_pairs = prior.blink_pairs
								vim.b[bufnr].indent_guide = prior.indent_guide
								-- Restore inlay hints only if they were enabled before
								if vim.lsp.inlay_hint and prior.inlay_hints then
									pcall(vim.lsp.inlay_hint.enable, true, { bufnr = bufnr })
								end
								-- Re-attach symbol-usage only if it was active before
								if prior.symbol_usage and package.loaded["symbol-usage"] then
									pcall(function()
										require("symbol-usage.buf").attach_buffer(bufnr)
									end)
								end
								-- Re-attach gitsigns
								if package.loaded.gitsigns then
									pcall(require("gitsigns").attach, bufnr)
								end
								-- Restore window options in any window showing this buffer
								for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
									pcall(function()
										vim.wo[win].cursorline = vim.o.cursorline
										vim.wo[win].signcolumn = vim.o.signcolumn
										vim.wo[win].foldcolumn = vim.o.foldcolumn
										vim.wo[win].statuscolumn = vim.o.statuscolumn
									end)
								end
							end
						end
							diffview_modified_bufs = {}
					end)

					if not diffview_suppress_restore and not commit_cycle_state.is_cycling then
						vim.schedule(function()
							return_target.restore(diffview_return_target)
							diffview_return_target = nil
							return_target.resume()
						end)
					end
				end,
				diff_buf_read = function(bufnr)
					-- Track this buffer with prior state for exact restoration
					local prior = {}
					-- Capture buffer-local toggle state (nil = "use global default")
					prior.blink_pairs = vim.b[bufnr].blink_pairs
					prior.indent_guide = vim.b[bufnr].indent_guide
					-- Capture inlay hint state before disabling
					if vim.lsp.inlay_hint then
						prior.inlay_hints = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
					end
					-- Capture symbol-usage state before clearing
					if package.loaded["symbol-usage"] then
						local su_state = require("symbol-usage.state")
						prior.symbol_usage = next(su_state.get_buf_workers(bufnr)) ~= nil
					end
					diffview_modified_bufs[bufnr] = prior

					-- Set local options for diff buffers
					vim.opt_local.wrap = false
					vim.opt_local.list = false
					vim.opt_local.colorcolumn = ""

					-- Reduce redraw cost: disable expensive per-line rendering
					vim.wo.cursorline = false
					vim.wo.relativenumber = false
					vim.wo.signcolumn = "yes:1"
					vim.wo.foldcolumn = "0"
					vim.wo.foldmethod = "manual"
					-- Draw Diffview-only signs after the line number, matching the reference layout.
					vim.wo.statuscolumn = "%=%l %s"

					-- Disable blink.pairs matchparen per-buffer (re-evaluates on every CursorMoved)
					vim.b[bufnr].blink_pairs = false

					-- Disable blink.indent scope guides per-buffer
					-- (blocked filetypes only cover DiffviewFiles panel, not diff panes)
					vim.b[bufnr].indent_guide = false

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
								vim.notify(
									"treesitter stop failed (buf " .. bufnr .. "): " .. tostring(err),
									vim.log.levels.DEBUG
								)
							end
						end
					end, 50)

					-- Disable diagnostics per-buffer (more reliable than view config alone)
					local ok, err = pcall(vim.diagnostic.enable, false, { bufnr = bufnr })
					if not ok then
						vim.notify(
							"diagnostic disable failed (buf " .. bufnr .. "): " .. tostring(err),
							vim.log.levels.DEBUG
						)
					end

					-- Disable inlay hints (extmarks redrawn every scroll frame)
					if vim.lsp.inlay_hint then
						pcall(vim.lsp.inlay_hint.enable, false, { bufnr = bufnr })
					end

					-- Detach symbol-usage extmarks (reference/implementation counts)
					if package.loaded["symbol-usage"] then
						pcall(function()
							require("symbol-usage.buf").clear_buffer(bufnr)
						end)
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
								vim.notify(
									"LSP detach failed (terraformls, buf " .. bufnr .. "): " .. tostring(err),
									vim.log.levels.DEBUG
								)
							end
						end
					end, 100)

					-- Ensure q closes diffview in ALL diff buffers (including index)
					vim.keymap.set("n", "q", close_diffview_restore, {
						buffer = bufnr,
						desc = "Close Diffview",
					})

					vim.defer_fn(function()
						refresh_diffview_gutters(bufnr)
						refresh_diffview_word_changes(bufnr)
					end, 50)
					vim.defer_fn(function()
						refresh_diffview_gutters(bufnr)
						refresh_diffview_word_changes(bufnr)
					end, 250)
					vim.defer_fn(refresh_visible_diffview_gutters, 500)
				end,
			},
		})

		local ok_styling, styling = pcall(require, "config.autocmds.styling")
		if ok_styling then
			styling.apply_consistent_styles()
		end

		require("git.diffview_workflow").setup({ api = api })

		-- Shared conflict-state polling: checks local + cross-worktree git conflict files
		-- (MERGE_HEAD, REBASE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD)
		-- Returns true if a reopen was triggered (caller should return early)
		-- Respects vim.g.diffview_auto_switch toggle.
		local function poll_merge_state()
			if not diffview_auto_switch_enabled() then
				return false
			end
			local ok, lib = pcall(require, "diffview.lib")
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
				diffview_internal_reopen("DiffviewOpen")
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
					diffview_current_root = vim.fn.resolve((main_info.main_work_dir:gsub("/$", "")))
					diffview_internal_reopen(
						"DiffviewOpen -C" .. vim.fn.fnameescape(main_info.main_work_dir)
					)
					return true
				elseif not main_conflicting and cross_worktree_state.active then
					cross_worktree_state.active = false
					cross_worktree_state.original_cwd = nil
					cross_worktree_state.main_work_dir = nil
					cross_worktree_state.main_git_dir = nil
					local cwd_root = find_repo_root(vim.fn.getcwd())
					diffview_current_root = cwd_root and vim.fn.resolve(cwd_root) or nil
					diffview_internal_reopen("DiffviewOpen")
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
		local dv_focus_group = vim.api.nvim_create_augroup("diffview_focus_refresh", { clear = true })

		-- Poll with bounded retry: initial check + one-shot retry at 800ms.
		-- Covers FSEvents coalescing where the first fs_stat misses a slow write.
		local function poll_with_retry()
			if poll_merge_state() then
				return
			end
			-- Refresh files immediately for non-conflict git changes
			local ok, lib = pcall(require, "diffview.lib")
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

		-- Shared reentrancy guard for repo-following (used by FocusGained, BufEnter, TermLeave).
		local repo_switch_in_progress = false

		-- Shared retarget helper: close current Diffview, open for new_root.
		-- Cross-repo retargeting still needs reopen: diffview.api.set_revs()
		-- can switch revisions in-place, but not the adapter root/-C target.
		-- Handles failure recovery (reverts diffview_current_root on error).
		local function retarget_diffview(new_root)
			if repo_switch_in_progress then
				return
			end
			repo_switch_in_progress = true
			local prev_root = diffview_current_root
			diffview_current_root = new_root
			diffview_suppress_restore = true
			pcall(vim.cmd, "DiffviewClose")
			vim.defer_fn(function()
				local open_ok, err = pcall(vim.cmd, "DiffviewOpen -C" .. vim.fn.fnameescape(new_root))
				if not open_ok then
					diffview_current_root = prev_root
					vim.notify("Diffview retarget failed: " .. tostring(err), vim.log.levels.WARN)
				end
				diffview_suppress_restore = false
				repo_switch_in_progress = false
			end, 100)
		end

		-- Shared tmux pane check: query the last-active tmux pane's cwd,
		-- compare against the current Diffview's adapter root, and retarget
		-- if the pane is in a different repo. Multi-tab safe.
		-- Called by: FocusGained, timer polling, and RPC from Fish hook.
		-- Optional cwd parameter: when provided (e.g. from Fish hook RPC),
		-- skips tmux pane query. Falls back to tmux {last} pane otherwise.
		check_tmux_pane_and_retarget = function(cwd)
			if vim.g.diffview_follow_repo == false then
				return
			end
			if repo_switch_in_progress then
				return
			end
			local ok, lib = pcall(require, "diffview.lib")
			if not ok then
				return
			end
			local current_view = lib.get_current_view()
			if not current_view then
				return
			end
			local pane_cwd = cwd or get_tmux_last_pane_cwd()
			if not pane_cwd then
				return
			end
			pane_cwd = vim.fn.resolve(pane_cwd)
			-- Read root from the active view's adapter (multi-tab safe).
			local view_root = current_view.adapter and current_view.adapter.ctx and current_view.adapter.ctx.toplevel
			if view_root then
				view_root = vim.fn.resolve(view_root):gsub("/$", "")
			end
			if path_is_under(pane_cwd, view_root) then
				return
			end
			local pane_root = find_repo_root(pane_cwd)
			if not pane_root then
				return
			end
			pane_root = vim.fn.resolve(pane_root):gsub("/$", "")
			if not view_root or pane_root ~= view_root then
				retarget_diffview(pane_root)
			end
		end

		-- Timer-based polling: check tmux pane cwd periodically.
		-- Starts when Diffview opens, stops when ALL views close (ref-counted).
		-- Acts as a reliable fallback; Fish hook provides instant response.
		-- Uses get_tmux_active_pane_cwd_async() to avoid blocking Neovim's UI
		-- thread — critical when multiple worktrees each run Diffview, as all
		-- their timers hit tmux's single-threaded server simultaneously.
		-- Adaptive interval: 3s base, backs off to 5s after 5 idle ticks.
		local FOLLOW_TIMER_BASE_MS = 3000
		local FOLLOW_TIMER_IDLE_MS = 5000
		local follow_idle_ticks = 0
		local follow_async_in_flight = false

		start_follow_timer = function()
			follow_timer_refs = follow_timer_refs + 1
			if follow_timer then
				return
			end
			if not vim.env.TMUX then
				return
			end
			follow_idle_ticks = 0
			follow_timer = vim.fn.timer_start(
				FOLLOW_TIMER_BASE_MS,
				vim.schedule_wrap(function()
					-- Skip if RPC hook fired since last timer tick (it already
					-- provided authoritative cwd; timer would be redundant).
					if follow_rpc_seq > follow_timer_seen_seq then
						follow_timer_seen_seq = follow_rpc_seq
						follow_idle_ticks = 0
						return
					end
					-- Skip if previous async query still in flight (prevents pile-up)
					if follow_async_in_flight then
						return
					end
					follow_async_in_flight = true
					get_tmux_active_pane_cwd_async(function(cwd)
						follow_async_in_flight = false
						if cwd then
							follow_idle_ticks = 0
							check_tmux_pane_and_retarget(cwd)
						else
							follow_idle_ticks = follow_idle_ticks + 1
						end
						-- Adaptive interval: back off when idle to reduce tmux IPC pressure
						if follow_timer and follow_idle_ticks > 5 then
							vim.fn.timer_stop(follow_timer)
							follow_timer = vim.fn.timer_start(
								FOLLOW_TIMER_IDLE_MS,
								vim.schedule_wrap(function()
									-- Re-check with same logic; reset to base on activity
									if follow_rpc_seq > follow_timer_seen_seq then
										follow_timer_seen_seq = follow_rpc_seq
										follow_idle_ticks = 0
										return
									end
									if follow_async_in_flight then
										return
									end
									follow_async_in_flight = true
									get_tmux_active_pane_cwd_async(function(cwd2)
										follow_async_in_flight = false
										if cwd2 then
											follow_idle_ticks = 0
											-- Switch back to base interval on activity
											if follow_timer then
												vim.fn.timer_stop(follow_timer)
												start_follow_timer()
												-- Adjust ref count since start_follow_timer increments it
												follow_timer_refs = follow_timer_refs - 1
											end
											check_tmux_pane_and_retarget(cwd2)
										end
									end)
								end),
								{ ["repeat"] = -1 }
							)
						end
					end)
				end),
				{ ["repeat"] = -1 }
			)
		end

		stop_follow_timer = function()
			follow_timer_refs = math.max(0, follow_timer_refs - 1)
			if follow_timer_refs > 0 then
				return
			end
			if follow_timer then
				vim.fn.timer_stop(follow_timer)
				follow_timer = nil
			end
		end

		-- RPC endpoint for Fish hook: called via
		--   nvim --server $socket --remote-expr 'v:lua.diffview_check_pane("/path")'
		-- Accepts optional cwd from the caller (Fish hook passes $PWD directly,
		-- avoiding the {last} pane ambiguity when Neovim queries tmux itself).
		-- vim.schedule ensures we run in the main loop (safe from RPC context).
		-- Increments follow_rpc_seq so the timer defers to this authoritative data.
		_G.diffview_check_pane = function(cwd)
			follow_rpc_seq = follow_rpc_seq + 1
			vim.schedule(function()
				check_tmux_pane_and_retarget(cwd)
			end)
			return "ok"
		end

		-- VimLeave: clean up tmux socket var on exit (prevents stale sockets
		-- when Neovim crashes or is killed without closing Diffview first).
		vim.api.nvim_create_autocmd("VimLeave", {
			group = dv_focus_group,
			callback = function()
				if vim.env.TMUX then
					vim.fn.system("tmux set-environment -u NVIM_DIFFVIEW_SOCKET 2>/dev/null")
				end
				stop_follow_timer()
			end,
			desc = "Clean up Diffview follow state on Neovim exit",
		})

		-- FocusGained: conflict detection + tmux pane repo-following.
		-- When you switch back to the Neovim tmux pane from another pane,
		-- Neovim receives FocusGained. We query tmux for the last-active
		-- pane's cwd and retarget Diffview if it's in a different repo.
		-- PERF: Uses async tmux query to avoid blocking UI during focus gain.
		vim.api.nvim_create_autocmd("FocusGained", {
			group = dv_focus_group,
			callback = function()
				-- Conflict detection (existing)
				vim.defer_fn(poll_with_retry, 200)

				-- Tmux repo-following (async to avoid blocking on focus gain)
				if vim.g.diffview_follow_repo == false or repo_switch_in_progress then
					return
				end
				local ok, lib = pcall(require, "diffview.lib")
				if not ok or not lib.get_current_view() then
					return
				end
				get_tmux_last_pane_cwd_async(function(cwd)
					if cwd then
						check_tmux_pane_and_retarget(cwd)
					end
				end)
			end,
			desc = "Refresh Diffview on focus gain (conflict detection + async tmux repo following)",
		})

		-- TermClose: detect conflicts started from :terminal splits.
		-- Fires when the terminal job exits.
		vim.api.nvim_create_autocmd("TermClose", {
			group = dv_focus_group,
			callback = function()
				vim.defer_fn(poll_with_retry, 200)
			end,
			desc = "Refresh Diffview on TermClose (conflict detection)",
		})

		-- TermLeave: conflict detection + repo-following from terminal cwd.
		-- Fires on Ctrl-\ Ctrl-n (leaving terminal mode). At this point the
		-- current buffer is still the terminal, so vim.b.terminal_job_id is
		-- available. We query the shell process's actual cwd (via lsof on macOS
		-- or /proc on Linux) and retarget Diffview if it's in a different repo.
		vim.api.nvim_create_autocmd("TermLeave", {
			group = dv_focus_group,
			callback = function()
				-- Conflict detection (existing)
				vim.defer_fn(poll_with_retry, 200)

				-- Repo-following from terminal cwd
				if vim.g.diffview_follow_repo == false then
					return
				end
				if repo_switch_in_progress then
					return
				end
				local ok, lib = pcall(require, "diffview.lib")
				if not ok or not lib.get_current_view() then
					return
				end
				local term_cwd = get_terminal_cwd()
				if not term_cwd then
					vim.notify("repo-follow: terminal cwd not detected", vim.log.levels.DEBUG)
					return
				end
				term_cwd = vim.fn.resolve(term_cwd)
				-- Short-circuit if terminal cwd is under current root (path-separator-aware)
				if path_is_under(term_cwd, diffview_current_root) then
					return
				end
				local term_root = find_repo_root(term_cwd)
				if not term_root then
					vim.notify("repo-follow: no git repo at " .. term_cwd, vim.log.levels.DEBUG)
					return
				end
				term_root = vim.fn.resolve(term_root)
				if not diffview_current_root or term_root ~= diffview_current_root then
					vim.notify(
						"repo-follow: switching " .. (diffview_current_root or "nil") .. " → " .. term_root,
						vim.log.levels.DEBUG
					)
					retarget_diffview(term_root)
				end
			end,
			desc = "Refresh Diffview on TermLeave (conflict detection + repo following)",
		})

		-- WinEnter: catch-all for any window switch while Diffview is open.
		-- Subsumes BufEnter/BufWinEnter since WinEnter fires on all window
		-- transitions. Scoped: bails immediately if no Diffview view is open.
		local win_enter_timer = nil
		vim.api.nvim_create_autocmd("WinEnter", {
			group = dv_focus_group,
			callback = function()
				-- Only check if Diffview is currently open
				local ok, lib = pcall(require, "diffview.lib")
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
			desc = "Poll conflict state on window switch while Diffview is open",
		})

		-- BufEnter: repo-following — when the user switches to a buffer in a
		-- different git repo, retarget Diffview to show that repo's changes.
		-- Skips non-file buffers (buftype ~= ""), which covers help, quickfix,
		-- terminal, nofile, prompt, and plugin UIs (Telescope, oil, etc.).
		-- Uses vim.fn.resolve() for path canonicalization (handles stow symlinks).
		-- Short-circuits when the buffer path is under the current root.
		-- Debounced at 300ms to avoid thrashing during rapid buffer switches.
		local buf_enter_timer = nil
		vim.api.nvim_create_autocmd("BufEnter", {
			group = dv_focus_group,
			callback = function()
				if vim.g.diffview_follow_repo == false then
					return
				end
				if repo_switch_in_progress then
					return
				end

				-- Skip non-file buffers (terminal, help, quickfix, nofile, prompt, etc.)
				if vim.bo.buftype ~= "" then
					return
				end

				local ok, lib = pcall(require, "diffview.lib")
				if not ok or not lib.get_current_view() then
					return
				end

				local bufname = vim.api.nvim_buf_get_name(0)
				if bufname == "" or bufname:match("^%w+://") then
					return
				end

				-- Short-circuit: if buffer path is under current root, no repo change
				if diffview_current_root then
					local resolved_buf = vim.fn.resolve(bufname)
					if path_is_under(resolved_buf, diffview_current_root) then
						return
					end
				end

				if buf_enter_timer then
					return
				end
				buf_enter_timer = vim.defer_fn(function()
					buf_enter_timer = nil
					local buf_dir = vim.fn.resolve(vim.fn.fnamemodify(bufname, ":h"))
					local buf_root = find_repo_root(buf_dir)
					if not buf_root then
						return
					end
					buf_root = vim.fn.resolve(buf_root)
					if not diffview_current_root or buf_root ~= diffview_current_root then
						retarget_diffview(buf_root)
					end
				end, 300)
			end,
			desc = "Follow buffer repo: retarget Diffview when switching to a different repo",
		})
	end,
}

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
							vim.fn.system("git rev-parse --verify " .. branch .. " 2>/dev/null")
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
						{ "n", "<leader>e", actions.focus_files, { desc = "Focus file panel" } },
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
						{ "n", "<leader>e", actions.focus_files, { desc = "Focus file panel" } },
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
						disable_diagnostics = false,
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
						disable_diagnostics = false,
						winbar_info = true,
					},
				},

				-- Lifecycle and buffer hooks
				hooks = {
					-- Called when diffview is opened
					view_opened = function(view)
						vim.notify("Diffview opened", vim.log.levels.DEBUG)
					end,
					-- Called when diffview is closed
					view_closed = function(view)
						vim.notify("Diffview closed", vim.log.levels.DEBUG)
					end,
					diff_buf_read = function(bufnr)
						-- Set local options for diff buffers
						vim.opt_local.wrap = false
						vim.opt_local.list = false
						vim.opt_local.colorcolumn = { 80 }
						-- Ensure q closes diffview in ALL diff buffers (including index)
						vim.keymap.set("n", "q", "<cmd>DiffviewClose<cr>", {
							buffer = bufnr,
							desc = "Close Diffview",
						})
					end,
				},
			})
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

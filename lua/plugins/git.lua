-- Git integration for nvim-mini
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
}

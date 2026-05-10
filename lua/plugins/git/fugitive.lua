-- Fugitive for comprehensive Git integration

return {
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
				cnoreabbrev <expr> glg getcmdtype() == ':' && getcmdline() == 'glg' ? 'Git log --graph --oneline --decorate --all --date-order' : 'glg'

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
	}

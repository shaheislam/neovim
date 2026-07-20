return {
	{
		"tpope/vim-obsession",
		lazy = false,
		version = false,
		config = function()
			vim.opt.sessionoptions:append("curdir")

			local function project_session()
				local root = vim.fs.root(0, ".git")
				return root and (root .. "/Session.vim") or nil
			end

			vim.api.nvim_create_autocmd("VimEnter", {
				group = vim.api.nvim_create_augroup("project_session_tracking", { clear = true }),
				callback = function()
					if vim.g.this_obsession or #vim.api.nvim_list_uis() == 0 then
						return
					end

					local session = project_session()
					if session then
						vim.cmd("silent Obsess " .. vim.fn.fnameescape(session))
					end
				end,
			})

			vim.keymap.set("n", "<leader>so", function()
				if vim.g.this_obsession then
					vim.cmd("Obsess!")
					return
				end
				local session = project_session()
				if session then
					vim.cmd("Obsess " .. vim.fn.fnameescape(session))
				end
			end, { desc = "Toggle Project Session" })

			vim.keymap.set("n", "<leader>sX", function()
				if vim.g.this_obsession then
					vim.cmd("Obsess!")
					return
				end
				local session = project_session()
				if session then
					vim.fn.delete(session)
				end
			end, { desc = "Delete Project Session" })
		end,
	},
}

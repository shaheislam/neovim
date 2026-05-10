-- Flog for visual branch graph/history, bridged into Diffview for review

return {
	"rbong/vim-flog",
	cmd = { "Flog", "Flogsplit", "Floggit" },
	dependencies = {
		"tpope/vim-fugitive",
		"dlyongemallo/diffview.nvim",
	},
	keys = {
		{
			"<leader>gG",
			function()
				require("git.flog").open_graph()
			end,
			desc = "Git graph",
		},
		{
			"<leader>gV",
			function()
				require("git.flog").open_graph_split()
			end,
			desc = "Git graph split",
		},
		{
			"<leader>gY",
			function()
				require("git.flog").open_current_file_graph()
			end,
			desc = "Git graph current file",
		},
		{
			"<leader>gW",
			function()
				require("git.flog").open_current_file_graph_split()
			end,
			desc = "Git graph current file split",
		},
		{
			"<leader>gY",
			function()
				require("git.flog").open_selected_lines_graph()
			end,
			mode = "v",
			desc = "Git graph selected lines",
		},
	},
	init = function()
		vim.g.flog_permanent_default_opts = {
			all = true,
			date = "relative",
			order = "topo",
			max_count = 5000,
		}

		vim.api.nvim_create_user_command("GitGraph", function()
			require("git.flog").open_graph()
		end, { desc = "Open Git branch graph" })
		vim.api.nvim_create_user_command("GitGraphCurrentFile", function()
			require("git.flog").open_current_file_graph()
		end, { desc = "Open Git branch graph for current file" })
		vim.api.nvim_create_user_command("GitGraphCurrentFileSplit", function()
			require("git.flog").open_current_file_graph_split()
		end, { desc = "Open Git branch graph split for current file" })
	end,
	config = function()
		require("git.flog").setup()
	end,
}

-- Review-only pilot for changes made by the existing OpenCode workflow.

return {
	{
		"olimorris/codecompanion.nvim",
		version = false,
		cmd = { "CodeCompanionCodeReview" },
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			interactions = {
				opts = {
					watcher = { enabled = false },
				},
				code_review = {
					enabled = true,
					keymaps = {
						accept = {
							modes = { n = "a" },
							callback = function()
								require("git.codecompanion_review").resync_after("accept")
							end,
							description = "Accept the hunk under the cursor",
						},
						comment = {
							modes = { n = "c" },
							callback = function()
								require("git.codecompanion_review").run("comment")
							end,
							description = "Comment on the hunk under the cursor",
						},
						diff = {
							modes = { n = "d" },
							callback = function()
								require("git.codecompanion_review").run("open_diff")
							end,
							description = "Diff the hunk under the cursor against the baseline",
						},
						ignore = {
							modes = { n = "x" },
							callback = function()
								require("git.codecompanion_review").resync_after("ignore")
							end,
							description = "Ignore the hunk's file until the baseline advances",
						},
					},
					display = {
						diff = {
							provider = function(target)
								require("git.codecompanion_review").provider(target)
							end,
						},
					},
				},
			},
		},
	},
}

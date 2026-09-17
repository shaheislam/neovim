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
					display = {
						-- Keep the pilot isolated; the same baseline can be opened manually in Diffview.
						diff = { provider = "native" },
					},
				},
			},
		},
	},
}

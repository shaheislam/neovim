return {
	"hat0uma/csvview.nvim",
	ft = { "csv", "tsv" },
	cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
	opts = {
		parser = {
			comments = { "#", "//" },
		},
		view = {
			display_mode = "border",
		},
	},
	config = function(_, opts)
		require("csvview").setup(opts)

		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("nvim_mini_csvview", { clear = true }),
			pattern = { "csv", "tsv" },
			callback = function(event)
				vim.api.nvim_buf_call(event.buf, function()
					vim.cmd("silent! CsvViewEnable")
				end)
			end,
		})

		if vim.tbl_contains({ "csv", "tsv" }, vim.bo.filetype) then
			vim.cmd("silent! CsvViewEnable")
		end
	end,
}

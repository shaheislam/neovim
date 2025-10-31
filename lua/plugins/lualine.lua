-- Lualine statusbar - Replicates LazyVim's configuration without LazyVim dependency
-- Provides a beautiful and informative statusline matching production neovim

return {
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
			"lewis6991/gitsigns.nvim",
		},
		config = function()
			require("lualine").setup({
				options = {
					theme = "auto",
					globalstatus = true,
					disabled_filetypes = {
						statusline = { "dashboard", "alpha", "starter", "snacks_dashboard" },
					},
					component_separators = { left = "", right = "" },
					section_separators = { left = "", right = "" },
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch" },
					lualine_c = {
						{
							function()
								local cwd = vim.fn.getcwd()
								local name = vim.fn.fnamemodify(cwd, ":t")
								return "󱉭  " .. name
							end,
						},
						{
							"diagnostics",
							symbols = {
								error = " ",
								warn = " ",
								hint = " ",
								info = " ",
							},
						},
						{ "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
						{
							function()
								-- Handle Oil buffers specially
								if vim.bo.filetype == "oil" then
									local ok, oil = pcall(require, "oil")
									if ok then
										local oil_dir = oil.get_current_dir()
										if oil_dir then
											return "oil://" .. oil_dir
										end
									end
								end

								local path = vim.fn.expand("%:p")
								if path == "" then
									return ""
								end

								-- Get current working directory
								local cwd = vim.fn.getcwd()

								-- Try to make path relative to cwd
								if path:find(cwd, 1, true) == 1 then
									path = path:sub(#cwd + 2)
								end

								-- Add modified and readonly indicators
								local modified_sign = ""
								local readonly_sign = ""

								if vim.bo.modified then
									modified_sign = " "
								end
								if vim.bo.readonly then
									readonly_sign = " 󰌾"
								end

								return path .. modified_sign .. readonly_sign
							end,
						},
					},
					lualine_x = {
						{
							function()
								if os.getenv("IN_NIX_SHELL") then
									local name = os.getenv("name") or "nix"
									return "❄️  " .. name
								elseif vim.fn.filereadable("flake.nix") == 1 then
									return "❄️  (flake)"
								end
								return ""
							end,
							cond = function()
								return os.getenv("IN_NIX_SHELL") ~= nil or vim.fn.filereadable("flake.nix") == 1
							end,
						},
						{
							"diff",
							symbols = {
								added = " ",
								modified = " ",
								removed = " ",
							},
							source = function()
								local gitsigns = vim.b.gitsigns_status_dict
								if gitsigns then
									return {
										added = gitsigns.added,
										modified = gitsigns.changed,
										removed = gitsigns.removed,
									}
								end
							end,
						},
					},
					lualine_y = {
						{ "progress", separator = " ", padding = { left = 1, right = 0 } },
						{ "location", padding = { left = 0, right = 1 } },
					},
					lualine_z = {
						{
							function()
								return " " .. os.date("%R")
							end,
						},
					},
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { "filename" },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				extensions = { "lazy", "quickfix" },
			})
		end,
	},
}

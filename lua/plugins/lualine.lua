-- Lualine statusbar
-- Provides a beautiful and informative statusline
return {
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = function()
			return {
				options = {
					theme = "auto", -- Auto-detect from colorscheme
					globalstatus = true, -- Single statusline for all windows
					disabled_filetypes = {
						statusline = { "dashboard", "alpha", "starter" },
					},
					component_separators = { left = "", right = "" },
					section_separators = { left = "", right = "" },
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch" },
					lualine_c = {
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
						{ "filename", path = 1, symbols = { modified = "  ", readonly = "", unnamed = "" } },
					},
					lualine_x = {
						-- Nix environment indicator (matches production neovim)
						function()
							if os.getenv("IN_NIX_SHELL") then
								local name = os.getenv("name") or "nix"
								return "❄️  " .. name
							elseif vim.fn.filereadable("flake.nix") == 1 then
								return "❄️  (flake)"
							end
							return ""
						end,
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
						function()
							return " " .. os.date("%R")
						end,
					},
				},
				extensions = { "lazy", "quickfix", "oil" },
			}
		end,
	},
}

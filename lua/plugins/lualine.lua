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
			-- Cache aerial status to avoid pcall(require) + symbol lookup on every refresh
			local aerial_cache = { text = "", tick = 0 }
			local function cached_aerial()
				local tick = vim.b.changedtick or 0
				if tick ~= aerial_cache.tick then
					aerial_cache.tick = tick
					local ok, aerial = pcall(require, "aerial")
					if ok then
						local symbols = aerial.get_location(true)
						if symbols and #symbols > 0 then
							local parts = {}
							for i, s in ipairs(symbols) do
								if i > 5 then break end
								parts[#parts + 1] = (s.icon or "") .. " " .. s.name
							end
							aerial_cache.text = table.concat(parts, " ")
						else
							aerial_cache.text = ""
						end
					else
						aerial_cache.text = ""
					end
				end
				return aerial_cache.text
			end

			local stl_escape = require("lualine.utils.utils").stl_escape
			local function buffer_label()
				if vim.bo.buftype == "terminal" then
					local id = vim.b.toggle_number
					if id then
						local ok, toggleterm = pcall(require, "toggleterm.terminal")
						if ok and type(toggleterm.get) == "function" then
							local found, term = pcall(toggleterm.get, id, true)
							if found and term and type(term.display_name) == "string" and term.display_name ~= "" then
								return stl_escape(term.display_name)
							end
						end
					end
					return "Terminal"
				end

				-- Handle Oil buffers specially
				if vim.bo.filetype == "oil" then
					local ok, oil = pcall(require, "oil")
					if ok then
						local oil_dir = oil.get_current_dir()
						if oil_dir then
							local home = os.getenv("HOME")
							if home and oil_dir:find(home, 1, true) == 1 then
								oil_dir = oil_dir:sub(#home + 2)
							end
							return stl_escape(oil_dir)
						end
					end
				end

				local path = vim.fn.expand("%:p")
				if path == "" then
					return ""
				end

				local cwd = vim.fn.getcwd()
				if path:find(cwd, 1, true) == 1 then
					path = path:sub(#cwd + 2)
				end

				local modified_sign = vim.bo.modified and " " or ""
				local readonly_sign = vim.bo.readonly and " 󰌾" or ""
				return stl_escape(path .. modified_sign .. readonly_sign)
			end

			require("lualine").setup({
				options = {
					theme = "auto",
					globalstatus = true,
					disabled_filetypes = {
						statusline = { "dashboard", "alpha", "starter", "snacks_dashboard" },
						winbar = {},
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
						{ buffer_label },
						-- Aerial breadcrumb (cached — only recalculates on buffer change tick, not every CursorMoved)
						{
							cached_aerial,
							cond = function() return aerial_cache.text ~= "" end,
						},
					},
					lualine_x = {
						{
							function()
								local clients = vim.lsp.get_clients({ bufnr = 0 })
								if #clients == 0 then
									return ""
								end

								local names = {}
								for _, client in ipairs(clients) do
									names[#names + 1] = client.name
								end

								return "LSP " .. table.concat(names, ",")
							end,
						},
						{
							function()
								local status = vim.g.opencode_status
								if status == "busy" then
									return "󰚩 "
								elseif status == "idle" or status == "connected" then
									return "󰚩"
								end
								return ""
							end,
							cond = function() return vim.g.opencode_status ~= nil end,
							color = function()
								if vim.g.opencode_status == "busy" then
									return { fg = "#ff9e64" }
								end
								return { fg = "#9ece6a" }
							end,
						},
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
					lualine_z = {},
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { { buffer_label } },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				extensions = { "lazy", "quickfix" },
				-- Throttle statusline refresh to reduce per-scroll-frame overhead
				-- Default is 100ms; 250ms still feels responsive but fires less during fast scrolling
				refresh = {
					statusline = 250,
					tabline = 1000,
					winbar = 1000,
				},
			})
		end,
	},
}

-- Which-key for keybinding hints
-- Provides a popup with available keybindings
return {
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "modern",
			delay = 300, -- Show after 300ms of inactivity
			plugins = {
				marks = true, -- shows a list of your marks on ' and `
				registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
				spelling = {
					enabled = true, -- enabling this will show WhichKey when pressing z= to select spelling suggestions
					suggestions = 20, -- how many suggestions should be shown in the list?
				},
				presets = {
					operators = true, -- adds help for operators like d, y, ...
					motions = true, -- adds help for motions
					text_objects = true, -- help for text objects triggered after entering an operator
					windows = true, -- default bindings on <c-w>
					nav = true, -- misc bindings to work with windows
					z = true, -- bindings for folds, spelling and others prefixed with z
					g = true, -- bindings for prefixed with g
				},
			},
			win = {
				border = "rounded",
				padding = { 1, 2 }, -- extra window padding [top/bottom, right/left]
			},
			layout = {
				height = { min = 4, max = 25 }, -- min and max height of the columns
				width = { min = 20, max = 0.9 }, -- min and max width - 0.9 = 90% of screen width
				spacing = 3, -- spacing between columns
				align = "left", -- align columns left, center or right
			},
			show_help = true, -- show help message on the command line when the popup is visible
			show_keys = true, -- show the currently pressed key and its label as a message in the command line
		},
		config = function(_, opts)
			local wk = require("which-key")
			wk.setup(opts)

			-- Define key groups (leader key mappings)
			wk.add({
				-- Core groups
				{ "<leader>c", group = "code/lsp" },
				{ "<leader>f", group = "find/file" },
				{ "<leader>g", group = "git" },
				{ "<leader>h", group = "git hunks" },
				{ "<leader>q", group = "quickfix/quit" },
				{ "<leader>s", group = "session" },
				{ "<leader>w", group = "window/viewport" },
				{ "<leader>e", desc = "Open File Browser" },
				{ "<leader>m", group = "markdown" },

				-- Code/LSP operations
				{ "<leader>ca", desc = "Code Action" },
				{ "<leader>cd", desc = "Buffer Diagnostics" },
				{ "<leader>cD", desc = "Workspace Diagnostics" },
				{ "<leader>cl", desc = "Run Code Lens" },
				{ "<leader>cL", desc = "Refresh Code Lens" },
				{ "<leader>cr", desc = "Rename" },
				{ "<leader>cs", desc = "Show LSP status" },
				{ "<leader>ct", desc = "Toggle buffer's LSP" },
				{ "<leader>cT", desc = "Toggle ALL LSPs" },

				-- Session management
				{ "<leader>sl", desc = "List Sessions" },
				{ "<leader>sn", desc = "New Session" },
				{ "<leader>su", desc = "Update Session" },
				{ "<leader>sd", desc = "Delete Session" },

				-- Quickfix specific
				{ "<leader>qq", desc = "Toggle Quickfix" },
				{ "<leader>ql", desc = "Toggle Loclist" },

				-- File operations
				{ "<leader>ff", desc = "Find Files" },
				{ "<leader>fg", desc = "Live Grep" },
				{ "<leader>fb", desc = "Find Buffers" },
				{ "<leader>fr", desc = "Recent Files" },
				{ "<leader>fe", desc = "Open File Browser" },
				{ "<leader>ft", desc = "Terminal Split" },

				-- Markdown operations
				{ "<leader>mp", desc = "Toggle Markdown Preview" },

				-- Git operations (if you add more git plugins later)
				{ "<leader>gg", desc = "Git Status" },
				{ "<leader>gb", desc = "Git Branches" },
				{ "<leader>gc", desc = "Git Commit (create)" },
				{ "<leader>gd", desc = "Toggle Diffview" },
				{ "<leader>gl", desc = "Git Log" },
				{ "<leader>gf", desc = "Git Files" },
				{ "<leader>go", desc = "Open commit in DiffView" },
				{ "<leader>gK", desc = "Compare clipboard" },

				-- Window/viewport operations
				{ "<leader>wv", desc = "Viewport Resize Mode" },
				{ "<leader>wn", desc = "Viewport Navigate Mode" },
				{ "<leader>ws", desc = "Viewport Select Mode" },

				-- Gitsigns hunk operations (already defined in git.lua but good to have here too)
				{ "<leader>hs", desc = "Stage hunk" },
				{ "<leader>hr", desc = "Reset hunk" },
				{ "<leader>hS", desc = "Stage buffer" },
				{ "<leader>hu", desc = "Undo stage hunk" },
				{ "<leader>hp", desc = "Preview hunk" },
				{ "<leader>hi", desc = "Preview hunk inline" },
				{ "<leader>hb", desc = "Blame line" },
				{ "<leader>hB", desc = "Toggle blame line" },
				{ "<leader>hd", desc = "Diff this" },
				{ "<leader>ht", desc = "Toggle deleted" },
				{ "<leader>hw", desc = "Toggle word diff" },
				{ "<leader>hL", desc = "Toggle line highlight" },

				-- Bracket mappings (navigation)
				{ "]q", desc = "Next quickfix item" },
				{ "[q", desc = "Previous quickfix item" },
				{ "]Q", desc = "Last quickfix item" },
				{ "[Q", desc = "First quickfix item" },
				{ "]c", desc = "Next Git hunk" },
				{ "[c", desc = "Previous Git hunk" },
				{ "]C", desc = "Last Git hunk" },
				{ "[C", desc = "First Git hunk" },

				-- Window management
				{ "<C-z>", desc = "Toggle Zoom Window" },

				-- Oil path yanking (C-y followed by l/s/g)
				{ "<C-y>", group = "yank path", mode = "n" },
			})
		end,
	},
}

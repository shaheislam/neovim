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
				-- Position as vertical panel on bottom right
				col = -1, -- -1 = right edge
				row = -1, -- -1 = bottom edge
				width = { min = 30, max = 50 }, -- narrow width for vertical layout
				height = { min = 1 }, -- fully dynamic height, fits content exactly
			},
			layout = {
				width = { min = 50 }, -- force single column by making min width = window width
				spacing = 2,
				align = "left",
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
				{ "<leader>a", group = "ai" },
				{ "<leader>aa", group = "agentic" },
				{ "<leader>ac", group = "codecompanion" },
				{ "<leader>ao", group = "opencode" },
				{ "<leader>c", group = "code" },
				{ "<leader>aw", desc = "Wrapped dashboard" },
				{ "<leader>l", group = "lsp" },
				{ "<leader>L", group = "lint/security" },
				{ "<leader>f", group = "find/file" },
				{ "<leader>g", group = "git" },
				{ "<leader>O", group = "Octo (GitHub)" },
				{ "<leader>h", group = "git hunks" },
				{ "<leader>q", group = "quickfix/quit" },
				{ "<leader>s", group = "session" },
				{ "<leader>w", group = "window/viewport" },
				{ "<leader>e", desc = "Open File Browser" },
				{ "<leader>m", group = "markdown" },
				{ "<leader>o", group = "obsidian" },
				{ "<leader>b", group = "buffers" },
				{ "<leader>k", group = "kubectl" },
				{ "<leader>t", group = "trim" },
				{ "<leader>go", group = "github/octo" },
				{ "<leader>R", group = "rust" },
				-- Obsidian subcommands
				{ "<leader>od", desc = "Today's note" },
				{ "<leader>oy", desc = "Yesterday's note" },
				{ "<leader>om", desc = "Tomorrow's note" },
				{ "<leader>oo", desc = "Quick switch" },
				{ "<leader>os", desc = "Search vault" },
				{ "<leader>ob", desc = "Backlinks" },
				{ "<leader>ol", desc = "Outgoing links" },
				{ "<leader>ok", desc = "Search tags" },
				{ "<leader>on", desc = "New note" },
				{ "<leader>ot", desc = "Insert template" },
				{ "<leader>oc", desc = "Toggle checkbox" },
				{ "<leader>oL", desc = "Create link", mode = "v" },
				{ "<leader>oN", desc = "Link to new note", mode = "v" },

				-- Code/LSP operations
				{ "<leader>la", desc = "Code Action" },
				{ "<leader>ld", desc = "Buffer Diagnostics" },
				{ "<leader>lD", desc = "Workspace Diagnostics" },
				{ "<leader>lc", desc = "Run Code Lens" },
				{ "<leader>lC", desc = "Refresh Code Lens" },
				{ "<leader>lr", desc = "Rename" },
				{ "<leader>ls", desc = "Show LSP status" },
				{ "<leader>lt", desc = "Toggle buffer's LSP" },
				{ "<leader>lT", desc = "Toggle ALL LSPs" },
				{ "<leader>lh", desc = "Signature Help" },
				{ "<leader>li", desc = "Incoming Calls" },
				{ "<leader>lo", desc = "Outgoing Calls" },
				{ "<leader>lI", desc = "Incoming Calls Tree" },
				{ "<leader>lO", desc = "Outgoing Calls Tree" },

				-- Lint / security scanners
				{ "<leader>Ll", desc = "Run linters" },
				{ "<leader>Lk", desc = "Run kube-linter" },
				{ "<leader>LT", desc = "Run Trivy" },
				{ "<leader>LP", desc = "Run Conftest" },

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
				{ "]r", desc = "Next commit (file)" },
				{ "[r", desc = "Prev commit (file)" },
				{ "]R", desc = "Next commit (repo)" },
				{ "[R", desc = "Prev commit (repo)" },

				-- Window management
				{ "<C-z>", desc = "Toggle Zoom Window" },

				-- Yank operations
				{ "<leader>y", group = "yank/copy" },
				{ "<leader>yl", desc = "GitHub permalink" },
				{ "<leader>yL", desc = "GitHub permalink (markdown)" },
				{ "<leader>yr", desc = "Yank with relative path", mode = "v" },
				{ "<leader>ya", desc = "Yank with absolute path", mode = "v" },

				-- Oil path yanking (C-y followed by l/s/g)
				{ "<C-y>", group = "yank path", mode = "n" },

				-- Kubectl helpers
				{ "<leader>kf", desc = "kubectl cp from pod" },
				{ "<leader>kt", desc = "kubectl cp to pod" },
				{ "<leader>kp", desc = "kubectl cp picker" },
				{ "<leader>kl", desc = "kubectl list pods" },

				-- Buffer helpers
				{ "<leader>bd", desc = "Delete buffer" },
				{ "<leader>bD", desc = "Delete buffer (force)" },

				-- Trim helpers
				{ "<leader>tw", desc = "Trim trailing whitespace" },
				{ "<leader>tl", desc = "Trim last empty lines" },

				-- Rust tools
				{ "<leader>Ra", desc = "Rust code action" },
				{ "<leader>Rd", desc = "Rust debuggables" },
				{ "<leader>Rr", desc = "Rust runnables" },
				{ "<leader>RT", desc = "Rust testables" },
				{ "<leader>Re", desc = "Rust expand macro" },
				{ "<leader>Rc", desc = "Rust open Cargo" },
				{ "<leader>Rp", desc = "Rust parent module" },
				{ "<leader>Rj", desc = "Rust join lines" },
				{ "<leader>Rs", desc = "Rust SSR" },
				{ "<leader>Rg", desc = "Rust crate graph" },
				{ "<leader>RV", desc = "Crate versions" },
				{ "<leader>RF", desc = "Crate features" },
				{ "<leader>Rcd", desc = "Crate dependencies" },
				{ "<leader>Rcu", desc = "Update crate" },
				{ "<leader>Rcs", desc = "Update selected crates" },
				{ "<leader>Rca", desc = "Update all crates" },
				{ "<leader>RcU", desc = "Upgrade crate" },
				{ "<leader>RcS", desc = "Upgrade selected crates" },
				{ "<leader>RcA", desc = "Upgrade all crates" },
				{ "<leader>Rch", desc = "Crate homepage" },
				{ "<leader>Rcr", desc = "Crate repository" },
				{ "<leader>RcD", desc = "Crate documentation" },
				{ "<leader>RcC", desc = "Open crates.io" },
				{ "<leader>RcL", desc = "Open lib.rs" },
			})
		end,
	},
}

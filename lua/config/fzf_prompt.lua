local M = {}
local yank = require("config.fzf_yank")
local clean = yank.clean

local catalog = {
	{ name = "files", key = "<leader>ff", desc = "Find files", kind = "path" },
	{ name = "files_home", picker = "files", key = "<leader>fF", desc = "Find files from home", kind = "path", opts = function() return { cwd = vim.fn.expand("~") } end },
	{ name = "buffers", key = "<leader>fb", desc = "Find buffers", kind = "path" },
	{ name = "buffers_all", picker = "buffers", key = "<leader>fB", desc = "Find all buffers", kind = "path", opts = { show_all_buffers = true } },
	{ name = "oldfiles", key = "<leader>fr", desc = "Find recent files", kind = "path" },
	{ name = "oldfiles_global", picker = "oldfiles", key = "<leader>fR", desc = "Find recent files globally", kind = "path" },
	{ name = "live_grep", key = "<leader>fg", desc = "Find text", kind = "location" },
	{ name = "live_grep_no_tests", picker = "live_grep", key = "<leader>fG", desc = "Find text excluding tests", kind = "location", opts = { rg_opts = "--column --line-number --no-heading --color=always --smart-case --glob '!*test*' --glob '!*spec*' --glob '!*.min.*'" } },
	{ name = "grep_cword", key = "<leader>fw", desc = "Find word", kind = "location" },
	{ name = "grep_cWORD", key = "<leader>fW", desc = "Find WORD", kind = "location" },
	{ name = "changes", key = "<leader>fu", desc = "Find changes", kind = "display", yank = false },
	{ name = "marks", key = "<leader>fm", desc = "Find marks", kind = "display", yank = false },
	{ name = "help_tags", key = "<leader>fh", desc = "Find help", kind = "display", yank = false },
	{ name = "commands", key = "<leader>fc", desc = "Find commands", kind = "command" },
	{ name = "quickfix", key = "<leader>fq", desc = "Find quickfix entries", kind = "location" },
	{ name = "projects", key = "<leader>fp", desc = "Find projects", kind = "display", custom = true },
	{ name = "yank_history", key = "<leader>fy", desc = "Find yank history", kind = "display", custom = true },
	{ name = "zoxide", key = "<leader>cd", desc = "Find directories", kind = "zoxide" },
	{ name = "grep", desc = "Find text with query", kind = "location" },
	{ name = "tabs", desc = "Find tabs", kind = "location" },
	{ name = "lines", desc = "Find lines", kind = "location" },
	{ name = "blines", desc = "Find current buffer lines", kind = "location" },
	{ name = "tags", desc = "Find tags", kind = "location" },
	{ name = "btags", desc = "Find current buffer tags", kind = "location" },
	{ name = "jumps", desc = "Find jumps", kind = "display", yank = false },
	{ name = "registers", desc = "Find registers", kind = "register" },
	{ name = "keymaps", desc = "Find keymaps", kind = "display", yank = false },
	{ name = "command_history", desc = "Find command history", kind = "command" },
	{ name = "man_pages", desc = "Find manual pages", kind = "display", yank = false },
	{ name = "loclist", desc = "Find location list entries", kind = "location" },

	{ name = "git_status", key = "<leader>gg", desc = "Find Git status", kind = "git_status" },
	{ name = "git_commits", key = "<leader>gl", desc = "Find Git commits", kind = "commit" },
	{ name = "git_worktrees", desc = "Find Git worktrees", kind = "worktree" },
	{ name = "git_branches", key = "<leader>gb", desc = "Find Git branches", kind = "branch" },
	{ name = "git_files", key = "<leader>gf", desc = "Find Git files", kind = "path" },
	{ name = "git_bcommits", key = "<leader>gC", desc = "Find buffer commits", kind = "commit" },
	{ name = "git_stash", key = "<leader>gs", desc = "Find Git stashes", kind = "stash" },
	{ name = "git_conflicts", picker = "live_grep", key = "<leader>gx", desc = "Find Git conflicts", kind = "location", opts = { prompt = "Git Conflicts> ", search = "^(<<<<<<<|=======|>>>>>>>)" } },

	{ name = "diagnostics_document", key = "<leader>ld", desc = "Find buffer diagnostics", kind = "location" },
	{ name = "diagnostics_workspace", key = "<leader>lD", desc = "Find workspace diagnostics", kind = "location" },
	{ name = "lsp_document_symbols", key = "<leader>ss", desc = "Find document symbols", kind = "location" },
	{ name = "lsp_workspace_symbols", key = "<leader>sS", desc = "Find workspace symbols", kind = "location" },
	{ name = "lsp_incoming_calls", key = "<leader>li", desc = "Find incoming calls", kind = "location" },
	{ name = "lsp_references", desc = "Find references", kind = "location" },
	{ name = "lsp_definitions", desc = "Find definitions", kind = "location" },
	{ name = "lsp_declarations", desc = "Find declarations", kind = "location" },
	{ name = "lsp_typedefs", desc = "Find type definitions", kind = "location" },
	{ name = "lsp_implementations", desc = "Find implementations", kind = "location" },

	{ name = "dap_breakpoints", key = "<leader>fdb", desc = "Find DAP breakpoints", kind = "location", dap = true },
	{ name = "dap_variables", key = "<leader>fdv", desc = "Find DAP variables", kind = "display", dap = true },
	{
		name = "dap_frames",
		key = "<leader>fdf",
		desc = "Find DAP frames",
		kind = "display",
		dap = true,
		config = {
			preserve_whitespace = true,
			resolve = function(entry) return require("config.fzf_dap").frame_location(entry) end,
		},
	},

	{ name = "aws_accounts", key = "<leader>fa", desc = "Find AWS accounts", kind = "aws_account", custom = true },

	{ name = "opencode_messages", desc = "OpenCode messages", custom = true },
	{ name = "opencode_prompts", desc = "OpenCode prompts", custom = true },
	{ name = "opencode_assistant", desc = "OpenCode assistant output", custom = true },
	{ name = "opencode_reasoning", desc = "OpenCode reasoning", custom = true },
	{ name = "opencode_tools", desc = "OpenCode tool calls", custom = true },
	{ name = "opencode_tool_output", desc = "OpenCode tool output", custom = true },
	{ name = "opencode_sessions", desc = "OpenCode sessions", custom = true },
	{ name = "opencode_all_sessions", desc = "OpenCode all sessions", custom = true },
}

local by_name = {}
for _, item in ipairs(catalog) do
	by_name[item.name] = item
end

local normal_builtins = {
	"files", "git_files", "grep", "live_grep", "grep_cword", "grep_cWORD", "buffers", "tabs", "lines", "blines",
	"tags", "btags", "marks", "jumps", "changes", "registers", "keymaps", "commands", "command_history", "help_tags",
	"man_pages", "colorschemes", "git_commits", "git_worktrees", "git_bcommits", "git_branches", "git_status", "git_stash",
	"lsp_references", "lsp_definitions", "lsp_declarations", "lsp_typedefs", "lsp_implementations",
	"lsp_document_symbols", "lsp_workspace_symbols", "diagnostics_document", "diagnostics_workspace", "oldfiles", "quickfix",
	"loclist", "yank_history", "aws_accounts", "opencode_messages", "opencode_prompts", "opencode_assistant",
	"opencode_reasoning", "opencode_tools", "opencode_tool_output", "opencode_sessions", "opencode_all_sessions",
}

local function format_values(item, selected, opts)
	return yank.insert_text(item.kind, selected, opts, item.config)
end

function M.catalog()
	return vim.deepcopy(catalog)
end

function M.transform(name, selected, opts)
	local item = by_name[name]
	return item and format_values(item, selected, opts) or nil
end

local function restore_source(owner)
	if owner and owner.source then
		local source = type(owner.source) == "function" and owner.source() or owner.source
		if source then
			require("config.return_target").restore(source, { fallback = false })
		end
	end
end

local function lifecycle(owner, cleanup)
	local stage = { completed = false, transitioned = false }
	local function close()
		if cleanup then
			pcall(cleanup)
		end
		vim.schedule(function()
			if not stage.completed and not stage.transitioned and owner and owner.restore then
				owner.restore()
			end
		end)
	end
	return stage, close
end

local function insert_action(item, owner, stage)
	return function(selected, opts)
		local text = format_values(item, selected, opts)
		if not text then
			return
		end
		stage.completed = true
		owner.insert(text)
	end
end

local function launch_public(item, owner)
	restore_source(owner)
	if item.dap then
		pcall(function()
			require("lazy").load({ plugins = { "nvim-dap" } })
		end)
	end

	local opts = type(item.opts) == "function" and item.opts() or vim.deepcopy(item.opts or {})
	opts._start = false
	local picker_name = item.picker or item.name
	local picker = require("fzf-lua")[picker_name]
	if type(picker) ~= "function" then
		if owner.restore then owner.restore() end
		return
	end
	local core = require("fzf-lua.core")
	local original_wrap = core.fzf_wrap
	local captured_command, captured_opts
	-- The pinned live_grep provider omits the return from core.fzf_live().
	-- Capture its synchronous _start=false resolution without starting fzf.
	local capture_live = picker_name == "live_grep"
	if capture_live then
		core.fzf_wrap = function(command, resolved, convert_actions)
			if resolved and resolved._start == false then
				captured_command, captured_opts = command, resolved
			end
			return original_wrap(command, resolved, convert_actions)
		end
	end
	local ok, _, command, resolved = pcall(picker, opts)
	if capture_live then core.fzf_wrap = original_wrap end
	if not ok then
		if owner.restore then owner.restore() end
		return
	end
	command = command or captured_command
	resolved = resolved or captured_opts
	if not command or not resolved then
		if owner.restore then owner.restore() end
		return
	end

	local prior_close = resolved.winopts and resolved.winopts.on_close
	local stage, on_close = lifecycle(owner, prior_close)
	resolved._start = nil
	-- Prompt pickers intentionally exclude provider actions that can mutate editor or session state.
	resolved.actions = { enter = insert_action(item, owner, stage) }
	if item.yank ~= false then resolved.actions["ctrl-y"] = yank.action(item.kind, item.config) end
	resolved.winopts = vim.tbl_deep_extend("force", resolved.winopts or {}, { on_close = on_close })
	core.fzf_wrap(command, resolved, true)
end

local function launch_projects(owner)
	restore_source(owner)
	pcall(function()
		require("lazy").load({ plugins = { "project.nvim" } })
	end)
	local ok, history = pcall(require, "project_nvim.utils.history")
	local projects = ok and history.get_recent_projects() or {}
	local stage, on_close = lifecycle(owner)
	require("fzf-lua").fzf_exec(projects, {
		prompt = "Projects> ",
		winopts = { on_close = on_close },
		actions = {
			enter = insert_action(by_name.projects, owner, stage),
			["ctrl-y"] = yank.action("display"),
		},
	})
end

local function launch_yanks(owner)
	restore_source(owner)
	pcall(function()
		require("lazy").load({ plugins = { "nvim-neoclip.lua" } })
	end)
	local ok, storage = pcall(require, "neoclip.storage")
	local yanks = ok and storage.get().yanks or {}
	local entries, entry_map = {}, {}
	for index, yank in ipairs(yanks) do
		local contents = clean(table.concat(yank.contents or {}, " "))
		local entry = ("%d. %s"):format(index, contents)
		table.insert(entries, entry)
		entry_map[entry] = yank
	end
	local stage, on_close = lifecycle(owner)
	require("fzf-lua").fzf_exec(entries, {
		prompt = "Yank History> ",
		winopts = { on_close = on_close },
			actions = {
				enter = function(selected)
					local values = {}
					for _, entry in ipairs(selected or {}) do
						local value = entry_map[clean(entry)] or entry_map[entry]
						if value then table.insert(values, table.concat(value.contents or {}, "\n")) end
					end
				if #values > 0 then
					stage.completed = true
					owner.insert(table.concat(values, " ") .. " ")
				end
			end,
				["ctrl-y"] = function(selected)
					local selected_yanks = {}
					for _, entry in ipairs(selected or {}) do
						local value = entry_map[clean(entry)] or entry_map[entry]
						if value then table.insert(selected_yanks, value) end
					end
					if #selected_yanks == 0 then return end
					if #selected_yanks == 1 then
						local value = selected_yanks[1]
						vim.fn.setreg("+", value.contents or {}, value.regtype)
					else
						local blocks = {}
						for index, value in ipairs(selected_yanks) do
							table.insert(blocks, ("Yank %d\n%s"):format(index, table.concat(value.contents or {}, "\n")))
						end
						vim.fn.setreg("+", table.concat(blocks, "\n\n"), "V")
					end
					vim.notify(("Yanked %d FZF selection%s"):format(#selected_yanks, #selected_yanks == 1 and "" or "s"))
				end,
		},
	})
end

local function insert_aws_values(aws_profiles, extract, owner, stage)
	return function(selected)
		local values, seen = {}, {}
		for _, entry in ipairs(selected or {}) do
			local value = extract(aws_profiles.decode_row(entry))
			if value and value ~= "" and not seen[value] then
				seen[value] = true
				table.insert(values, value)
			end
		end
		if #values > 0 then
			stage.completed = true
			owner.insert(table.concat(values, " ") .. " ")
		end
	end
end

local function launch_aws_accounts(owner)
	restore_source(owner)
	local aws_profiles = require("config.aws_profiles")
	local profiles = aws_profiles.profiles()
	local rows = vim.tbl_map(aws_profiles.row, profiles)
	local stage, on_close = lifecycle(owner)
	require("fzf-lua").fzf_exec(rows, {
		prompt = "AWS Accounts> ",
		fzf_opts = {
			["--header"] = ":: enter insert account id  ::  alt-y insert profile name  ::  alt-b insert both",
		},
		winopts = { on_close = on_close },
		actions = {
			enter = insert_action(by_name.aws_accounts, owner, stage),
			["ctrl-y"] = yank.action("aws_account"),
			["alt-y"] = insert_aws_values(aws_profiles, function(decoded) return decoded.profile end, owner, stage),
			["alt-b"] = insert_aws_values(aws_profiles, aws_profiles.combined, owner, stage),
		},
	})
end

local function launch_opencode(item, owner)
	restore_source(owner)
	local pickers = require("config.opencode_pickers")
	local prompt = { owner = owner }
	local actions = {
		opencode_messages = function() pickers.all({ prompt = prompt }) end,
		opencode_prompts = function() pickers.prompts({ prompt = prompt }) end,
		opencode_assistant = function() pickers.assistant({ prompt = prompt }) end,
		opencode_reasoning = function() pickers.reasoning({ prompt = prompt }) end,
		opencode_tools = function() pickers.tools({ prompt = prompt }) end,
		opencode_tool_output = function() pickers.tool_output({ prompt = prompt }) end,
		opencode_sessions = function()
			pickers.sessions("all", { prompt = prompt, session_scope = "local", allow_cross_route_fork = true })
		end,
		opencode_all_sessions = function()
			pickers.all_sessions("all", { prompt = prompt, session_scope = "local", allow_cross_route_fork = true })
		end,
	}
	local action = actions[item.name]
	if action then action() end
end

function M.launch(name, owner)
	local item = by_name[name]
	if not item or not owner or type(owner.insert) ~= "function" then
		return
	end
	if item.name == "projects" then
		launch_projects(owner)
	elseif item.name == "yank_history" then
		launch_yanks(owner)
	elseif item.name == "aws_accounts" then
		launch_aws_accounts(owner)
	elseif item.name:match("^opencode_") then
		launch_opencode(item, owner)
	else
		launch_public(item, owner)
	end
end

local function open_prompt_menu(owner)
	local entries = vim.tbl_map(function(item) return item.name end, catalog)
	local stage, on_close = lifecycle(owner)
	require("fzf-lua").fzf_exec(entries, {
		prompt = "Insert from picker> ",
		winopts = { on_close = on_close },
		actions = {
			enter = function(selected)
				local choice = selected and selected[1]
				if not by_name[choice] then return end
				stage.transitioned = true
				vim.schedule(function() M.launch(choice, owner) end)
			end,
		},
	})
end

local function open_normal_menu()
	local fzf = require("fzf-lua")
	fzf.fzf_exec(normal_builtins, {
		prompt = "FZF-Lua Builtins> ",
		actions = {
			enter = function(selected)
				local choice = selected and selected[1]
				if not choice then return end
				vim.schedule(function()
					if choice == "yank_history" then
						require("neoclip.fzf")()
					elseif choice == "aws_accounts" then
						local aws_profiles = require("config.aws_profiles")
						local profiles = aws_profiles.profiles()
						local rows = vim.tbl_map(aws_profiles.row, profiles)
						fzf.fzf_exec(rows, {
							prompt = "AWS Accounts> ",
							fzf_opts = {
								["--header"] = ":: enter yank account id  ::  alt-y yank profile name  ::  alt-b yank both",
							},
							actions = {
								["default"] = function(selected)
									if selected and selected[1] then
										aws_profiles.yank_account_id(selected[1])
									end
								end,
								["alt-y"] = function(selected)
									if selected and selected[1] then
										aws_profiles.yank_profile_name(selected[1])
									end
								end,
								["alt-b"] = function(selected)
									if selected and selected[1] then
										aws_profiles.yank_both(selected[1])
									end
								end,
							},
						})
					elseif choice:match("^opencode_") then
						local pickers = require("config.opencode_pickers")
						local actions = {
							opencode_messages = pickers.all,
							opencode_prompts = pickers.prompts,
							opencode_assistant = pickers.assistant,
							opencode_reasoning = pickers.reasoning,
							opencode_tools = pickers.tools,
							opencode_tool_output = pickers.tool_output,
						opencode_sessions = function()
							pickers.sessions("all", { session_scope = "local", allow_cross_route_fork = true })
						end,
						opencode_all_sessions = function()
							pickers.all_sessions("all", { session_scope = "local", allow_cross_route_fork = true })
						end,
						}
						if actions[choice] then actions[choice]() end
					elseif choice == "dap_frames" then
						require("config.fzf_dap").launch()
					elseif type(fzf[choice]) == "function" then
						fzf[choice]()
					end
				end)
			end,
		},
	})
end

function M.open_menu(owner)
	if owner then
		open_prompt_menu(owner)
	else
		open_normal_menu()
	end
end

function M.bind(buf, owner)
	local mode = owner.mode or "n"
	local function key(lhs)
		return owner.prefix and lhs:gsub("^<leader>", owner.prefix) or lhs
	end
	for _, item in ipairs(catalog) do
		if item.key then
			vim.keymap.set(mode, key(item.key), function()
				M.launch(item.name, owner)
			end, { buffer = buf, desc = item.desc })
		end
	end
	vim.keymap.set(mode, key("<leader>fz"), function()
		M.open_menu(owner)
	end, { buffer = buf, desc = "Choose picker for prompt" })
end

return M

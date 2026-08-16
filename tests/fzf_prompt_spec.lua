package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function contains(haystack, needle, message)
	assert(vim.tbl_contains(haystack, needle), message .. ": " .. vim.inspect(haystack))
end

local scheduled = {}
local original_schedule = vim.schedule
vim.schedule = function(callback)
	table.insert(scheduled, callback)
end

local current_win = 21
local source_target = { win = 7, buf = 8 }
local restore_calls = {}
package.loaded["config.return_target"] = {
	restore = function(target, opts)
		table.insert(restore_calls, { target = target, opts = opts })
		return true
	end,
}

local wrapped
package.loaded["fzf-lua.core"] = {
	fzf_wrap = function(command, opts, convert_actions)
		wrapped = { command = command, opts = opts, convert_actions = convert_actions }
		return nil, command, opts
	end,
}

package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value)
		return value:gsub("\27%[[%d;]*m", "")
	end,
}

package.loaded["fzf-lua.path"] = {
	entry_to_file = function(entry, opts)
		local clean = entry:gsub("\27%[[%d;]*m", "")
		local path, line, col = clean:match("([^:]+):(%d+):(%d+):")
		if not path then
			path, line = clean:match("([^:]+):(%d+):")
		end
		path = path or clean
		if opts and opts.cwd and not path:match("^/") then
			path = opts.cwd .. "/" .. path
		end
		return { path = path, line = tonumber(line) or 0, col = tonumber(col) or 0 }
	end,
}

local picker_calls = {}
package.loaded["fzf-lua"] = setmetatable({
	fzf_exec = function(entries, opts)
		table.insert(picker_calls, { name = "fzf_exec", entries = entries, opts = opts })
	end,
}, {
	__index = function(_, name)
		return function(opts)
			table.insert(picker_calls, { name = name, opts = opts })
			if opts == nil then return end
			assert(opts._start == false, name .. " resolves without starting fzf")
			return nil, "command:" .. name, {
				_start = false,
				cwd = opts.cwd or vim.fn.getcwd(),
				actions = {
					enter = function() error("normal Enter action leaked") end,
					["ctrl-x"] = function() error("destructive alternate action leaked") end,
				},
				winopts = {
					on_close = function()
						table.insert(restore_calls, "provider-cleanup")
					end,
				},
			}
		end
	end,
})

local original_get_current_win = vim.api.nvim_get_current_win
vim.api.nvim_get_current_win = function()
	return current_win
end

local inserted = {}
local owner_restores = 0
local clipboard = {}
local original_setreg = vim.fn.setreg
local original_notify = vim.notify
vim.fn.setreg = function(register, value, regtype)
	if register == "+" then
		local write = { register = register, value = value }
		if regtype then write.regtype = regtype end
		table.insert(clipboard, write)
		return
	end
	return original_setreg(register, value)
end
vim.notify = function() end
local owner = {
	source = source_target,
	insert = function(text)
		table.insert(inserted, text)
	end,
	restore = function()
		owner_restores = owner_restores + 1
	end,
}

package.loaded["config.fzf_yank"] = dofile("lua/config/fzf_yank.lua")
local prompt = dofile("lua/config/fzf_prompt.lua")
local names = vim.tbl_map(function(item)
	return item.name
end, prompt.catalog())
local catalog = {}
for _, item in ipairs(prompt.catalog()) do catalog[item.name] = item end

for _, expected in ipairs({
	"files",
	"live_grep",
	"git_status",
	"git_commits",
	"git_worktrees",
	"git_branches",
	"git_stash",
	"lsp_document_symbols",
	"diagnostics_workspace",
	"yank_history",
	"projects",
	"zoxide",
	"dap_frames",
	"opencode_messages",
	"registers",
	"command_history",
	"lsp_references",
	"tags",
	"aws_accounts",
}) do
	contains(names, expected, "prompt catalog includes " .. expected)
end
assert(not vim.tbl_contains(names, "colorschemes"), "prompt catalog excludes colorscheme actions")
assert(not vim.tbl_contains(names, "resume"), "prompt catalog excludes unknown resume actions")
eq(catalog.tabs.kind, "location", "tab completions retain their source location")

prompt.launch("files", owner)
eq(restore_calls[1], { target = source_target, opts = { fallback = false } }, "picker resolves from the captured editor source")
eq(wrapped.command, "command:files", "the provider's stringified command is relaunched")
eq(wrapped.convert_actions, true, "the second phase asks fzf-lua to convert replacement actions")
eq(wrapped.opts._start, nil, "the second phase clears the no-start marker")
assert(
	vim.tbl_count(wrapped.opts.actions) == 2 and wrapped.opts.actions.enter and wrapped.opts.actions["ctrl-y"],
	"resolved prompt providers retain only safe Enter and Ctrl-y actions"
)

wrapped.opts.winopts.on_close()
eq(restore_calls[2], "provider-cleanup", "provider cleanup still runs immediately on close")
eq(#scheduled, 1, "owner restoration is deferred until after action dispatch")
wrapped.opts.actions.enter({ "lua/config/fzf_prompt.lua" }, wrapped.opts)
local root = vim.fs.normalize(vim.fn.getcwd())
eq(inserted, { root .. "/lua/config/fzf_prompt.lua " }, "Enter inserts one absolute value with one trailing space")
scheduled[1]()
eq(owner_restores, 0, "selection suppresses the deferred cancellation restore")

scheduled = {}
prompt.launch("files", owner)
wrapped.opts.winopts.on_close()
scheduled[1]()
eq(owner_restores, 1, "cancelling restores the prompt owner once")

scheduled = {}
prompt.launch("files", owner)
wrapped.opts.winopts.on_close()
wrapped.opts.actions["ctrl-y"]({ "lua/config/fzf_prompt.lua" }, wrapped.opts)
eq(clipboard, { { register = "+", value = root .. "/lua/config/fzf_prompt.lua" } }, "Ctrl-y copies the absolute selection")
eq(inserted, { root .. "/lua/config/fzf_prompt.lua " }, "Ctrl-y never inserts into the prompt")
scheduled[1]()
eq(owner_restores, 2, "Ctrl-y closes and restores the prompt owner")

eq(prompt.transform("git_branches", { "\27[32m* main abc123 subject\27[0m" }, {}), "main ", "branch markers are stripped")
eq(prompt.transform("git_branches", { "+ feature/topic def456 subject" }, {}), "feature/topic ", "worktree branch markers are stripped")
eq(prompt.transform("git_commits", { "abc1234 (2 days ago) fix parser" }, {}), "abc1234 ", "commit rows insert their SHA")
eq(
	prompt.transform("git_worktrees", { "\27[34m/Users/shahe/work/topic\27[0m  abc1234 [topic]" }, {}),
	"/Users/shahe/work/topic ",
	"worktree rows insert only the worktree path"
)
eq(prompt.transform("git_stash", { "stash@{2}: On main: WIP" }, {}), "stash@{2} ", "stash rows insert their ref")
eq(
	prompt.transform("git_status", { "R  old name.lua -> new name.lua" }, {}),
	root .. "/new name.lua ",
	"renamed Git status rows insert the destination path"
)
eq(prompt.transform("git_status", { " D deleted file.lua" }, {}), root .. "/deleted file.lua ", "unstaged deletions retain their absolute path")
eq(prompt.transform("git_status", { '?? "new file.lua"' }, {}), root .. "/new file.lua ", "quoted untracked paths are unwrapped")
eq(
	prompt.transform("git_status", { 'C  "old file.lua" -> "copied file.lua"' }, {}),
	root .. "/copied file.lua ",
	"copied Git status rows insert the destination path"
)
eq(
	prompt.transform("live_grep", { "lua/mod.lua:42:7:matched text" }, { cwd = vim.fn.getcwd() }),
	root .. "/lua/mod.lua:42:7 ",
	"location rows preserve absolute path, line, and column"
)
eq(
	prompt.transform("files", { "alpha.lua", "alpha.lua", "beta.lua" }, {}),
	root .. "/alpha.lua " .. root .. "/beta.lua ",
	"multi-selection is deduplicated and space-joined"
)

package.loaded["dap"] = {
	session = function()
		return {
			stopped_thread_id = 1,
			threads = { [1] = { frames = { { source = { path = "/tmp/frame source.lua" }, line = 12, column = 3 } } } },
		}
	end,
}
inserted = {}
clipboard = {}
prompt.launch("dap_frames", owner)
wrapped.opts.actions.enter({ "1. [main] frame.lua:12" }, wrapped.opts)
eq(inserted, { "/tmp/frame source.lua:12:3 " }, "prompt DAP frames insert their live absolute source location")
wrapped.opts.actions["ctrl-y"]({ "1. [main] frame.lua:12" }, wrapped.opts)
eq(clipboard, { { register = "+", value = "/tmp/frame source.lua:12:3" } }, "prompt DAP frames yank their live absolute source location")

local original_register = vim.fn.getreg("z", 1, true)
local original_register_type = vim.fn.getregtype("z")
vim.fn.setreg("z", { "first  line", "second line" }, "V")
eq(
	prompt.transform("registers", { "[z] [l] decorated preview" }, {}),
	"first  line\nsecond line\n ",
	"register pickers insert the exact register contents"
)
vim.fn.setreg("z", original_register, original_register_type)

package.loaded["neoclip.storage"] = {
	get = function()
		return { yanks = { { contents = { "first  line", "second line" }, regtype = "V" } } }
	end,
}
clipboard = {}
picker_calls = {}
prompt.launch("yank_history", owner)
local yank_history = picker_calls[#picker_calls]
yank_history.opts.actions["ctrl-y"]({ yank_history.entries[1] })
eq(
	clipboard,
	{ { register = "+", value = { "first  line", "second line" }, regtype = "V" } },
	"prompt yank history preserves exact contents and register type"
)

package.loaded["config.aws_profiles"] = {
	profiles = function()
		return {
			{ profile = "labs", account_id = "154805902702", role = "AWSAdministratorAccess" },
			{ profile = "prod", account_id = "325875666703", role = "AWSAdministratorAccess" },
		}
	end,
	row = function(entry)
		return ("%s  •  %s  •  %s"):format(entry.profile, entry.account_id, entry.role or "")
	end,
	decode_row = function(display_row)
		local profile, account_id = display_row:match("^(.-)  •  (.-)  •  ")
		return { profile = profile, account_id = account_id }
	end,
	combined = function(entry)
		return ("%s (%s)"):format(entry.profile, entry.account_id)
	end,
}

inserted = {}
scheduled = {}
picker_calls = {}
prompt.launch("aws_accounts", owner)
local aws_call = picker_calls[#picker_calls]
eq(aws_call.name, "fzf_exec", "aws_accounts launches a custom fzf_exec picker, not a public fzf-lua provider")
eq(
	aws_call.entries,
	{ "labs  •  154805902702  •  AWSAdministratorAccess", "prod  •  325875666703  •  AWSAdministratorAccess" },
	"aws_accounts rows are built from the parsed profiles"
)
aws_call.opts.actions.enter({ "prod  •  325875666703  •  AWSAdministratorAccess" })
eq(inserted, { "325875666703 " }, "selecting an AWS account inserts its account id")

clipboard = {}
aws_call.opts.actions["ctrl-y"]({ "prod  •  325875666703  •  AWSAdministratorAccess" })
eq(clipboard, { { register = "+", value = "325875666703" } }, "Ctrl-y yanks the AWS account id")

inserted = {}
aws_call.opts.actions["alt-y"]({ "prod  •  325875666703  •  AWSAdministratorAccess" })
eq(inserted, { "prod " }, "alt-y inserts the AWS account's profile name")

inserted = {}
aws_call.opts.actions["alt-b"]({ "prod  •  325875666703  •  AWSAdministratorAccess" })
eq(inserted, { "prod (325875666703) " }, "alt-b inserts the combined profile name and account id")

eq(
	aws_call.opts.fzf_opts["--header"],
	":: enter insert account id  ::  alt-y insert profile name  ::  alt-b insert both",
	"the prompt-mode AWS picker's header documents all three insertion actions"
)

local opencode_dispatches = {}
package.loaded["config.opencode_pickers"] = {
	all = function() end,
	prompts = function() end,
	assistant = function() end,
	reasoning = function() end,
	tools = function() end,
	tool_output = function() end,
	sessions = function(scope, opts)
		table.insert(opencode_dispatches, { kind = "history", scope = scope, opts = opts })
	end,
	all_sessions = function(scope, opts)
		table.insert(opencode_dispatches, { kind = "aggregate", scope = scope, opts = opts })
	end,
}
prompt.launch("opencode_sessions", owner)
prompt.launch("opencode_all_sessions", owner)
eq(opencode_dispatches[1].scope, "all", "prompt session history retains the all-message content scope")
eq(opencode_dispatches[1].opts.session_scope, "local", "prompt session history starts in Local scope")
eq(opencode_dispatches[1].opts.prompt.owner, owner, "prompt session history retains its owner")
eq(opencode_dispatches[2].scope, "all", "prompt aggregate search retains the all-message content scope")
eq(opencode_dispatches[2].opts.session_scope, "local", "prompt aggregate search starts in Local scope")
eq(opencode_dispatches[2].opts.prompt.owner, owner, "prompt aggregate search retains its owner")

scheduled = {}
picker_calls = {}
prompt.open_menu()
local opencode_menu = picker_calls[#picker_calls]
opencode_menu.opts.actions.enter({ "opencode_sessions" })
scheduled[1]()
eq(
	opencode_dispatches[3],
	{ kind = "history", scope = "all", opts = { session_scope = "local", allow_cross_route_fork = true } },
	"normal prompt catalog history starts Local"
)

scheduled = {}
prompt.open_menu()
opencode_menu = picker_calls[#picker_calls]
opencode_menu.opts.actions.enter({ "opencode_all_sessions" })
scheduled[1]()
eq(
	opencode_dispatches[4],
	{ kind = "aggregate", scope = "all", opts = { session_scope = "local", allow_cross_route_fork = true } },
	"normal prompt catalog aggregate search starts Local"
)

inserted = {}
prompt.launch("git_worktrees", owner)
eq(wrapped.command, "command:git_worktrees", "the worktree provider is relaunched for prompt insertion")
assert(
	vim.tbl_count(wrapped.opts.actions) == 2 and wrapped.opts.actions.enter and wrapped.opts.actions["ctrl-y"],
	"prompt worktrees retain only safe insertion and yank actions"
)
wrapped.opts.actions.enter({ "\27[34m/Users/shahe/work/topic\27[0m  abc1234 [topic]" }, wrapped.opts)
eq(inserted, { "/Users/shahe/work/topic " }, "prompt worktrees insert the selected path")

scheduled = {}
picker_calls = {}
prompt.open_menu()
local normal_menu = picker_calls[#picker_calls]
eq(normal_menu.name, "fzf_exec", "the ownerless picker opens the regular FZF menu")
contains(normal_menu.entries, "git_commits", "the regular FZF menu includes Git commits")
contains(normal_menu.entries, "git_worktrees", "the regular FZF menu includes Git worktrees")
normal_menu.opts.actions.enter({ "git_worktrees" })
eq(#scheduled, 1, "regular picker dispatch is scheduled after the menu closes")
scheduled[1]()
local normal_worktrees = picker_calls[#picker_calls]
eq(normal_worktrees.name, "git_worktrees", "the regular FZF menu dispatches the worktree provider")
eq(normal_worktrees.opts, nil, "regular worktrees retain the provider's normal actions")

scheduled = {}
prompt.open_menu()
normal_menu = picker_calls[#picker_calls]
normal_menu.opts.actions.enter({ "dap_frames" })
scheduled[1]()
eq(wrapped.command, "command:dap_frames", "ownerless DAP frame dispatch routes through the semantic adapter")
assert(wrapped.opts.actions["ctrl-y"], "ownerless DAP frame dispatch exposes semantic Ctrl-y")

local binding_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(binding_buf)
prompt.bind(binding_buf, {
	mode = "t",
	prefix = "<C-Space>",
	insert = function() end,
	restore = function() end,
})
local function binding(lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(binding_buf, "t")) do
		if mapping.lhs == lhs then return mapping end
	end
end
eq(
	binding("<C-Space>ff").desc,
	"Find files",
	"an explicit prompt prefix binds the files picker directly in terminal mode"
)
eq(
	binding("<C-Space>fz").desc,
	"Choose picker for prompt",
	"an explicit prompt prefix also binds the picker menu directly in terminal mode"
)
eq(
	binding("<Space>ff"),
	nil,
	"an explicit prompt prefix leaves ordinary terminal leader text unmapped"
)

vim.schedule = original_schedule
vim.api.nvim_get_current_win = original_get_current_win
vim.fn.setreg = original_setreg
vim.notify = original_notify

print("PASS fzf prompt adapter catalog, safety, transforms, and lifecycle")

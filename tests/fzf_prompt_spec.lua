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
local owner = {
	source = source_target,
	insert = function(text)
		table.insert(inserted, text)
	end,
	restore = function()
		owner_restores = owner_restores + 1
	end,
}

local prompt = require("config.fzf_prompt")
local names = vim.tbl_map(function(item)
	return item.name
end, prompt.catalog())

for _, expected in ipairs({
	"files",
	"live_grep",
	"git_status",
	"git_commits",
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
}) do
	contains(names, expected, "prompt catalog includes " .. expected)
end
assert(not vim.tbl_contains(names, "colorschemes"), "prompt catalog excludes colorscheme actions")
assert(not vim.tbl_contains(names, "resume"), "prompt catalog excludes unknown resume actions")

prompt.launch("files", owner)
eq(restore_calls[1], { target = source_target, opts = { fallback = false } }, "picker resolves from the captured editor source")
eq(wrapped.command, "command:files", "the provider's stringified command is relaunched")
eq(wrapped.convert_actions, true, "the second phase asks fzf-lua to convert replacement actions")
eq(wrapped.opts._start, nil, "the second phase clears the no-start marker")
assert(
	vim.tbl_count(wrapped.opts.actions) == 1 and wrapped.opts.actions.enter,
	"all inherited normal and alternate actions are removed"
)

wrapped.opts.winopts.on_close()
eq(restore_calls[2], "provider-cleanup", "provider cleanup still runs immediately on close")
eq(#scheduled, 1, "owner restoration is deferred until after action dispatch")
wrapped.opts.actions.enter({ "lua/config/fzf_prompt.lua" }, wrapped.opts)
eq(inserted, { "lua/config/fzf_prompt.lua " }, "Enter inserts one normalized value with one trailing space")
scheduled[1]()
eq(owner_restores, 0, "selection suppresses the deferred cancellation restore")

scheduled = {}
prompt.launch("files", owner)
wrapped.opts.winopts.on_close()
scheduled[1]()
eq(owner_restores, 1, "cancelling restores the prompt owner once")

eq(prompt.transform("git_branches", { "\27[32m* main abc123 subject\27[0m" }, {}), "main ", "branch markers are stripped")
eq(prompt.transform("git_branches", { "+ feature/topic def456 subject" }, {}), "feature/topic ", "worktree branch markers are stripped")
eq(prompt.transform("git_commits", { "abc1234 (2 days ago) fix parser" }, {}), "abc1234 ", "commit rows insert their SHA")
eq(prompt.transform("git_stash", { "stash@{2}: On main: WIP" }, {}), "stash@{2} ", "stash rows insert their ref")
eq(
	prompt.transform("git_status", { "R  old name.lua -> new name.lua" }, {}),
	"new name.lua ",
	"renamed Git status rows insert the destination path"
)
eq(prompt.transform("git_status", { " D deleted file.lua" }, {}), "deleted file.lua ", "unstaged deletions retain their path")
eq(prompt.transform("git_status", { '?? "new file.lua"' }, {}), "new file.lua ", "quoted untracked paths are unwrapped")
eq(
	prompt.transform("git_status", { 'C  "old file.lua" -> "copied file.lua"' }, {}),
	"copied file.lua ",
	"copied Git status rows insert the destination path"
)
eq(
	prompt.transform("live_grep", { "lua/mod.lua:42:7:matched text" }, { cwd = vim.fn.getcwd() }),
	"lua/mod.lua:42:7 ",
	"location rows preserve project-relative line and column"
)
eq(
	prompt.transform("files", { "alpha.lua", "alpha.lua", "beta.lua" }, {}),
	"alpha.lua beta.lua ",
	"multi-selection is deduplicated and space-joined"
)

local original_register = vim.fn.getreg("z")
vim.fn.setreg("z", { "first line", "second line" })
eq(
	prompt.transform("registers", { "[z] [l] decorated preview" }, {}),
	"first line second line ",
	"register pickers insert the actual flattened register contents"
)
vim.fn.setreg("z", original_register)

vim.schedule = original_schedule
vim.api.nvim_get_current_win = original_get_current_win

print("PASS fzf prompt adapter catalog, safety, transforms, and lifecycle")

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value)
		return value:gsub("\27%[[%d;]*m", "")
	end,
}

package.loaded["fzf-lua.path"] = {
	entry_to_file = function(entry, opts)
		if entry == "unparseable" then return nil end
		if entry:find("●", 1, true) then
			return { path = (opts.cwd or vim.fn.getcwd()) .. "/src/main.lua", line = 0, col = 0 }
		end
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

package.loaded["config.aws_profiles"] = {
	decode_row = function(row)
		local profile, account_id = row:match("^(.-)  •  (.-)  •")
		return { profile = profile, account_id = account_id }
	end,
}

local yank = require("config.fzf_yank")

eq(yank.clean("  \27[32malpha\194\160 beta\27[0m  "), "alpha beta", "display cleanup strips ANSI and normalizes spacing")
eq(yank.clipboard_text("branch", { "* main abc123 subject", "+ feature/topic def456" }), "main feature/topic", "branch values strip worktree markers")
eq(yank.clipboard_text("commit", { "abc1234 subject", "abc1234 duplicate", "def5678 other" }), "abc1234 def5678", "multi-selection is deduplicated")
eq(yank.clipboard_text("stash", { "stash@{2}: On main: WIP" }), "stash@{2}", "stash rows copy only the ref")
eq(yank.clipboard_text("worktree", { "/repo/topic abc123 [topic]" }), "/repo/topic", "worktree rows copy only their path")
eq(yank.clipboard_text("command", { "write" }), ":write", "commands retain their Ex prefix")
eq(yank.clipboard_text("zoxide", { "42.5\t/repo/topic" }), "/repo/topic", "zoxide rows omit their score")
eq(
	yank.clipboard_text("aws_account", { "prod  •  325875666703  •  AWSAdministratorAccess" }),
	"325875666703",
	"AWS rows copy only the account id"
)
eq(
	yank.clipboard_text("git_status", { 'R  "old file.lua" -> "new file.lua"' }),
	"new file.lua",
	"Git status copies the destination path"
)
eq(
	yank.clipboard_text("git_status", { "●\194\160●\194\160\194\160src/main.lua" }, { cwd = vim.fn.getcwd() }),
	"src/main.lua",
	"transformed Git status rows omit icon metadata"
)
eq(
	yank.clipboard_text("location", { "lua/mod.lua:42:7:matched text" }, { cwd = vim.fn.getcwd() }),
	"lua/mod.lua:42:7",
	"locations retain project-relative line and column"
)
eq(
	yank.clipboard_text("path", { "/repo/src/main.lua" }, {}, { reference_dir = "/repo" }),
	"src/main.lua",
	"paths inside an explicit reference directory are relative"
)
eq(
	yank.clipboard_text("path", { "/other/main.lua" }, {}, { reference_dir = "/repo" }),
	"/other/main.lua",
	"paths outside an explicit reference directory stay absolute"
)
eq(
	yank.clipboard_text("display", { "row-a", "row-b" }, {}, {
		resolve = function(entry) return ({ ["row-a"] = "first", ["row-b"] = "second" })[entry] end,
		separator = "\n\n",
	}),
	"first\n\nsecond",
	"custom resolvers can preserve payload separators"
)
eq(yank.insert_text("path", { "alpha.lua", "beta.lua" }), "alpha.lua beta.lua ", "prompt insertion retains one trailing space")
eq(yank.clipboard_text("display", {}), nil, "empty selections do not produce clipboard text")
eq(yank.clipboard_text("location", { "unparseable" }), nil, "unparseable location rows fail closed")

local original_z = vim.fn.getreg("z")
vim.fn.setreg("z", { "first line", "second line" })
eq(yank.clipboard_text("register", { "[z] [l] preview" }), "first line second line", "register rows copy their contents")
vim.fn.setreg("z", original_z)

local original_setreg = vim.fn.setreg
local original_notify = vim.notify
local writes = {}
local notifications = {}
vim.fn.setreg = function(register, value)
	table.insert(writes, { register = register, value = value })
end
vim.notify = function(message)
	table.insert(notifications, message)
end

local action = yank.action("location")
local result = action({ "lua/mod.lua:42:7:matched text" }, { cwd = vim.fn.getcwd() })
eq(result, nil, "the yank action does not return a resume action")
eq(writes, { { register = "+", value = "lua/mod.lua:42:7" } }, "the yank action writes semantic text to the system clipboard")
eq(#notifications, 1, "a successful yank reports one notification")

action({}, {})
eq(#writes, 1, "empty selections leave the clipboard untouched")
eq(#notifications, 1, "empty selections do not notify")

package.loaded["fzf-lua.actions"] = {
	resume = function() error("Ctrl-y must not resume") end,
}
local plugin = dofile("lua/plugins/fzf-lua.lua")
local opts = plugin[1].opts()
assert(opts.defaults.actions["ctrl-y"], "the FZF defaults expose Ctrl-y to every inherited picker")
assert(opts.actions.files["ctrl-y"], "file-like providers inherit semantic location yanks")
assert(opts.actions.buffers["ctrl-y"], "buffer providers inherit semantic path yanks")
assert(opts.git.status.actions["ctrl-y"], "Git status exposes semantic path yanks")
assert(opts.git.worktrees.actions["ctrl-y"], "Git worktrees expose semantic path yanks")
assert(opts.commands.actions["ctrl-y"], "commands expose executable yanks")
assert(opts.command_history.actions["ctrl-y"], "command history exposes executable yanks")
assert(opts.registers.actions["ctrl-y"], "registers expose content yanks")
opts.defaults.actions["ctrl-y"]({ "generic decorated row" }, {})
eq(writes[2], { register = "+", value = "generic decorated row" }, "the global fallback yanks generic picker rows")

local custom_picker
local fzf_stub = {
	fzf_exec = function(entries, picker_opts) custom_picker = { entries = entries, opts = picker_opts } end,
	zoxide = function(picker_opts) custom_picker = { opts = picker_opts } end,
	git_commits = function(picker_opts) custom_picker = { kind = "commits", opts = picker_opts } end,
	git_branches = function(picker_opts) custom_picker = { kind = "branches", opts = picker_opts } end,
	git_stash = function(picker_opts) custom_picker = { kind = "stashes", opts = picker_opts } end,
}
package.loaded["fzf-lua"] = fzf_stub
package.loaded["config.aws_profiles"] = {
	profiles = function()
		return { { profile = "prod", account_id = "325875666703", role = "AWSAdministratorAccess" } }
	end,
	row = function(entry) return ("%s  •  %s  •  %s"):format(entry.profile, entry.account_id, entry.role) end,
	decode_row = function(row)
		local profile, account_id = row:match("^(.-)  •  (.-)  •")
		return { profile = profile, account_id = account_id }
	end,
}

for _, mapping in ipairs(plugin[1].keys) do
	if mapping.desc == "Find AWS accounts" then mapping[2]() end
end
assert(custom_picker.opts.actions["ctrl-y"], "the normal AWS picker exposes semantic Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ custom_picker.entries[1] })
eq(writes[3], { register = "+", value = "325875666703" }, "the normal AWS picker yanks the account id")

custom_picker = nil
plugin[2].keys[1][2]()
assert(custom_picker.opts.actions["ctrl-y"], "the zoxide picker exposes semantic Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "42.5\t/repo/topic" })
eq(writes[4], { register = "+", value = "/repo/topic" }, "the zoxide picker yanks the path without its score")

local original_schedule = vim.schedule
local original_systemlist = vim.fn.systemlist
vim.schedule = function(callback) callback() end
vim.fn.systemlist = function(command)
	if command == "git worktree list" then return { "/repo/topic abc123 [topic]" } end
	return original_systemlist(command)
end

for _, mapping in ipairs(plugin[1].keys) do
	if mapping.desc and mapping.desc:match("^Diffview picker") then mapping[2]() end
end
eq(custom_picker.kind, "commits", "the Diffview selector starts with commits")
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview commits picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "abc1234 subject" })
eq(writes[5], { register = "+", value = "abc1234" }, "the Diffview commits picker yanks the SHA")

custom_picker.opts.actions["ctrl-b"]()
eq(custom_picker.kind, "branches", "the Diffview selector switches to branches")
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview branches picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "* main abc123 subject" })
eq(writes[6], { register = "+", value = "main" }, "the Diffview branches picker yanks the branch")

custom_picker.opts.actions["ctrl-w"]()
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview worktrees picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ custom_picker.entries[1] })
eq(writes[7], { register = "+", value = "/repo/topic" }, "the Diffview worktrees picker yanks the path")

custom_picker.opts.actions["ctrl-s"]()
eq(custom_picker.kind, "stashes", "the Diffview selector switches to stashes")
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview stash picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "stash@{1}: WIP" })
eq(writes[8], { register = "+", value = "stash@{1}" }, "the Diffview stash picker yanks the ref")

local neoclip
for _, spec in ipairs(plugin) do
	if spec[1] == "AckslD/nvim-neoclip.lua" then neoclip = spec end
end
local neoclip_yank = neoclip and neoclip.opts.keys.fzf.custom["ctrl-y"]
assert(neoclip_yank, "the Neoclip picker exposes a semantic Ctrl-y custom action")
neoclip_yank({ entry = { contents = { "first line", "second line" }, regtype = "V" } })
eq(
	writes[9],
	{ register = "+", value = { "first line", "second line" } },
	"the Neoclip picker preserves multiline yank contents"
)

vim.schedule = original_schedule
vim.fn.systemlist = original_systemlist

vim.fn.setreg = original_setreg
vim.notify = original_notify

print("PASS shared FZF yank decoding, formatting, and close behavior")

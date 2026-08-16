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
	entry_to_file = function(entry, opts, force_uri)
		if entry == "unparseable" then return nil end
		if entry:match("^jdt://") or force_uri and entry:match("^[%a%-]+://") then
			local uri, line, col = entry:match("^(.-):(%d+):(%d+):")
			return { uri = uri or entry, line = tonumber(line) or 0, col = tonumber(col) or 0 }
		end
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

local yank = dofile("lua/config/fzf_yank.lua")
package.loaded["config.fzf_yank"] = yank

eq(yank.clean("  \27[32malpha\194\160 beta\27[0m  "), "alpha beta", "display cleanup strips ANSI and normalizes spacing")
eq(yank.clipboard_text("branch", { "* main abc123 subject", "+ feature/topic def456" }), "main\nfeature/topic", "branch values strip worktree markers")
eq(yank.clipboard_text("commit", { "abc1234 subject", "abc1234 duplicate", "def5678 other" }), "abc1234\ndef5678", "multi-selection is deduplicated and newline separated")
eq(yank.clipboard_text("stash", { "stash@{2}: On main: WIP" }), "stash@{2}", "stash rows copy only the ref")
eq(yank.clipboard_text("worktree", { "/repo/topic abc123 [topic]" }), "/repo/topic", "worktree rows copy only their path")
eq(
	yank.clipboard_text("worktree", { "/repo/topic with spaces abc123 [topic]" }),
	"/repo/topic with spaces",
	"worktree paths preserve spaces"
)
eq(yank.clipboard_text("command", { "write" }), ":write", "commands retain their Ex prefix")
eq(yank.clipboard_text("command", { "lua  print('x')" }), ":lua  print('x')", "commands preserve meaningful internal whitespace")
eq(yank.clipboard_text("zoxide", { "42.5\twork/topic" }, {}, { base_dir = "/Users/test" }), "/Users/test/work/topic", "zoxide rows omit their score and restore an absolute path")
eq(
	yank.clipboard_text("aws_account", { "prod  •  325875666703  •  AWSAdministratorAccess" }),
	"325875666703",
	"AWS rows copy only the account id"
)
eq(
	yank.clipboard_text("git_status", { 'R  "old file.lua" -> "new file.lua"' }),
	vim.fs.normalize(vim.fn.getcwd() .. "/new file.lua"),
	"Git status copies the absolute destination path"
)
eq(
	yank.clipboard_text("git_status", { "●\194\160●\194\160\194\160src/main.lua" }, { cwd = vim.fn.getcwd() }),
	vim.fs.normalize(vim.fn.getcwd() .. "/src/main.lua"),
	"transformed Git status rows omit icon metadata and resolve absolutely"
)
eq(
	yank.clipboard_text("location", { "lua/mod.lua:42:7:matched text" }, { cwd = vim.fn.getcwd() }),
	vim.fs.normalize(vim.fn.getcwd() .. "/lua/mod.lua") .. ":42:7",
	"locations retain absolute path, line, and column"
)
eq(
	yank.clipboard_text("path", { "/repo/src/main.lua" }, {}, { reference_dir = "/repo" }),
	"/repo/src/main.lua",
	"paths inside an explicit reference directory stay absolute"
)
eq(
	yank.clipboard_text("path", { "/other/main.lua" }, {}, { reference_dir = "/repo" }),
	"/other/main.lua",
	"paths outside an explicit reference directory stay absolute"
)
eq(
	yank.clipboard_text("path", { "$LITERAL_NAME/file#%.lua" }, { cwd = "/repo" }),
	"/repo/$LITERAL_NAME/file#%.lua",
	"path resolution preserves literal expansion metacharacters"
)
eq(
	yank.clipboard_text("location", { "file:///repo/src/main.lua:8:3:match" }, { _uri = true }),
	"/repo/src/main.lua:8:3",
	"file URIs become absolute file locations"
)
eq(
	yank.clipboard_text("location", { "jdt://contents/java/lang/String.class:9:2:match" }, { _uri = true }),
	"jdt://contents/java/lang/String.class:9:2",
	"non-file URIs remain URI locations"
)
eq(
	yank.clipboard_text("display", { "row-a", "row-b" }, {}, {
		resolve = function(entry) return ({ ["row-a"] = "first", ["row-b"] = "second" })[entry] end,
		separator = "\n\n",
	}),
	"first\n\nsecond",
	"custom resolvers can preserve payload separators"
)
eq(
	yank.clipboard_text("display", { " x " }, {}, {
		preserve_whitespace = true,
		resolve = function(entry) return entry end,
	}),
	" x ",
	"exact history resolvers preserve short queries and surrounding whitespace"
)
eq(
	yank.insert_text("path", { "alpha.lua", "beta.lua" }, { cwd = "/repo" }),
	"/repo/alpha.lua /repo/beta.lua ",
	"prompt insertion retains a separate space separator and one trailing space"
)
eq(yank.clipboard_text("display", {}), nil, "empty selections do not produce clipboard text")
eq(yank.clipboard_text("location", { "unparseable" }), nil, "unparseable location rows fail closed")

local original_z = vim.fn.getreg("z", 1, true)
local original_z_type = vim.fn.getregtype("z")
local original_a = vim.fn.getreg("a", 1, true)
local original_a_type = vim.fn.getregtype("a")
local original_b = vim.fn.getreg("b", 1, true)
local original_b_type = vim.fn.getregtype("b")
vim.fn.setreg("z", { "first  line", "second line" }, "V")
vim.fn.setreg("a", "alpha  value", "v")
vim.fn.setreg("b", { "beta", "line" }, "V")
eq(yank.clipboard_text("register", { "[z] [l] preview" }), "first  line\nsecond line\n", "register rows preserve their contents")

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
eq(writes, { { register = "+", value = vim.fs.normalize(vim.fn.getcwd() .. "/lua/mod.lua") .. ":42:7" } }, "the yank action writes an absolute semantic location")
eq(#notifications, 1, "a successful yank reports one notification")

local typed_writes = {}
vim.fn.setreg = function(register, value, regtype)
	table.insert(typed_writes, { register = register, value = value, regtype = regtype })
end
yank.action("register")({ "[z] [l] preview" }, {})
eq(
	typed_writes,
	{ { register = "+", value = { "first  line", "second line" }, regtype = "V" } },
	"a single register yank preserves contents and register type"
)
typed_writes = {}
yank.action("register")({ "[a] [c] preview", "[b] [l] preview" }, {})
eq(
	typed_writes,
	{
		{
			register = "+",
			value = "Register a\nalpha  value\n\nRegister b\nbeta\nline\n",
			regtype = "V",
		},
	},
	"multiple registers become labeled linewise blocks without flattening their contents"
)
vim.fn.setreg = function(register, value)
	table.insert(writes, { register = register, value = value })
end

action({}, {})
eq(#writes, 1, "empty selections leave the clipboard untouched")
eq(#notifications, 3, "empty selections do not notify")

package.loaded["fzf-lua.actions"] = {
	resume = function() error("Ctrl-y must not resume") end,
}
local plugin = dofile("lua/plugins/fzf-lua.lua")
local opts = plugin[1].opts()
assert(not opts.defaults or not opts.defaults.actions or not opts.defaults.actions["ctrl-y"], "arbitrary FZF rows do not inherit an ambiguous Ctrl-y")
assert(opts.actions.files["ctrl-y"], "file-like providers inherit semantic location yanks")
assert(opts.actions.buffers["ctrl-y"], "buffer providers inherit semantic path yanks")
assert(opts.git.status.actions["ctrl-y"], "Git status exposes semantic path yanks")
assert(opts.git.worktrees.actions["ctrl-y"], "Git worktrees expose semantic path yanks")
assert(opts.commands.actions["ctrl-y"], "commands expose executable yanks")
assert(opts.command_history.actions["ctrl-y"], "command history exposes executable yanks")
assert(opts.registers.actions["ctrl-y"], "registers expose content yanks")

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
eq(writes[2], { register = "+", value = "325875666703" }, "the normal AWS picker yanks the account id")

custom_picker = nil
plugin[2].keys[1][2]()
assert(custom_picker.opts.actions["ctrl-y"], "the zoxide picker exposes semantic Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "42.5\t/repo/topic" })
eq(writes[3], { register = "+", value = "/repo/topic" }, "the zoxide picker yanks the path without its score")

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
eq(writes[4], { register = "+", value = "abc1234" }, "the Diffview commits picker yanks the SHA")

custom_picker.opts.actions["ctrl-b"]()
eq(custom_picker.kind, "branches", "the Diffview selector switches to branches")
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview branches picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "* main abc123 subject" })
eq(writes[5], { register = "+", value = "main" }, "the Diffview branches picker yanks the branch")

custom_picker.opts.actions["ctrl-w"]()
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview worktrees picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ custom_picker.entries[1] })
eq(writes[6], { register = "+", value = "/repo/topic" }, "the Diffview worktrees picker yanks the path")

custom_picker.opts.actions["ctrl-s"]()
eq(custom_picker.kind, "stashes", "the Diffview selector switches to stashes")
assert(custom_picker.opts.actions["ctrl-y"], "the Diffview stash picker exposes Ctrl-y")
custom_picker.opts.actions["ctrl-y"]({ "stash@{1}: WIP" })
eq(writes[7], { register = "+", value = "stash@{1}" }, "the Diffview stash picker yanks the ref")

local neoclip
for _, spec in ipairs(plugin) do
	if spec[1] == "AckslD/nvim-neoclip.lua" then neoclip = spec end
end
local neoclip_yank = neoclip and neoclip.opts.keys.fzf.custom["ctrl-y"]
assert(neoclip_yank, "the Neoclip picker exposes a semantic Ctrl-y custom action")
neoclip_yank({ entry = { contents = { "first line", "second line" }, regtype = "V" } })
eq(
	writes[8],
	{ register = "+", value = { "first line", "second line" } },
	"the Neoclip picker preserves multiline yank contents"
)

opts.actions.buffers["ctrl-y"]({ "lua/mod.lua:21:4:text" }, { cwd = vim.fn.getcwd() })
eq(
	writes[9],
	{ register = "+", value = vim.fs.normalize(vim.fn.getcwd() .. "/lua/mod.lua") .. ":21:4" },
	"buffer-derived line and tab providers preserve source positions"
)

vim.schedule = original_schedule
vim.fn.systemlist = original_systemlist

vim.fn.setreg = original_setreg
vim.fn.setreg("z", original_z, original_z_type)
vim.fn.setreg("a", original_a, original_a_type)
vim.fn.setreg("b", original_b, original_b_type)
vim.notify = original_notify

print("PASS shared FZF yank decoding, formatting, and close behavior")

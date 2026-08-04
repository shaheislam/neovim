package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local original_schedule = vim.schedule
local original_defer_fn = vim.defer_fn
local original_notify = vim.notify
local original_getcwd = vim.fn.getcwd
local original_tempname = vim.fn.tempname
local original_mkdir = vim.fn.mkdir
local original_writefile = vim.fn.writefile
local original_delete = vim.fn.delete
local original_executable = vim.fn.executable
local original_fs_find = vim.fs.find
local original_system = vim.system

vim.schedule = function(callback) callback() end
vim.defer_fn = function(callback) callback() end

local notifications = {}
vim.notify = function(message, level)
	table.insert(notifications, { message = message, level = level })
end

local cwd = "/alias/repo/main"
vim.fn.getcwd = function() return cwd end
local temp_index = 0
vim.fn.tempname = function()
	temp_index = temp_index + 1
	return "/virtual/opencode-scope-" .. temp_index
end
vim.fn.mkdir = function() return 1 end
vim.fn.writefile = function() return 0 end
vim.fn.delete = function() return 0 end
vim.fn.executable = function() return 0 end
vim.fs.find = function(name)
	assert(name == ".git", "scope context only searches for .git")
	return { "/repo/main/.git" }
end

local git_should_fail = false
vim.system = function(args, _, callback)
	assert(vim.deep_equal(args, { "git", "-C", "/repo/main", "worktree", "list", "--porcelain" }), "Git scope uses stable launch root")
	if git_should_fail then
		callback({ code = 1, stdout = "", stderr = "failed" })
	else
		callback({
			code = 0,
			stdout = "worktree /alias/repo/main\nHEAD aaa\n\nworktree /alias/repo/linked\nHEAD bbb\n",
			stderr = "",
		})
	end
	return {}
end

local aliases = {
	["/alias/repo/main"] = "/repo/main",
	["/alias/repo/linked"] = "/repo/linked",
}
local http_calls = {}
package.loaded["config.opencode_http"] = {
	canonical = function(path)
		return aliases[path] or (path and path:gsub("/+$", ""))
	end,
	post = function(path, body, callback, opts)
		table.insert(http_calls, { kind = "post", path = path, body = body, opts = opts })
		callback(true, "")
	end,
	publish_command = function(command, callback, opts)
		table.insert(http_calls, { kind = "publish", command = command, opts = opts })
		callback(true, "")
	end,
	publish_commands = function(commands, callback, opts)
		table.insert(http_calls, { kind = "publish_commands", commands = commands, opts = opts })
		callback(true, "")
	end,
}

local sessions = {
	{
		id = "local",
		title = "Local exact",
		directory = "/alias/repo/main/",
		projectID = "project-1",
		project = { id = "project-1", name = "sessions", worktree = "/repo/main" },
		time = { updated = 60 },
	},
	{ id = "child", title = "Current worktree child", directory = "/repo/main/subdir", time = { updated = 50 } },
	{ id = "linked", title = "Linked worktree", directory = "/alias/repo/linked/feature", time = { updated = 40 } },
	{ id = "prefix", title = "Prefix collision", directory = "/repo/main-other", time = { updated = 30 } },
	{ id = "foreign", title = "Foreign project", directory = "/other/project", time = { updated = 20 } },
	{ id = "missing", title = "Missing directory", time = { updated = 10 } },
}

local api_calls = {}
local deferred_message_callbacks = {}
local defer_messages = false
local messages = {
	{
		info = { id = "message-1", role = "user", time = { created = 1000 } },
		parts = { { id = "part-1", type = "text", text = "scope payload" } },
	},
}
package.loaded["config.opencode_messages"] = {
	sessions = function(callback, opts)
		table.insert(api_calls, { kind = "sessions", opts = vim.deepcopy(opts) })
		callback(vim.deepcopy(sessions))
	end,
	latest_session = function(callback) callback(vim.deepcopy(sessions[1])) end,
	messages = function(session_id, callback, opts)
		table.insert(api_calls, { kind = "messages", id = session_id, opts = vim.deepcopy(opts) })
		if defer_messages then
			table.insert(deferred_message_callbacks, callback)
			return
		end
		callback(vim.deepcopy(messages))
	end,
	notify_error = function(err) error(err or "unexpected OpenCode API error") end,
}

local picker_calls = {}
local grep_calls = {}
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, opts)
		table.insert(picker_calls, { entries = vim.deepcopy(entries), opts = opts })
	end,
	live_grep = function(opts)
		table.insert(grep_calls, { opts = opts })
	end,
}
package.loaded["fzf-lua.utils"] = { strip_ansi_coloring = function(value) return value end }
package.loaded["fzf-lua.path"] = {
	entry_to_file = function()
		return { path = "/virtual/opencode-grep/000001.md" }
	end,
}

local function entry_named(picker, name)
	for _, entry in ipairs(picker.entries) do
		if entry:find(name, 1, true) then return entry end
	end
	error("missing picker entry: " .. name)
end

local function api_call_count(kind)
	local count = 0
	for _, call in ipairs(api_calls) do
		if call.kind == kind then count = count + 1 end
	end
	return count
end

local opencode = dofile("lua/config/opencode_pickers.lua")
opencode.sessions("all", { session_scope = "local" })
local local_picker = picker_calls[1]
eq(#local_picker.entries, 1, "Local scope matches the canonical launch cwd exactly")
assert(local_picker.entries[1]:find("Local exact", 1, true), "Local scope keeps its exact session")
assert(local_picker.entries[1]:find("sessions", 1, true), "session rows include compact project context")
assert(local_picker.entries[1]:find("/alias/repo/main/", 1, true), "session rows include directory context")
eq(local_picker.opts.prompt, "OpenCode Sessions (Local)> ", "session prompt shows active Local scope")
eq(api_calls[1].opts.catalog, "global", "scoped session picker requests the shared global catalog")
eq(api_calls[1].opts.dir, "/repo/main", "catalog request uses the stable launch route")
assert(local_picker.opts.actions["alt-g"] and local_picker.opts.actions["alt-s"] and local_picker.opts.actions["alt-l"], "session picker exposes direct location actions")

local_picker.opts.actions["alt-g"]({}, { last_query = "typed query", __call_opts = { query = "stale query" } })
local global_picker = picker_calls[2]
eq(#global_picker.entries, 6, "Global scope includes every catalog session")
eq(global_picker.opts.query, "typed query", "scope relaunch prefers fzf-lua's live last_query")
eq(global_picker.opts.prompt, "OpenCode Sessions (Global)> ", "session prompt shows active Global scope")

global_picker.opts.actions["alt-s"]({}, { last_query = "repo query" })
local repo_picker = picker_calls[3]
eq(#repo_picker.entries, 3, "Git scope includes the current and linked worktrees only")
assert(entry_named(repo_picker, "Local exact"), "Git scope includes the launch worktree")
assert(entry_named(repo_picker, "Current worktree child"), "Git scope includes descendants")
assert(entry_named(repo_picker, "Linked worktree"), "Git scope includes linked worktrees")
eq(repo_picker.opts.query, "repo query", "Git scope preserves the current query")
eq(repo_picker.opts.prompt, "OpenCode Sessions (Git)> ", "session prompt shows active Git scope")

git_should_fail = true
repo_picker.opts.actions["alt-s"]({}, { last_query = "keep me" })
local retained_picker = picker_calls[4]
eq(retained_picker.opts.prompt, "OpenCode Sessions (Git)> ", "failed worktree discovery retains the prior scope")
eq(retained_picker.opts.query, "keep me", "failed worktree discovery retains the query")
assert(notifications[#notifications].message:match("Global"), "failed Git discovery never silently widens to Global")
git_should_fail = false

cwd = "/changed/after/launch"
global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Foreign project") })
eq(#http_calls, 0, "foreign sessions cannot switch the live TUI")
assert(notifications[#notifications].message:match("outside"), "foreign live switch explains the route rejection")

global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Current worktree child") })
eq(http_calls[1].path, "/tui/select-session", "current-worktree sessions may switch the live TUI")
eq(http_calls[1].opts.dir, "/repo/main", "live switch remains pinned after cwd changes")

local_picker.opts.actions.default({ local_picker.entries[1] })
local message_picker = picker_calls[#picker_calls]
message_picker.opts.actions["ctrl-l"]({ message_picker.entries[1] })
eq(http_calls[2].opts.dir, "/repo/main", "timeline session selection uses the stable route")
eq(http_calls[3].opts.dir, "/repo/main", "timeline opening uses the stable route")
eq(http_calls[4].opts.dir, "/repo/main", "timeline navigation uses the stable route")

sessions = { { id = "only-foreign", title = "Only foreign", directory = "/elsewhere", time = { updated = 1 } } }
cwd = "/alias/repo/main"
opencode.sessions("all", { session_scope = "local" })
local empty_picker = picker_calls[#picker_calls]
eq(empty_picker.entries, {}, "an empty Local scope still opens a picker")
assert(empty_picker.opts.actions["alt-g"], "an empty scope can widen to Global")

sessions = {}
for index = 1, 10 do
	table.insert(sessions, {
		id = "grep-" .. index,
		title = "Grep " .. index,
		directory = "/repo/main",
		time = { updated = 20 - index },
	})
end
cwd = "/alias/repo/main"
api_calls = {}
grep_calls = {}
deferred_message_callbacks = {}
defer_messages = true
opencode.grep({ scope = "global", query = "bounded" })
eq(api_call_count("messages"), 8, "global grep starts at most eight concurrent message requests")
eq(#grep_calls, 0, "global grep waits for every message request before opening")
table.remove(deferred_message_callbacks, 1)(vim.deepcopy(messages))
eq(api_call_count("messages"), 9, "a grep completion starts exactly one queued request")
while #deferred_message_callbacks > 0 do
	table.remove(deferred_message_callbacks, 1)(vim.deepcopy(messages))
end
eq(api_call_count("messages"), 10, "global grep eventually fetches every filtered session")
eq(#grep_calls, 1, "global grep opens once after its bounded queue drains")
defer_messages = false

sessions = {
	{ id = "grep-local", title = "Grep local", directory = "/repo/main", time = { updated = 2 } },
	{ id = "grep-foreign", title = "Grep foreign", directory = "/other/project", time = { updated = 1 } },
}
cwd = "/alias/repo/main"
api_calls = {}
grep_calls = {}
opencode.grep({ scope = "global", query = "start" })
eq(#grep_calls, 1, "global grep opens its picker")
local grep_picker = grep_calls[1]
local grep_catalog_call = api_calls[#api_calls - 2]
eq(grep_catalog_call.kind, "sessions", "global grep requests a session catalog before messages")
eq(grep_catalog_call.opts and grep_catalog_call.opts.catalog, "global", "global grep shares the complete global catalog")
eq(grep_catalog_call.opts and grep_catalog_call.opts.dir, "/repo/main", "global grep pins catalog routing to its launch context")

cwd = "/changed/after/grep-launch"
local before_grep_switch = #http_calls
grep_picker.opts.actions["ctrl-l"]({ "000001.md:1:payload" })
eq(#http_calls, before_grep_switch + 1, "grep can switch a session in the launch worktree")
eq(http_calls[#http_calls].opts.dir, "/repo/main", "grep live switching remains on the stable launch route")

grep_picker.opts.actions["alt-g"]({}, { last_query = "live grep query", __call_opts = { query = "stale grep query" } })
eq(grep_calls[#grep_calls].opts.query, "live grep query", "grep scope relaunch prefers the live fzf query")

vim.schedule = original_schedule
vim.defer_fn = original_defer_fn
vim.notify = original_notify
vim.fn.getcwd = original_getcwd
vim.fn.tempname = original_tempname
vim.fn.mkdir = original_mkdir
vim.fn.writefile = original_writefile
vim.fn.delete = original_delete
vim.fn.executable = original_executable
vim.fs.find = original_fs_find
vim.system = original_system

print("PASS OpenCode session picker scopes canonical paths and guards stable live routes")

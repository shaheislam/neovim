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
local original_confirm = vim.fn.confirm
local original_fs_find = vim.fs.find
local original_system = vim.system
local original_fs_stat = vim.uv.fs_stat

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
local confirm_result = 1
local confirmations = {}
vim.fn.confirm = function(message, choices, default)
	table.insert(confirmations, { message = message, choices = choices, default = default })
	return confirm_result
end
vim.fs.find = function(name)
	assert(name == ".git", "scope context only searches for .git")
	return { "/repo/main/.git" }
end

local git_should_fail = false
local linked_registered = true
local live_waits = 0
vim.system = function(args, _, callback)
	assert(vim.deep_equal(args, { "git", "-C", "/repo/main", "worktree", "list", "--porcelain" }), "Git scope uses stable launch root")
	local result
	if git_should_fail then
		result = { code = 1, stdout = "", stderr = "failed" }
	else
		local lines = {
			"worktree /alias/repo/main",
			"HEAD aaa",
			"",
		}
		if linked_registered then
			vim.list_extend(lines, {
				"worktree /alias/repo/linked",
				"HEAD bbb",
				"",
			})
		end
		vim.list_extend(lines, {
			"worktree /repo/prunable",
			"HEAD ccc",
			"prunable gitdir file points to non-existent location",
			"",
		})
		result = {
			code = 0,
			stdout = table.concat(lines, "\n"),
			stderr = "",
		}
	end
	if callback then
		callback(result)
	end
	return {
		wait = function(_, timeout)
			assert(timeout and timeout > 0, "live authorization bounds Git worktree discovery")
			live_waits = live_waits + 1
			return result
		end,
	}
end

local aliases = {
	["/alias/repo/main"] = "/repo/main",
	["/alias/repo/linked"] = "/repo/linked",
}
local existing_directories = {
	["/repo/main"] = true,
	["/repo/main/subdir"] = true,
	["/repo/linked/feature"] = true,
	["/repo/main-other"] = true,
	["/other/project"] = true,
	["/repo/removed"] = true,
	["/repo/prunable"] = true,
	["/repo/file"] = "file",
}
vim.uv.fs_stat = function(path)
	local kind = existing_directories[path]
	return kind and { type = kind == true and "directory" or kind } or nil
end
package.loaded["config.opencode_http"] = {
	canonical = function(path)
		return aliases[path] or (path and path:gsub("/+$", ""))
	end,
}
local restart_calls = {}
package.loaded["config.opencode_terminal"] = {
	restart_owned = function(dir, launch_context)
		table.insert(restart_calls, { dir = dir, launch_context = vim.deepcopy(launch_context) })
		return { ok = true, term = { id = #restart_calls }, owner_retired = true }
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
	{ id = "removed", title = "Removed worktree", directory = "/repo/removed", time = { updated = 19 } },
	{ id = "prunable", title = "Prunable worktree", directory = "/repo/prunable", time = { updated = 18 } },
	{ id = "deleted", title = "Deleted directory", directory = "/repo/deleted", time = { updated = 17 } },
	{ id = "file", title = "File path", directory = "/repo/file", time = { updated = 16 } },
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
local original_fzf_config = package.loaded["fzf-lua.config"]
package.loaded["fzf-lua.config"] = { globals = { winopts = {} } }
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
eq(#global_picker.entries, 10, "Global scope includes every catalog session")
eq(global_picker.opts.query, "typed query", "scope relaunch prefers fzf-lua's live last_query")
eq(global_picker.opts.prompt, "OpenCode Sessions (Global)> ", "session prompt shows active Global scope")

local before_linked_switch = #restart_calls
global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Linked worktree") })
eq(#restart_calls, before_linked_switch + 1, "Global history can restart into an active linked-worktree session")
eq(restart_calls[#restart_calls], {
	dir = "/repo/main",
	launch_context = { session_id = "linked" },
}, "linked-worktree restart targets only the stable initiating terminal")
eq(confirmations[#confirmations].default, 2, "session restart confirmation defaults to Cancel")
assert(confirmations[#confirmations].message:match("unsent"), "restart confirmation warns about unsent composer text")

for _, blocked in ipairs({ "Prefix collision", "Foreign project", "Removed worktree", "Prunable worktree", "Deleted directory", "File path", "Missing directory" }) do
	local before = #restart_calls
	local confirms_before = #confirmations
	global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, blocked) })
	eq(#restart_calls, before, blocked .. " cannot restart the owned TUI")
	eq(#confirmations, confirms_before, blocked .. " is rejected before confirmation")
	local rejection = notifications[#notifications].message
	if blocked == "Deleted directory" or blocked == "File path" then
		assert(rejection:match("unavailable"), blocked .. " reports an unavailable session directory")
	elseif blocked == "Missing directory" then
		assert(rejection:match("no directory"), "missing session metadata reports the absent directory")
	else
		assert(rejection:match("repository"), blocked .. " reports failed repository membership")
	end
end

git_should_fail = true
local before_unverified = #restart_calls
global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Linked worktree") })
eq(#restart_calls, before_unverified, "linked sessions fail closed when Git membership cannot be verified")
assert(notifications[#notifications].message:match("verify"), "failed linked-worktree verification is explicit")
git_should_fail = false

confirm_result = 2
local before_cancelled_restart = #restart_calls
global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Current worktree child") })
eq(#restart_calls, before_cancelled_restart, "cancelling confirmation leaves the owned terminal untouched")
confirm_result = 1

global_picker.opts.actions["alt-s"]({}, { last_query = "repo query" })
local repo_picker = picker_calls[3]
eq(#repo_picker.entries, 3, "Git scope includes the current and linked worktrees only")
assert(entry_named(repo_picker, "Local exact"), "Git scope includes the launch worktree")
assert(entry_named(repo_picker, "Current worktree child"), "Git scope includes descendants")
assert(entry_named(repo_picker, "Linked worktree"), "Git scope includes linked worktrees")
eq(repo_picker.opts.query, "repo query", "Git scope preserves the current query")
eq(repo_picker.opts.prompt, "OpenCode Sessions (Git)> ", "session prompt shows active Git scope")

linked_registered = false
local before_stale_cache = #restart_calls
local waits_before_stale_cache = live_waits
global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Linked worktree") })
eq(#restart_calls, before_stale_cache, "an unregistered linked worktree is rejected even after scope discovery cached it")
eq(live_waits, waits_before_stale_cache + 1, "linked authorization refreshes Git membership instead of trusting cached roots")
assert(notifications[#notifications].message:match("active worktree"), "stale linked membership explains the rejection")
linked_registered = true

git_should_fail = true
repo_picker.opts.actions["alt-s"]({}, { last_query = "keep me" })
local retained_picker = picker_calls[4]
eq(retained_picker.opts.prompt, "OpenCode Sessions (Git)> ", "failed worktree discovery retains the prior scope")
eq(retained_picker.opts.query, "keep me", "failed worktree discovery retains the query")
assert(notifications[#notifications].message:match("Global"), "failed Git discovery never silently widens to Global")
git_should_fail = false

cwd = "/changed/after/launch"
global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Foreign project") })
eq(#restart_calls, before_unverified, "foreign sessions cannot restart the owned TUI")
assert(notifications[#notifications].message:match("repository"), "foreign live switch explains the repository rejection")

global_picker.opts.actions["ctrl-o"]({ entry_named(global_picker, "Current worktree child") })
eq(restart_calls[#restart_calls], {
	dir = "/repo/main",
	launch_context = { session_id = "child" },
}, "current-worktree restart remains pinned after cwd changes")

global_picker.opts.actions.default({ entry_named(global_picker, "Linked worktree") })
local message_picker = picker_calls[#picker_calls]
local before_message_restart = #restart_calls
message_picker.opts.actions["ctrl-l"]({ message_picker.entries[1] })
eq(#restart_calls, before_message_restart + 1, "message restart replaces only one owned terminal")
eq(restart_calls[#restart_calls], {
	dir = "/repo/main",
	launch_context = { session_id = "linked" },
}, "message restart is session-level and uses the stable route")
assert(not message_picker.opts.fzf_opts["--header"]:match("timeline"), "message picker makes no exact timeline claim")

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
	{ id = "grep-linked", title = "Grep linked", directory = "/repo/linked/feature", time = { updated = 2 } },
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
assert(type(grep_picker.opts.winopts.on_create) == "function", "OpenCode grep configures terminal key routing")
local grep_buf = vim.api.nvim_create_buf(false, true)
grep_picker.opts.winopts.on_create({ bufnr = grep_buf, winid = 37 })
local grep_ctrl_l_map
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(grep_buf, "t")) do
	if mapping.lhs == "<C-L>" then
		grep_ctrl_l_map = mapping
		break
	end
end
assert(grep_ctrl_l_map, "OpenCode grep shadows the global terminal Ctrl-l mapping")
eq(grep_ctrl_l_map.rhs, "<C-L>", "OpenCode grep sends literal Ctrl-l to fzf")
vim.api.nvim_buf_delete(grep_buf, { force = true })

cwd = "/changed/after/grep-launch"
local before_grep_switch = #restart_calls
grep_picker.opts.actions["ctrl-l"]({ "000001.md:1:payload" })
eq(#restart_calls, before_grep_switch + 1, "grep can restart into a session in an active linked worktree")
eq(restart_calls[#restart_calls], {
	dir = "/repo/main",
	launch_context = { session_id = "grep-linked" },
}, "grep restart remains on the stable launch route")

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
vim.fn.confirm = original_confirm
vim.fs.find = original_fs_find
vim.system = original_system
vim.uv.fs_stat = original_fs_stat
package.loaded["fzf-lua.config"] = original_fzf_config

print("PASS OpenCode session picker scopes canonical paths and guards stable live routes")

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local original_schedule = vim.schedule
local original_defer_fn = vim.defer_fn
local original_getcwd = vim.fn.getcwd
local original_tempname = vim.fn.tempname
local original_mkdir = vim.fn.mkdir
local original_writefile = vim.fn.writefile
local original_delete = vim.fn.delete
local original_executable = vim.fn.executable
local original_confirm = vim.fn.confirm
local original_fs_find = vim.fs.find
local original_fs_stat = vim.uv.fs_stat
local original_ui_input = vim.ui.input

vim.schedule = function(callback) callback() end
vim.defer_fn = function(callback) callback() end

local cwd = "/repo/original"
vim.fn.getcwd = function() return cwd end
vim.fs.find = function(name, opts)
	assert(name == ".git", "fork picker context only searches for .git")
	return { opts.path .. "/.git" }
end
vim.uv.fs_stat = function(path)
	if path == "/repo/original" or path == "/repo/changed" then
		return { type = "directory" }
	end
	return nil
end

local temp_index = 0
vim.fn.tempname = function()
	temp_index = temp_index + 1
	return "/virtual/opencode-fork-" .. temp_index
end
vim.fn.mkdir = function() return 1 end
vim.fn.writefile = function() return 0 end
vim.fn.delete = function() return 0 end
vim.fn.executable = function() return 0 end
vim.fn.confirm = function(_, _, default)
	eq(default, 2, "fork picker restart confirmation defaults to Cancel")
	return 1
end

local pickers = {}
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, opts)
		table.insert(pickers, { entries = vim.deepcopy(entries), opts = opts })
	end,
}
package.loaded["fzf-lua.utils"] = { strip_ansi_coloring = function(value) return value end }
package.loaded["fzf-lua.config"] = { globals = { winopts = {} } }

package.loaded["config.opencode_http"] = {
	canonical = function(path) return path and path:gsub("/+$", "") end,
}
local restart_calls = {}
package.loaded["config.opencode_terminal"] = {
	restart_owned = function(dir, launch_context)
		table.insert(restart_calls, { dir = dir, launch_context = vim.deepcopy(launch_context) })
		return { ok = true, term = { id = #restart_calls }, owner_retired = true }
	end,
}

local latest_calls = {}
local message_calls = {}
package.loaded["config.opencode_messages"] = {
	latest_session = function(callback, opts)
		table.insert(latest_calls, { callback = callback, opts = vim.deepcopy(opts) })
	end,
	messages = function(session_id, callback, opts)
		table.insert(message_calls, { id = session_id, callback = callback, opts = vim.deepcopy(opts) })
	end,
	notify_error = function(err) error(err or "unexpected OpenCode API error") end,
}

local session = {
	id = "session-fork",
	title = "Stable fork route",
	directory = "/repo/original",
	time = { updated = 2 },
}
local messages = {
	{
		info = { id = "message-fork", role = "user", time = { created = 1 } },
		parts = { { id = "part-fork", type = "text", text = "Choose this fork point" } },
	},
}

local opencode = dofile("lua/config/opencode_pickers.lua")

opencode.forkpane()
eq(latest_calls[1].opts.dir, "/repo/original", "forkpane pins latest-session retrieval at invocation")
cwd = "/repo/changed"
latest_calls[1].callback(vim.deepcopy(session))
eq(message_calls[1].opts.dir, "/repo/original", "forkpane routes message retrieval through the selected session")
message_calls[1].callback(vim.deepcopy(messages))
local forkpane_picker = pickers[1]
forkpane_picker.opts.actions["ctrl-l"]({ forkpane_picker.entries[1] })
eq(restart_calls[1], {
	dir = "/repo/original",
	launch_context = { session_id = "session-fork" },
}, "forkpane restart retains the invocation route after cwd changes")

local input_callback
vim.ui.input = function(_, callback) input_callback = callback end
cwd = "/repo/original"
opencode.gwtfork()
assert(input_callback, "gwtfork opens its branch prompt")
cwd = "/repo/changed"
input_callback("feature/stable-route")
eq(latest_calls[2].opts.dir, "/repo/original", "gwtfork uses the route captured before prompting")
latest_calls[2].callback(vim.deepcopy(session))
eq(message_calls[2].opts.dir, "/repo/original", "gwtfork routes message retrieval through the selected session")
message_calls[2].callback(vim.deepcopy(messages))
local gwtfork_picker = pickers[2]
local before_gwt_live = #restart_calls
gwtfork_picker.opts.actions["ctrl-l"]({ gwtfork_picker.entries[1] })
eq(restart_calls[before_gwt_live + 1], {
	dir = "/repo/original",
	launch_context = { session_id = "session-fork" },
}, "gwtfork restart retains the pre-prompt route")

vim.schedule = original_schedule
vim.defer_fn = original_defer_fn
vim.fn.getcwd = original_getcwd
vim.fn.tempname = original_tempname
vim.fn.mkdir = original_mkdir
vim.fn.writefile = original_writefile
vim.fn.delete = original_delete
vim.fn.executable = original_executable
vim.fn.confirm = original_confirm
vim.fs.find = original_fs_find
vim.uv.fs_stat = original_fs_stat
vim.ui.input = original_ui_input

print("PASS OpenCode fork pickers retain their invocation route")

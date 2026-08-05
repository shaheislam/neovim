package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local scheduled = {}
local original_schedule = vim.schedule
local original_defer_fn = vim.defer_fn
local original_getcwd = vim.fn.getcwd
local original_fs_find = vim.fs.find
local original_system = vim.system
local original_fs_stat = vim.uv.fs_stat
vim.schedule = function(callback)
	table.insert(scheduled, callback)
end
vim.defer_fn = function(callback) callback() end
vim.fn.getcwd = function() return "/repo" end
vim.fs.find = function(name)
	assert(name == ".git", "prompt picker context only searches for .git")
	return { "/repo/.git" }
end
vim.system = function(args, _, callback)
	assert(vim.deep_equal(args, { "git", "-C", "/repo", "worktree", "list", "--porcelain" }), "prompt live navigation checks the launch repository")
	local result = {
		code = 0,
		stdout = "worktree /repo\nHEAD aaa\n\nworktree /repo-linked\nHEAD bbb\n",
		stderr = "",
	}
	if callback then
		callback(result)
	end
	return {
		wait = function(_, timeout)
			assert(timeout and timeout > 0, "prompt live navigation bounds Git discovery")
			return result
		end,
	}
end
vim.uv.fs_stat = function(path)
	if path == "/repo" or path == "/repo-linked" or path == "/foreign/repo" then
		return { type = "directory" }
	end
	return nil
end

local pickers = {}
local inherited_on_create
package.loaded["fzf-lua"] = {
	fzf_exec = function(entries, opts)
		table.insert(pickers, { entries = entries, opts = opts })
	end,
}
local original_fzf_config = package.loaded["fzf-lua.config"]
package.loaded["fzf-lua.config"] = {
	globals = {
		winopts = {
			on_create = function(event) inherited_on_create = event end,
		},
	},
}
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value) return value end,
}

local session = {
	id = "session-1",
	title = "Prompt picker work",
	agent = "build",
	directory = "/repo",
	time = { created = 1000, updated = 2000 },
}
local messages = {
	{
		info = { id = "message-1", role = "user", time = { created = 3000 } },
		parts = {
			{ id = "part-1", type = "text", text = "Implement the picker lifecycle" },
		},
	},
}
package.loaded["config.opencode_messages"] = {
	latest_session = function(callback) callback(session) end,
	sessions = function(callback) callback({ session }) end,
	messages = function(_, callback) callback(messages) end,
	notify_error = function(err) error(err or "unexpected OpenCode API error") end,
}

local http_calls = {}
package.loaded["config.opencode_http"] = {
	canonical = function(path) return path and path:gsub("/+$", "") end,
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

local inserted = {}
local restored = 0
local prompt = {
	owner = {
		insert = function(text) table.insert(inserted, text) end,
		restore = function() restored = restored + 1 end,
	},
}

local opencode = dofile("lua/config/opencode_pickers.lua")
opencode.all({ prompt = prompt })
eq(#pickers, 1, "prompt mode opens the message picker")
local message_picker = pickers[1]
assert(message_picker.opts.actions.enter, "prompt message picker exposes insertion Enter")
assert(message_picker.opts.actions["ctrl-l"], "prompt message picker exposes live timeline navigation")
assert(message_picker.opts.actions["alt-s"], "prompt message picker retains safe scope navigation")
assert(message_picker.opts.actions["ctrl-s"], "prompt message picker retains safe session navigation")
assert(not message_picker.opts.actions.default, "prompt message picker removes its normal open action")
assert(not message_picker.opts.actions["ctrl-f"], "prompt message picker removes forking actions")
assert(not message_picker.opts.actions["ctrl-w"], "prompt message picker removes worktree actions")
assert(message_picker.opts.fzf_opts["--header"]:match("C%-l: live"), "prompt message picker advertises live navigation")
assert(type(message_picker.opts.winopts.on_create) == "function", "message picker configures terminal key routing")
local picker_buf = vim.api.nvim_create_buf(false, true)
local picker_event = { bufnr = picker_buf, winid = 37 }
message_picker.opts.winopts.on_create(picker_event)
eq(inherited_on_create, picker_event, "message picker preserves the global fzf on_create behavior")
local ctrl_l_map
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(picker_buf, "t")) do
	if mapping.lhs == "<C-L>" then
		ctrl_l_map = mapping
		break
	end
end
assert(ctrl_l_map, "message picker shadows the global terminal Ctrl-l mapping")
eq(ctrl_l_map.rhs, "<C-L>", "message picker sends literal Ctrl-l to fzf")
eq(ctrl_l_map.noremap, 1, "message picker passthrough cannot recurse into terminal navigation")
eq(ctrl_l_map.buffer, picker_buf, "message picker Ctrl-l passthrough is buffer-local")
vim.api.nvim_buf_delete(picker_buf, { force = true })

message_picker.opts.winopts.on_close()
eq(#scheduled, 1, "message picker defers prompt restoration until action dispatch")
message_picker.opts.actions.enter({ message_picker.entries[1] })
eq(#inserted, 1, "message Enter inserts into the prompt owner")
assert(inserted[1]:match("Implement the picker lifecycle"), "inserted text contains the selected message payload")
assert(not inserted[1]:find("\n", 1, true), "message payload is flattened for prompt insertion")
assert(inserted[1]:match(" $"), "message payload ends in one continuation space")
scheduled[1]()
eq(restored, 0, "selection suppresses the deferred cancellation restore")

pickers = {}
scheduled = {}
http_calls = {}
session.directory = "/repo-linked"
opencode.all({ prompt = prompt })
local live_picker = pickers[1]
live_picker.opts.winopts.on_close()
live_picker.opts.actions["ctrl-l"]({ live_picker.entries[1] })
eq(#inserted, 1, "live navigation does not insert the selected message")
eq(http_calls[1], {
	kind = "post",
	path = "/tui/select-session",
	body = { sessionID = "session-1" },
	opts = { dir = "/repo" },
}, "live navigation selects the target session on the stable route")
eq(http_calls[2], {
	kind = "publish",
	command = "session.timeline",
	opts = { dir = "/repo" },
}, "live navigation opens the target session timeline")
eq(http_calls[3], {
	kind = "publish_commands",
	commands = { "dialog.select.home" },
	opts = { dir = "/repo" },
}, "live navigation selects the target conversation turn")
scheduled[1]()
eq(restored, 0, "accepted live navigation keeps the old prompt owner closed")

pickers = {}
scheduled = {}
session.directory = "/foreign/repo"
opencode.all({ prompt = prompt })
local foreign_picker = pickers[1]
local calls_before_rejection = #http_calls
foreign_picker.opts.winopts.on_close()
foreign_picker.opts.actions["ctrl-l"]({ foreign_picker.entries[1] })
eq(#http_calls, calls_before_rejection, "foreign live navigation fails before publishing commands")
scheduled[1]()
eq(restored, 1, "rejected live navigation restores the prompt owner")

pickers = {}
scheduled = {}
session.directory = "/repo-deleted"
opencode.all({ prompt = prompt })
local deleted_picker = pickers[1]
calls_before_rejection = #http_calls
deleted_picker.opts.winopts.on_close()
deleted_picker.opts.actions["ctrl-l"]({ deleted_picker.entries[1] })
eq(#http_calls, calls_before_rejection, "deleted live navigation fails before publishing commands")
scheduled[1]()
eq(restored, 2, "deleted live navigation restores the prompt owner exactly once")
session.directory = "/repo"
restored = 0

pickers = {}
scheduled = {}
opencode.sessions("all", { prompt = prompt })
eq(#pickers, 1, "prompt mode opens the session picker")
local session_picker = pickers[1]
assert(session_picker.opts.actions.enter, "prompt session picker exposes navigation Enter")
assert(session_picker.opts.actions["alt-g"], "prompt session picker can widen to Global")
assert(session_picker.opts.actions["alt-s"], "prompt session picker can switch to Git")
assert(session_picker.opts.actions["alt-l"], "prompt session picker can return to Local")
assert(not session_picker.opts.actions["ctrl-o"], "prompt session picker excludes live switching")
session_picker.opts.winopts.on_close()
session_picker.opts.actions.enter({ session_picker.entries[1] })
eq(#scheduled, 2, "session transition queues close restoration before the next picker")
scheduled[1]()
eq(restored, 0, "a session-to-message transition suppresses intermediate restoration")
scheduled[2]()
eq(#pickers, 2, "selecting a session opens its message picker")
local nested_picker = pickers[2]
nested_picker.opts.winopts.on_close()
scheduled[3]()
eq(restored, 1, "cancelling the terminal nested picker restores the prompt exactly once")

vim.schedule = original_schedule
vim.defer_fn = original_defer_fn
vim.fn.getcwd = original_getcwd
vim.fs.find = original_fs_find
vim.system = original_system
vim.uv.fs_stat = original_fs_stat
package.loaded["fzf-lua.config"] = original_fzf_config

print("PASS OpenCode prompt pickers insert payloads and preserve nested lifecycle")

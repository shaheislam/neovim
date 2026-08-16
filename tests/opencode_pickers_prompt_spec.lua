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
local original_confirm = vim.fn.confirm
local original_fs_find = vim.fs.find
local original_system = vim.system
local original_fs_stat = vim.uv.fs_stat
vim.schedule = function(callback)
	table.insert(scheduled, callback)
end
vim.defer_fn = function(callback) callback() end
vim.fn.getcwd = function() return "/repo" end
local confirm_result = 1
local confirm_calls = 0
vim.fn.confirm = function(message, choices, default)
	confirm_calls = confirm_calls + 1
	assert(message:match("unsent"), "prompt restart warns that unsent composer text will be lost")
	eq(choices, "&Restart\n&Cancel", "prompt restart offers explicit Restart and Cancel choices")
	eq(default, 2, "prompt restart defaults to Cancel")
	return confirm_result
end
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

package.loaded["config.opencode_http"] = {
	canonical = function(path) return path and path:gsub("/+$", "") end,
}
local restart_calls = {}
local restart_outcome = { ok = true, term = { id = 1 }, owner_retired = true }
package.loaded["config.opencode_terminal"] = {
	restart_owned = function(dir, launch_context)
		table.insert(restart_calls, { dir = dir, launch_context = vim.deepcopy(launch_context) })
		return vim.deepcopy(restart_outcome)
	end,
}

local inserted = {}
local restored = 0
local clipboard = {}
local original_setreg = vim.fn.setreg
local original_notify = vim.notify
vim.fn.setreg = function(register, value)
	if register == "+" then
		table.insert(clipboard, value)
		return
	end
	return original_setreg(register, value)
end
vim.notify = function() end
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
assert(message_picker.opts.actions["ctrl-y"], "prompt message picker exposes payload yank")
assert(message_picker.opts.actions["ctrl-l"], "prompt message picker exposes owned-session restart")
assert(message_picker.opts.actions["alt-s"], "prompt message picker retains safe scope navigation")
assert(message_picker.opts.actions["ctrl-s"], "prompt message picker retains safe session navigation")
assert(not message_picker.opts.actions.default, "prompt message picker removes its normal open action")
assert(not message_picker.opts.actions["ctrl-f"], "prompt message picker removes forking actions")
assert(not message_picker.opts.actions["ctrl-w"], "prompt message picker removes worktree actions")
assert(message_picker.opts.fzf_opts["--header"]:match("C%-l: restart"), "prompt message picker advertises session restart")
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
clipboard = {}
opencode.all({ prompt = prompt })
local yank_picker = pickers[1]
yank_picker.opts.winopts.on_close()
yank_picker.opts.actions["ctrl-y"]({ yank_picker.entries[1] })
assert(clipboard[1]:match("Implement the picker lifecycle"), "message Ctrl-y copies the selected payload")
eq(#inserted, 1, "message Ctrl-y does not insert into the prompt")
scheduled[1]()
eq(restored, 1, "message Ctrl-y closes and restores the prompt owner")
restored = 0

pickers = {}
scheduled = {}
restart_calls = {}
session.directory = "/repo-linked"
opencode.all({ prompt = prompt })
local live_picker = pickers[1]
live_picker.opts.winopts.on_close()
live_picker.opts.actions["ctrl-l"]({ live_picker.entries[1] })
scheduled[1]()
eq(restored, 0, "pending restart suppresses the automatic close restoration")
scheduled[2]()
eq(#inserted, 1, "session restart does not insert the selected message")
eq(restart_calls[1], {
	dir = "/repo",
	launch_context = { session_id = "session-1" },
}, "prompt restart replaces only the exact initiating terminal on its stable route")
eq(restored, 0, "accepted session restart keeps the old prompt owner closed")

pickers = {}
scheduled = {}
confirm_result = 2
opencode.all({ prompt = prompt })
local cancelled_picker = pickers[1]
cancelled_picker.opts.winopts.on_close()
cancelled_picker.opts.actions["ctrl-l"]({ cancelled_picker.entries[1] })
scheduled[1]()
scheduled[2]()
eq(#restart_calls, 1, "cancelled prompt restart never mutates the owned terminal")
eq(restored, 1, "cancelled prompt restart restores the old prompt owner exactly once")
confirm_result = 1

pickers = {}
scheduled = {}
restart_outcome = { ok = false, error = "preflight failed", owner_retired = false }
opencode.all({ prompt = prompt })
local preflight_picker = pickers[1]
preflight_picker.opts.winopts.on_close()
preflight_picker.opts.actions["ctrl-l"]({ preflight_picker.entries[1] })
scheduled[1]()
scheduled[2]()
eq(restored, 2, "pre-retirement restart failure restores the still-valid prompt owner")

pickers = {}
scheduled = {}
restart_outcome = { ok = false, error = "spawn failed", owner_retired = true }
opencode.all({ prompt = prompt })
local retired_picker = pickers[1]
retired_picker.opts.winopts.on_close()
retired_picker.opts.actions["ctrl-l"]({ retired_picker.entries[1] })
scheduled[1]()
scheduled[2]()
eq(restored, 2, "post-retirement failure never restores an invalid terminal owner")
restart_outcome = { ok = true, term = { id = 2 }, owner_retired = true }

pickers = {}
scheduled = {}
session.directory = "/foreign/repo"
opencode.all({ prompt = prompt })
local foreign_picker = pickers[1]
local calls_before_rejection = #restart_calls
local confirms_before_rejection = confirm_calls
foreign_picker.opts.winopts.on_close()
foreign_picker.opts.actions["ctrl-l"]({ foreign_picker.entries[1] })
eq(#restart_calls, calls_before_rejection, "foreign restart fails before mutating the owned terminal")
eq(confirm_calls, confirms_before_rejection, "foreign restart is rejected before confirmation")
scheduled[1]()
eq(restored, 3, "rejected restart restores the prompt owner")

pickers = {}
scheduled = {}
session.directory = "/repo-deleted"
opencode.all({ prompt = prompt })
local deleted_picker = pickers[1]
calls_before_rejection = #restart_calls
deleted_picker.opts.winopts.on_close()
deleted_picker.opts.actions["ctrl-l"]({ deleted_picker.entries[1] })
eq(#restart_calls, calls_before_rejection, "deleted restart fails before mutating the owned terminal")
scheduled[1]()
eq(restored, 4, "deleted restart restores the prompt owner exactly once")
session.directory = "/repo"
restored = 0

pickers = {}
scheduled = {}
opencode.sessions("all", { prompt = prompt })
eq(#pickers, 1, "prompt mode opens the session picker")
local session_picker = pickers[1]
assert(session_picker.opts.actions.enter, "prompt session picker exposes navigation Enter")
assert(session_picker.opts.actions["ctrl-y"], "prompt session picker exposes session yank")
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

pickers = {}
scheduled = {}
clipboard = {}
restored = 0
opencode.sessions("all", { prompt = prompt })
session_picker = pickers[1]
session_picker.opts.winopts.on_close()
session_picker.opts.actions["ctrl-y"]({ session_picker.entries[1] })
eq(clipboard, { "session-1" }, "session Ctrl-y copies the stable session id")
scheduled[1]()
eq(restored, 1, "session Ctrl-y closes and restores the prompt owner")

vim.schedule = original_schedule
vim.defer_fn = original_defer_fn
vim.fn.getcwd = original_getcwd
vim.fn.confirm = original_confirm
vim.fs.find = original_fs_find
vim.system = original_system
vim.uv.fs_stat = original_fs_stat
package.loaded["fzf-lua.config"] = original_fzf_config
vim.fn.setreg = original_setreg
vim.notify = original_notify

print("PASS OpenCode prompt pickers insert payloads and preserve nested lifecycle")

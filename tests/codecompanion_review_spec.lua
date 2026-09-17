package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message or (vim.inspect(actual) .. " ~= " .. vim.inspect(expected)))
end

local root = vim.fn.tempname()
assert(vim.fn.mkdir(root, "p") == 1, "failed to create review root")
local candidate = vim.fs.joinpath(root, "candidate.lua")
local generated = vim.fs.joinpath(root, "generated.lua")
assert(vim.fn.writefile({ "return true" }, candidate) == 0, "failed to create candidate")
assert(vim.fn.writefile({ "return false" }, generated) == 0, "failed to create generated fixture")

local commands = {}
local notifications = {}
local scheduled = {}
local cursor_line = 1
local positioned = {}
local set_paths = {}
local ready_callback
local current_view
local owns_review = true
local open_diff_calls = 0
local restore_calls = 0
local review_action_calls = {}
local qf = {
	id = 41,
	idx = 1,
	qfbufnr = 17,
	title = "CodeCompanion Code Review",
	context = {},
	items = {
		{ bufnr = 101, filename = candidate, lnum = 4, user_data = { code_review_hunk = 101 } },
		{ bufnr = 102, filename = generated, lnum = 8, user_data = { code_review_hunk = 102 } },
	},
}

local function future()
	local callbacks = {}
	return {
		done = false,
		is_done = function(self)
			return self.done
		end,
		finally = function(_, callback)
			table.insert(callbacks, callback)
		end,
		settle = function(self)
			self.done = true
			for _, callback in ipairs(callbacks) do
				callback()
			end
		end,
	}
end

local in_flight
local tabpage = vim.api.nvim_get_current_tabpage()
local view = {
	tabpage = tabpage,
	rev_arg = "refs/worktree/codecompanion/baseline",
	adapter = { ctx = { toplevel = root } },
	initialized = false,
	options = {},
	cur_entry = nil,
	emitter = {
		once = function(_, event, callback)
			eq(event, "files_updated", "review waits for Diffview file discovery")
			ready_callback = callback
		end,
	},
	set_file_in_flight = function()
		return in_flight
	end,
	set_file_by_path = function(self, path, focus, highlight)
		table.insert(set_paths, { path, focus, highlight })
		self.cur_entry = { path = path }
		in_flight = in_flight and not in_flight.done and in_flight or future()
		return in_flight
	end,
	cur_layout = {
		get_main_win = function()
			return { id = 88 }
		end,
	},
}

local original_cmd = vim.cmd
local original_getqflist = vim.fn.getqflist
local original_setqflist = vim.fn.setqflist
local original_notify = vim.notify
local original_schedule = vim.schedule
local original_defer_fn = vim.defer_fn
local original_get_cursor = vim.api.nvim_win_get_cursor
local original_set_cursor = vim.api.nvim_win_set_cursor
local original_win_call = vim.api.nvim_win_call
local original_win_valid = vim.api.nvim_win_is_valid

vim.cmd = function(command)
	command = type(command) == "string" and command or tostring(command)
	table.insert(commands, command)
	if vim.startswith(command, "DiffviewOpen ") then
		current_view = view
	end
end
vim.fn.getqflist = function()
	return vim.deepcopy(qf)
end
vim.fn.setqflist = function(_, action, opts)
	eq(action, "r", "review cleanup replaces the current list")
	qf.items = vim.deepcopy(opts.items)
	return 0
end
vim.notify = function(message)
	table.insert(notifications, message)
end
vim.schedule = function(callback)
	table.insert(scheduled, callback)
end
vim.defer_fn = function(callback)
	table.insert(scheduled, callback)
end
vim.api.nvim_win_get_cursor = function()
	return { cursor_line, 0 }
end
vim.api.nvim_win_set_cursor = function(win, cursor)
	table.insert(positioned, { win = win, line = cursor[1] })
end
vim.api.nvim_win_call = function(_, callback)
	return callback()
end
vim.api.nvim_win_is_valid = function()
	return true
end

package.loaded["diffview.lib"] = {
	get_current_view = function()
		return current_view
	end,
}
package.loaded["codecompanion.interactions.code_review.keymaps"] = {
	owns_quickfix = function()
		return owns_review
	end,
	restore = function()
		restore_calls = restore_calls + 1
	end,
}
package.loaded["codecompanion.interactions.code_review"] = {
	open_diff = function()
		open_diff_calls = open_diff_calls + 1
	end,
	comment = function()
		table.insert(review_action_calls, "comment")
	end,
	accept = function()
		table.remove(qf.items, cursor_line)
	end,
	ignore = function()
		table.remove(qf.items, cursor_line)
	end,
}

local review = require("git.codecompanion_review")
local baseline = "refs/worktree/codecompanion/baseline"
review.provider({ root = root, path = "candidate.lua", baseline_ref = baseline, line = 4, id = 101 })

eq(commands[1], "cclose", "first diff closes the source quickfix window")
assert(vim.startswith(commands[2], "DiffviewOpen -C" .. vim.fn.fnameescape(root)), "Diffview uses the review root")
assert(commands[2]:find(vim.fn.fnameescape(candidate), 1, true), "selected file is absolute")
assert(not commands[2]:find("selected%-row"), "selected row is deferred so Diffview cannot steal focus")
eq(commands[#commands - 2], "copen 10", "quickfix is reopened beneath Diffview")
eq(commands[#commands - 1], "wincmd J", "quickfix is docked at the bottom")
eq(commands[#commands], "resize 10", "quickfix keeps its review height")
assert(type(ready_callback) == "function", "new Diffview waits for files_updated")
eq(set_paths, {}, "first open does not search an empty Diffview file list")

view.initialized = true
ready_callback("files_updated", {})
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(set_paths[#set_paths], { "candidate.lua", false, true }, "ready Diffview selects the requested file")
in_flight:settle()
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(positioned[#positioned], { win = 88, line = 4 }, "settled Diffview lands on the review line")

in_flight = future()
view.cur_entry = { path = "candidate.lua" }
review.provider({ root = root, path = "generated.lua", baseline_ref = baseline, line = 8, id = 102 })
review.provider({ root = root, path = "candidate.lua", baseline_ref = baseline, line = 6, id = 101 })
eq(set_paths[#set_paths], { "candidate.lua", false, true }, "A-B-A navigation queues the latest path")
in_flight:settle()
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(positioned[#positioned], { win = 88, line = 6 }, "A-B-A navigation lands on the latest line")

cursor_line = 2
eq(review.follow_current({ immediate = true }), true, "review quickfix entries are handled")
eq(open_diff_calls, 1, "review navigation invokes the upstream diff action")
qf.items[2].user_data = nil
eq(review.follow_current({ immediate = true }), true, "quicker context rows are handled without opening files")
eq(open_diff_calls, 1, "context rows keep the current Diffview target")
local context_items = vim.deepcopy(qf.items)
review.run("comment")
eq(review_action_calls, {}, "review actions ignore quicker context rows")
review.resync_after("accept")
eq(qf.items, context_items, "review actions ignore quicker context rows")
qf.items[1].user_data = nil
eq(review.follow_current({ immediate = true }), false, "same-ID ordinary lists are not treated as reviews")
eq(restore_calls, 1, "ordinary navigation restores stale review mappings")
owns_review = true
local ordinary_items = vim.deepcopy(qf.items)
review.run("comment")
eq(qf.items, ordinary_items, "stale comment mappings preserve same-ID ordinary lists")
eq(review_action_calls, {}, "stale comment mappings do not invoke CodeCompanion")
eq(restore_calls, 2, "stale review actions restore the displaced mappings")
owns_review = true
qf.items[1].user_data = { code_review_hunk = 101 }
owns_review = false
eq(review.follow_current({ immediate = true }), false, "ordinary quickfix lists fall through")
eq(restore_calls, 3, "a new quickfix list restores stale review mappings")
owns_review = true
qf.items[2].user_data = { code_review_hunk = 102 }

cursor_line = 1
review.resync_after("accept")
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(#qf.items, 1, "accept still uses CodeCompanion's review state")
eq(open_diff_calls, 2, "accept follows the nearest remaining hunk")

qf.items = {
	{ bufnr = 102, filename = generated, lnum = 7, valid = 0, user_data = { lnum = 7 } },
	{ bufnr = 102, filename = generated, lnum = 8, valid = 1, user_data = { code_review_hunk = 102 } },
	{ bufnr = 102, filename = generated, lnum = 9, valid = 0, user_data = { lnum = 9 } },
}
qf.context = { quicker = { num_before = 2, num_after = 2 } }
cursor_line = 2
review.resync_after("accept")
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(qf.items, {}, "accepting the final expanded hunk removes orphan context rows")
eq(restore_calls, 4, "finishing an expanded review restores the quickfix mappings")

qf.items = {
	{ bufnr = 102, filename = generated, lnum = 8, user_data = { code_review_hunk = 102 } },
}
qf.context = {}
cursor_line = 1
review.resync_after("accept")
qf.items = {
	{ bufnr = 101, filename = candidate, lnum = 1, valid = 1, text = "ordinary" },
}
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(#qf.items, 1, "scheduled cleanup preserves a same-ID ordinary replacement")
eq(qf.items[1].text, "ordinary", "ordinary replacement content is untouched")
eq(restore_calls, 5, "ordinary replacement still restores stale review mappings")

qf.items = {
	{ bufnr = 102, filename = generated, lnum = 8, user_data = { code_review_hunk = 102 } },
}
cursor_line = 1
review.resync_after("accept")
while #scheduled > 0 do
	table.remove(scheduled, 1)()
end
eq(qf.items, {}, "accepting the final plain hunk empties the review")
eq(restore_calls, 6, "finishing a plain review restores the quickfix mappings")

qf.items = {
	{ bufnr = 102, filename = generated, lnum = 8, user_data = { code_review_hunk = 102 } },
}

local original_current_tab = vim.api.nvim_get_current_tabpage
vim.api.nvim_get_current_tabpage = function()
	return -2
end
commands = {}
review.provider({ root = root, path = "generated.lua", baseline_ref = baseline, line = 8, id = 102 })
eq(commands[1], "cclose", "reusing a review from another tab moves quickfix back to its Diffview")
vim.api.nvim_get_current_tabpage = original_current_tab

commands = {}
current_view = nil
view.initialized = false
view.tabpage = -1
ready_callback = nil
local fail_command = true
vim.cmd = function(command)
	command = type(command) == "string" and command or tostring(command)
	table.insert(commands, command)
	if fail_command and vim.startswith(command, "DiffviewOpen ") then
		error("failed diff")
	end
end
local ok = pcall(review.provider, {
	root = root,
	path = "generated.lua",
	baseline_ref = baseline,
	line = 8,
	id = 102,
})
eq(ok, true, "Diffview failures do not escape the provider")
assert(vim.tbl_contains(commands, "copen 10"), "failed Diffview open restores quickfix")
assert(#notifications > 0, "failed Diffview open reports the problem")

vim.cmd = original_cmd
vim.fn.getqflist = original_getqflist
vim.fn.setqflist = original_setqflist
vim.notify = original_notify
vim.schedule = original_schedule
vim.defer_fn = original_defer_fn
vim.api.nvim_win_get_cursor = original_get_cursor
vim.api.nvim_win_set_cursor = original_set_cursor
vim.api.nvim_win_call = original_win_call
vim.api.nvim_win_is_valid = original_win_valid

print("PASS CodeCompanion review keeps Diffview synchronized above quickfix")

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
vim.o.swapfile = false
local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message .. "\nactual: " .. vim.inspect(actual))
end
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.tmp", "p")
root = vim.uv.fs_realpath(root)
assert(vim.system({ "git", "-C", root, "init", "-q" }):wait().code == 0)
vim.fn.writefile({ "first", "second", "third", "fourth" }, root .. "/example.txt")
vim.cmd.edit(root .. "/example.txt")
local buf = vim.api.nvim_get_current_buf()
local provenance = { project = root, sessionID = "ses_review" }
local view = {
	left = { type = 2, commit = "HEAD" },
	right = { type = 1 },
	adapter = { ctx = { toplevel = root } },
	opencode_review = { base = "HEAD", provenance = provenance, automatic = true },
	cur_layout = {
		windows = {
			{}, -- A Diffview window can still be loading its file.
			{ file = { bufnr = buf, path = "example.txt", symbol = "b", adapter = { ctx = { toplevel = root } } } },
		},
	},
}
package.loaded["diffview.lib"] = {
	views = { view },
	tabpage_to_view = function()
		return view
	end,
}
local sent, stale = {}, false
package.loaded["config.agent_session"] = {
	resolve = function(route)
		return not stale and vim.deep_equal(route, provenance) and { directory = root, sessionID = route.sessionID }
			or nil
	end,
	submit = function(route, prompt, callback)
		sent[#sent + 1] = { route = route, prompt = prompt }
		callback("queued")
		return true
	end,
}
vim.notify = function() end
local annotations = require("config.annotations")
local function notes()
	return vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
end
local function input(text)
	vim.ui.input = function(_, callback)
		callback(text)
	end
end
input("Immediate feedback")
annotations.add_current()
eq(#sent, 1, "ordinary annotation saving still submits immediately")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
input("Draft feedback")
annotations.add_current({ draft = true })
eq(#sent, 1, "draft saving does not submit")
assert(notes()[2].draft and notes()[2].id, "drafts persist their stable point identity")
local first_id = notes()[2].id
annotations.list(root)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
input("Edited draft")
vim.fn.maparg("e", "n", false, true).callback()
eq(#sent, 1, "editing a draft in the panel does not submit")
eq(notes()[2].id, first_id, "editing a draft preserves its point identity")
vim.fn.maparg("q", "n", false, true).callback()
vim.api.nvim_buf_set_mark(buf, "<", 3, 0, {})
vim.api.nvim_buf_set_mark(buf, ">", 4, 0, {})
input("Range feedback")
annotations.add_visual({ draft = true })
eq(notes()[3].end_line, 4, "drafts retain selected ranges")

local confirmation
vim.ui.select = function(_, opts, callback)
	confirmation = opts.prompt
	callback(nil)
end
annotations.send_drafts(root)
assert(
	confirmation:find("2", 1, true) and confirmation:find("ses_review", 1, true),
	"confirmation identifies pending count and exact recipient"
)
eq(#sent, 1, "cancelling a batch sends nothing")
eq(notes()[2].round, nil, "cancelled drafts are not assigned a review round")
vim.ui.select = function(items, _, callback)
	callback(items[1])
end
annotations.send_drafts(root)
eq(#sent, 2, "one confirmed batch produces one prompt")
assert(sent[2].prompt:find("Review round 1 · point 1", 1, true), "batch prompt includes numbered points")
assert(sent[2].prompt:find("Range feedback", 1, true), "batch contains every draft")
assert(not sent[2].prompt:find("Immediate feedback", 1, true), "batch excludes previously sent unresolved notes")
eq(notes()[2].draft, false, "accepted delivery removes a note from the draft queue")
eq(notes()[2].id, first_id, "batch submission preserves point identity")
eq(notes()[3].point, 2, "batch points are numbered in stored order")
annotations.send_drafts(root)
eq(#sent, 2, "sending again does not duplicate accepted drafts")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
input("Next round")
annotations.add_current({ draft = true })
vim.ui.select = function(items, _, callback)
	stale = true
	callback(items[1])
end
annotations.send_drafts(root)
eq(#sent, 2, "a route switch during confirmation cannot redirect delivery")
assert(notes()[4].draft, "stale delivery leaves the draft available")
stale = false
vim.ui.select = function(items, _, callback)
	callback(items[1])
end
annotations.send_drafts(root)
eq(notes()[4].round, 2, "retry preserves the next round number")

vim.api.nvim_win_set_cursor(0, { 1, 0 })
input("Failed batch")
annotations.add_current({ draft = true })
stale = true
annotations.send_drafts(root)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
input("Added after failure")
annotations.add_current({ draft = true })
stale = false
annotations.send_drafts(root)
eq(notes()[5].round, notes()[6].round, "changed batch membership receives one coherent round")
eq(notes()[5].point, 1, "changed batch points restart in stored order")
eq(notes()[6].point, 2, "changed batch points are unique")

vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "changed" })
annotations.refresh_buffer(buf)
local marks =
	vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("repo_annotations"), 0, -1, { details = true })
assert(
	vim.iter(marks):any(function(mark)
		return vim.inspect(mark[4].virt_text):find("outdated", 1, true)
	end),
	"inline comments flag changed source without removing the note"
)
annotations.list(root)
vim.fn.maparg("r", "n", false, true).callback()
assert(notes()[1].text:match("^RESOLVED:"), "handled action preserves the existing resolution convention")
annotations.list(root, "all")
assert(vim.api.nvim_get_current_line():find("handled", 1, true), "handled notes remain accessible in the all filter")
vim.fn.maparg("A", "n", false, true).callback()
assert(not sent[#sent].prompt:find("Immediate feedback", 1, true), "send all excludes handled notes in the all filter")
vim.fn.maparg("r", "n", false, true).callback()
eq(notes()[1].text, "Immediate feedback", "handled notes can be reopened")
vim.fn.maparg("q", "n", false, true).callback()
annotations.list(root, "drafts")
assert(vim.bo.filetype == "annotate", "empty draft filter stays open for filter navigation")
vim.fn.maparg("f", "n", false, true).callback()
assert(vim.api.nvim_get_current_line():find("Immediate feedback", 1, true), "empty filter can return to all notes")
vim.fn.maparg("q", "n", false, true).callback()
input("Unsent bulk draft")
annotations.add_current({ draft = true })
annotations.list(root)
local before_bulk = #sent
vim.fn.maparg("A", "n", false, true).callback()
eq(#sent, before_bulk + 1, "panel bulk sending still submits non-draft feedback")
assert(not sent[#sent].prompt:find("Unsent bulk draft", 1, true), "panel bulk sending excludes pending drafts")
vim.fn.maparg("q", "n", false, true).callback()
annotations.ask_all()
eq(#sent, before_bulk + 2, "askall still submits non-draft feedback")
assert(not sent[#sent].prompt:find("Unsent bulk draft", 1, true), "askall excludes pending drafts")
assert(notes()[#notes()].draft, "bulk sends leave drafts available for confirmed submission")
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(root, "rf")
print("PASS review drafts, confirmed rounds, stale routing, freshness and handled notes")

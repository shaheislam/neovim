package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local review_context = require("config.review_context")

local diff = table.concat({
	"diff --git a/lua/example.lua b/lua/example.lua",
	"--- a/lua/example.lua",
	"+++ b/lua/example.lua",
	"@@ -8,5 +8,6 @@ local function run()",
	" local value = load_value()",
	"-return value",
	"+if not value then",
	"+  return nil",
	"+end",
	" return value",
	"@@ -30,2 +31,2 @@ local function other()",
	"-old_call()",
	"+new_call()",
}, "\n")

assert_equal(
	review_context.hunk_for_range(diff, 10, 10),
	table.concat({
		"@@ -8,5 +8,6 @@ local function run()",
		" local value = load_value()",
		"-return value",
		"+if not value then",
		"+  return nil",
		"+end",
		" return value",
	}, "\n"),
	"selects the diff hunk containing the annotated new-file line"
)

assert_equal(review_context.hunk_for_range(diff, 25, 25), nil, "does not attach an unrelated hunk")

assert_equal(
	review_context.hunk_for_range(diff, 30, 30, "old"),
	table.concat({
		"@@ -30,2 +31,2 @@ local function other()",
		"-old_call()",
		"+new_call()",
	}, "\n"),
	"selects a hunk by old-file line when annotating the left Diffview pane"
)

local multi_file_diff = diff
	.. "\n"
	.. table.concat({
		"diff --git a/lua/second.lua b/lua/second.lua",
		"--- a/lua/second.lua",
		"+++ b/lua/second.lua",
		"@@ -1 +1 @@",
		"-before",
		"+after",
	}, "\n")
assert_equal(review_context.hunk_for_range(multi_file_diff, 20, 20), nil, "does not return a hunk from another file")

package.loaded["diffview.lib"] = {
	get_current_view = function()
		return nil
	end,
	views = {
		[1] = {
			cur_layout = {
				windows = {
					{ id = 101, file = { bufnr = 11, symbol = "a" } },
					{ id = 102, file = { bufnr = 12, symbol = "b" } },
				},
			},
		},
	},
}
local annotations = require("config.annotations")
assert_equal(annotations.diff_side(11, 101), "old", "identifies the left Diffview pane")
assert_equal(annotations.diff_side(12, 102), "new", "identifies the right Diffview pane")
assert_equal(annotations.diff_side(12, 101), "new", "refreshing another buffer does not inherit the focused pane's side")

local old_annotation = { file = "lua/example.lua", line = 30, end_line = 31, side = "old" }
assert(review_context.item_matches(old_annotation, "lua/example.lua", 30, "old"), "old annotation appears on old pane")
assert(not review_context.item_matches(old_annotation, "lua/example.lua", 30, "new"), "old annotation stays off new pane")

local prompt = review_context.prompt_for_items({
	{
		file = "lua/example.lua",
		line = 10,
		end_line = 11,
		text = "Handle the missing value explicitly",
		hunk = review_context.hunk_for_range(diff, 10, 10),
	},
}, "mark resolved")

assert(prompt:find("lua/example.lua:10%-11: Handle the missing value explicitly"), "prompt includes location and comment")
assert(prompt:find("```diff", 1, true), "prompt includes a diff fence")
assert(prompt:find("+if not value then", 1, true), "prompt includes changed code")
assert(prompt:find("mark resolved", 1, true), "prompt includes the resolution instruction")

local original_prompt_module = package.loaded["config.opencode_prompt"]
local original_notify = vim.notify
vim.notify = function() end

local sink_calls = {}
package.loaded["config.opencode_prompt"] = {
	append = function(text, opts)
		table.insert(sink_calls, { text = text, opts = opts })
	end,
}
package.loaded["config.annotations"] = nil
local annotations = require("config.annotations")

local root = vim.fn.tempname()
assert(vim.fn.mkdir(root .. "/.git", "p") == 1, "failed to create temporary annotation repo marker")
assert(vim.fn.mkdir(root .. "/.tmp", "p") == 1, "failed to create temporary annotation dir")
assert(vim.fn.writefile(vim.split(vim.json.encode({
	{ file = "lua/example.lua", line = 10, end_line = 11, text = "Handle the missing value explicitly" },
}), "\n"), root .. "/.tmp/annotations.json") == 0, "failed to write temporary annotations")

local annotation_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(annotation_buf, root .. "/lua/example.lua")
vim.api.nvim_set_current_buf(annotation_buf)
vim.api.nvim_buf_set_lines(annotation_buf, 0, -1, false, { "local value = load_value()" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })

annotations.ask_all()

assert_equal(#sink_calls, 1, "annotation ask routes through the local composer facade, not HTTP broadcast")
assert(sink_calls[1].text:find("Handle the missing value explicitly", 1, true), "routed prompt includes the annotation text")
assert_equal(sink_calls[1].opts.dir, root, "targets the OpenCode terminal for the reviewed repo")

local original_input = vim.ui.input
local panel_notes = {
	{ file = "lua/example.lua", line = 1, side = "new", text = "Shared feedback" },
	{ file = "lua/example.lua", line = 1, side = "old", text = "Shared feedback" },
}
vim.fn.writefile({ vim.json.encode(panel_notes) }, root .. "/.tmp/annotations.json")
annotations.list()
vim.ui.input = function(_, callback)
	callback("Edited in panel")
end
vim.fn.maparg("e", "n", false, true).callback()
assert(vim.api.nvim_get_current_line():find("Edited in panel", 1, true), "editing refreshes the existing panel")
vim.fn.writefile({ vim.json.encode(panel_notes) }, root .. "/.tmp/annotations.json")
annotations.list(root)
vim.fn.maparg("d", "n", false, true).callback()
local remaining = vim.json.decode(table.concat(vim.fn.readfile(root .. "/.tmp/annotations.json"), "\n"))
assert_equal(#remaining, 1, "deleting a comment does not remove identical feedback on the opposite side")
assert_equal(remaining[1].side, "old", "panel deletion keeps the unselected diff side")
vim.fn.maparg("q", "n", false, true).callback()
vim.ui.input = original_input

vim.api.nvim_buf_delete(annotation_buf, { force = true })
vim.notify = original_notify
package.loaded["config.opencode_prompt"] = original_prompt_module
assert(vim.fn.delete(root, "rf") == 0, "failed to remove temporary annotation root")

print("PASS annotation hunk context")
print("PASS annotation OpenCode directory routing")
print("PASS annotation panel edits and side-specific deletion")

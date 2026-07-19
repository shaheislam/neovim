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

local http = require("config.opencode_http")
local captured_args
local original_system = vim.system
local original_notify = vim.notify
vim.notify = function() end
vim.system = function(args, _, callback)
	captured_args = args
	callback({ code = 0, stdout = "", stderr = "" })
	return {}
end

http.append_prompt("review feedback", { dir = "/tmp/review-root" })
vim.wait(100, function()
	return captured_args ~= nil
end)

vim.system = original_system
vim.notify = original_notify

local directory_header
for index, value in ipairs(captured_args or {}) do
	if value == "--header" then
		local candidate = captured_args[index + 1]
		if candidate and candidate:match("^x%-opencode%-directory:") then
			directory_header = candidate
		end
	end
end
assert_equal(directory_header, "x-opencode-directory: /tmp/review-root", "targets the OpenCode session for the reviewed repo")

print("PASS annotation hunk context")
print("PASS annotation OpenCode directory routing")

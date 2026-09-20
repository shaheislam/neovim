package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function plugin(path)
	local specs = dofile(path)
	return type(specs[1]) == "table" and specs[1] or specs
end

local diffview = require("git.diffview")
local original_cmd = vim.cmd
local commands = {}
vim.cmd = function(command) table.insert(commands, command) end
diffview.open_file(nil, "/tmp/example file.lua")
diffview.open_file("HEAD~2", "/tmp/example file.lua")
diffview.open_file("HEAD|echo injected", "/tmp/example file.lua")
diffview.open_commit("feature|echo injected")
diffview.open_range("base|echo injected", "head|echo injected")
vim.cmd = original_cmd
eq(commands, {
	"DiffviewOpen -- /tmp/example\\ file.lua",
	"DiffviewOpen HEAD~2 -- /tmp/example\\ file.lua",
	"DiffviewOpen " .. vim.fn.fnameescape("HEAD|echo injected") .. " -- /tmp/example\\ file.lua",
	"DiffviewOpen " .. vim.fn.fnameescape("feature|echo injected") .. "^!",
	"DiffviewOpen " .. vim.fn.fnameescape("base|echo injected") .. ".." .. vim.fn.fnameescape("head|echo injected"),
}, "file comparisons use Diffview with an escaped path")

local fugitive = plugin("lua/plugins/git/fugitive.lua")
assert(not vim.tbl_contains(fugitive.cmd, "Gdiffsplit"), "Fugitive no longer exposes Gdiffsplit")
assert(not vim.tbl_contains(fugitive.cmd, "Gvdiffsplit"), "Fugitive no longer exposes Gvdiffsplit")
fugitive.init()
assert(vim.fn.execute("cabbrev gd"):find("DiffviewOpen", 1, true), "gd expands to Diffview")
assert(vim.fn.execute("cabbrev gds"):find("DiffviewOpen --staged", 1, true), "gds expands to staged Diffview")

local original_workflow = package.loaded["git.workflow"]
local original_gitsigns = package.loaded["gitsigns"]
local gitsigns_opts
package.loaded["git.workflow"] = { show_single_commit_info = function() end }
package.loaded["gitsigns"] = setmetatable({ setup = function(opts) gitsigns_opts = opts end }, {
	__index = function() return function() end end,
})
local gitsigns = plugin("lua/plugins/git/gitsigns.lua")
gitsigns.config()
local signs_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(signs_buf, "/tmp/gitsigns-diffview-routing.lua")
local signs_file = vim.api.nvim_buf_get_name(signs_buf)
local signs_maps = {}
local original_keymap_set = vim.keymap.set
vim.keymap.set = function(_, lhs, rhs) signs_maps[lhs] = rhs end
gitsigns_opts.on_attach(signs_buf)
vim.keymap.set = original_keymap_set
package.loaded["git.workflow"] = original_workflow
package.loaded["gitsigns"] = original_gitsigns
local original_input = vim.ui.input
commands = {}
vim.cmd = function(command) table.insert(commands, command) end
vim.ui.input = function(_, callback) callback("HEAD~2") end
signs_maps["<leader>hd"]()
signs_maps["<leader>hD"]()
signs_maps["<leader>hc"]()
vim.cmd = original_cmd
vim.ui.input = original_input
vim.api.nvim_buf_delete(signs_buf, { force = true })
eq(commands, {
	"DiffviewOpen -- " .. signs_file,
	"DiffviewOpen HEAD~ -- " .. signs_file,
	"DiffviewOpen HEAD~2 -- " .. signs_file,
}, "Gitsigns full-file comparisons dispatch to Diffview")

local octo = plugin("lua/plugins/octo.lua")
local octo_diff
for _, key in ipairs(octo.keys) do
	if key[1] == "<leader>gopd" then octo_diff = key end
end
assert(octo_diff and octo_diff.desc == "Open PR in DiffView", "Octo PR diff is owned by Diffview")
local original_octo_diffview = _G.octo_diffview
local octo_calls = 0
_G.octo_diffview = { open_pr_in_diffview = function() octo_calls = octo_calls + 1 end }
octo_diff[2]()
_G.octo_diffview = original_octo_diffview
eq(octo_calls, 1, "Octo PR diff dispatches to the shared Diffview route")
local original_octo = package.loaded.octo
local octo_opts
package.loaded.octo = {
	setup = function(opts)
		octo_opts = opts
		error("stop after setup")
	end,
}
pcall(octo.config)
package.loaded.octo = original_octo
eq(octo_opts.mappings.pull_request.show_pr_diff.lhs, "", "Octo disables its raw PR diff mapping")

local fzf_spec = plugin("lua/plugins/fzf-lua.lua")
local picker
for _, key in ipairs(fzf_spec.keys) do
	if key[1] == "<leader>gD" then picker = key end
end
assert(picker, "FZF exposes the Diffview picker")

local original_fzf = package.loaded["fzf-lua"]
local original_fzf_utils = package.loaded["fzf-lua.utils"]
local original_schedule = vim.schedule
local original_systemlist = vim.fn.systemlist
local original_diffview = package.loaded["git.diffview"]
local picker_calls = {}
local git_calls = {}
local diff_calls = {}
local fake_fzf = {
	git_commits = function(opts) table.insert(picker_calls, { kind = "commits", opts = opts }) end,
	fzf_exec = function(entries, opts) table.insert(picker_calls, { kind = "exec", entries = entries, opts = opts }) end,
}
package.loaded["fzf-lua"] = fake_fzf
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value) return value:gsub("\27%[[%d;]*m", "") end,
}
package.loaded["git.diffview"] = {
	open_commit = function(ref, extra) table.insert(diff_calls, { "commit", ref, extra }) end,
	open_range = function(base, head, extra) table.insert(diff_calls, { "range", base, head, extra }) end,
}
vim.schedule = function(callback) callback() end
vim.fn.systemlist = function(args)
	table.insert(git_calls, args)
	if vim.deep_equal(args, { "git", "worktree", "list", "--porcelain" }) then
		return { "worktree /tmp/worktree with space", "HEAD abc123", "branch refs/heads/branch", "" }
	end
	return { "lua/example.lua" }
end

picker[2]()
picker_calls[#picker_calls].opts.actions["ctrl-w"]()
eq(picker_calls[#picker_calls].entries, { "/tmp/worktree with space" }, "FZF preserves complete porcelain worktree paths")
picker_calls[#picker_calls].opts.actions.default({ "/tmp/worktree with space" })
picker_calls[#picker_calls].opts.actions.default({ "\27[33mabc123\27[0m commit subject" })
picker_calls[#picker_calls].opts.actions.default(nil)
picker_calls[#picker_calls].opts.actions.default({ "lua/example.lua", "lua/other file.lua" })

package.loaded["fzf-lua"] = original_fzf
package.loaded["fzf-lua.utils"] = original_fzf_utils
package.loaded["git.diffview"] = original_diffview
vim.schedule = original_schedule
vim.fn.systemlist = original_systemlist

eq(git_calls, {
	{ "git", "worktree", "list", "--porcelain" },
	{ "git", "-C", "/tmp/worktree with space", "diff-tree", "--no-commit-id", "--name-only", "-r", "abc123" },
}, "FZF file discovery runs in the selected worktree")
eq(diff_calls, {
	{ "commit", "abc123", "-C/tmp/worktree\\ with\\ space -- lua/example.lua lua/other\\ file.lua" },
}, "FZF opens one selected ref as one commit in the selected worktree")

print("PASS full diff workflows route through Diffview")

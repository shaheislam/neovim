package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message or (vim.inspect(actual) .. " ~= " .. vim.inspect(expected)))
end

local function assert_status(result, status, reason)
	eq(type(result), "table", "handoff result must be a table")
	eq(result.status, status, "unexpected handoff status")
	eq(result.reason, reason, "unexpected handoff reason")
end

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

local function external_write(path, lines)
	local before = assert(vim.uv.fs_stat(path), "expected file before external write")
	assert(vim.fn.writefile(lines, path) == 0, "failed to write external file content")
	assert(vim.uv.fs_utime(path, before.atime.sec, before.mtime.sec + 2), "failed to advance file mtime")
end

local function read_lines(path)
	return vim.fn.readfile(path)
end

local root = vim.fn.tempname()
assert(vim.fn.mkdir(root, "p") == 1, "failed to create temporary project")
root = canonical(root)
local plan_path = root .. "/.plan.md"
assert(vim.fn.writefile({ "# Plan", "initial" }, plan_path) == 0, "failed to create plan")

local idle = require("config.diffview_idle")
eq(type(idle.open_diff), "function", "open_diff must be exposed")
eq(type(idle.open_plan), "function", "open_plan must be exposed")

local original_get_mode = vim.api.nvim_get_mode
vim.api.nvim_get_mode = function()
	return { mode = "no", blocking = false }
end
assert_status(idle.open_plan(root), "deferred", "editor_not_normal")
vim.api.nvim_get_mode = original_get_mode

local tabs_before = #vim.api.nvim_list_tabpages()
assert_status(idle.open_plan(root), "opened", "plan_opened")
local plan_buf = vim.api.nvim_get_current_buf()
local plan_tab = vim.api.nvim_get_current_tabpage()
eq(canonical(vim.api.nvim_buf_get_name(plan_buf)), plan_path, "plan buffer uses canonical project plan")
eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "first plan open creates one reusable tab")

assert_status(idle.open_plan(root), "opened", "plan_focused")
eq(vim.api.nvim_get_current_buf(), plan_buf, "second plan open reuses its buffer")
eq(vim.api.nvim_get_current_tabpage(), plan_tab, "second plan open reuses its tab")
eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "second plan open does not create another tab")

local matching_buffers = 0
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_valid(buf) and canonical(vim.api.nvim_buf_get_name(buf)) == plan_path then
		matching_buffers = matching_buffers + 1
	end
end
eq(matching_buffers, 1, "plan open keeps exactly one canonical buffer")

external_write(plan_path, { "# Plan", "external update" })
assert_status(idle.open_plan(root), "opened", "plan_reloaded")
eq(vim.api.nvim_buf_get_lines(plan_buf, 0, -1, false), { "# Plan", "external update" }, "checktime reloads unmodified plan")
eq(vim.bo[plan_buf].modified, false, "external reload remains unmodified")

vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "local draft" })
assert_status(idle.open_plan(root), "opened", "modified_preserved")
eq(vim.api.nvim_buf_get_lines(plan_buf, -2, -1, false), { "local draft" }, "unchanged disk preserves modified plan")
eq(vim.bo[plan_buf].modified, true, "preserved draft remains modified")
vim.cmd("write")

vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "local conflict" })
external_write(plan_path, { "# Plan", "external conflict" })
assert_status(idle.open_plan(root), "refused", "modified_disk_conflict")
eq(vim.b[plan_buf].agent_plan_disk_conflict, true, "disk conflict is marked on the plan buffer")
eq(vim.api.nvim_get_current_buf(), plan_buf, "conflicted plan is still focused")
eq(vim.api.nvim_buf_get_lines(plan_buf, -2, -1, false), { "local conflict" }, "conflicted local content is preserved")

vim.cmd("tabnew")
eq(read_lines(plan_path), { "# Plan", "external conflict" }, "BufLeave does not overwrite a conflicted plan")
eq(vim.bo[plan_buf].modified, true, "BufLeave leaves the conflicted plan modified")

vim.api.nvim_exec_autocmds("FocusLost", { modeline = false })
eq(read_lines(plan_path), { "# Plan", "external conflict" }, "FocusLost does not overwrite a conflicted plan")
eq(vim.bo[plan_buf].modified, true, "FocusLost leaves the conflicted plan modified")

local ordinary_path = root .. "/ordinary.txt"
assert(vim.fn.writefile({ "before" }, ordinary_path) == 0, "failed to create ordinary file")
vim.cmd("edit " .. vim.fn.fnameescape(ordinary_path))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ordinary autosave" })
vim.api.nvim_exec_autocmds("FocusLost", { modeline = false })
eq(read_lines(ordinary_path), { "ordinary autosave" }, "FocusLost still writes ordinary modified buffers")

vim.api.nvim_set_current_tabpage(plan_tab)
vim.cmd("edit!")
eq(vim.b[plan_buf].agent_plan_disk_conflict, nil, "BufReadPost reload clears the conflict flag")
eq(vim.api.nvim_buf_get_lines(plan_buf, 0, -1, false), { "# Plan", "external conflict" }, "reload accepts disk content")

vim.api.nvim_buf_set_lines(plan_buf, -1, -1, false, { "explicit local resolution" })
external_write(plan_path, { "# Plan", "second external conflict" })
assert_status(idle.open_plan(root), "refused", "modified_disk_conflict")
vim.cmd("write!")
eq(vim.b[plan_buf].agent_plan_disk_conflict, nil, "successful BufWritePost clears the conflict flag")
eq(read_lines(plan_path), { "# Plan", "external conflict", "explicit local resolution" }, "forced write records explicit resolution")

local original_system = vim.system
local original_cmd = vim.cmd
local hotreload = require("config.hotreload")
local original_watch_directory = hotreload.watch_directory
local return_target = require("config.return_target")
local original_capture = return_target.capture
local original_diffview_lib = package.loaded["diffview.lib"]
local commands = {}
local system_calls = {}
local lib = { views = {} }

package.loaded["diffview.lib"] = lib
hotreload.watch_directory = function() end
return_target.capture = function()
	return { buf = plan_buf, tab = plan_tab }
end
vim.system = function(args)
	table.insert(system_calls, args)
	local code = args[#args] == "invalid-base^{commit}" and 1 or 0
	return {
		wait = function()
			return { code = code, stdout = "", stderr = "" }
		end,
	}
end
vim.cmd = function(command)
	table.insert(commands, command)
end

assert_status(idle.open_diff(root, "abc123"), "opened", "diff_opened")
eq(commands, { "DiffviewOpen -C" .. vim.fn.fnameescape(root) .. " " .. vim.fn.fnameescape("abc123") }, "Diffview command targets project and base")
eq(system_calls[#system_calls], { "git", "-C", root, "cat-file", "-e", "abc123^{commit}" }, "base is validated as a commit")

commands = {}
assert_status(idle.open_diff(root, "invalid-base"), "refused", "invalid_base")
eq(commands, {}, "invalid base does not open Diffview")

vim.cmd = original_cmd
vim.cmd("tabnew")
local other_tab = vim.api.nvim_get_current_tabpage()
assert(other_tab ~= plan_tab, "expected a non-Diffview tab for focus test")
vim.cmd = function(command)
	table.insert(commands, command)
end

local retargeted_to
local refreshed = 0
local view = {
	tabpage = plan_tab,
	rev_arg = "old-base",
	adapter = { ctx = { toplevel = root } },
	set_revs = function(self, base)
		retargeted_to = base
		self.rev_arg = base
	end,
	update_files = function()
		refreshed = refreshed + 1
	end,
}
lib.views = { view }
commands = {}
assert_status(idle.open_diff(root, "abc123"), "opened", "diff_retargeted")
eq(retargeted_to, "abc123", "same-repo Diffview is retargeted to requested base")
eq(vim.api.nvim_get_current_tabpage(), plan_tab, "retargeted Diffview tab is focused")
eq(commands, {}, "retargeting does not open a duplicate Diffview")

assert_status(idle.open_diff(root, "abc123"), "opened", "diff_refreshed")
eq(refreshed, 1, "matching Diffview range is refreshed")

vim.cmd = original_cmd
vim.system = original_system
hotreload.watch_directory = original_watch_directory
return_target.capture = original_capture
package.loaded["diffview.lib"] = original_diffview_lib

local original_open_diff = idle.open_diff
local original_open_plan = idle.open_plan
local focus_order = {}
idle.open_diff = function(project_dir, base)
	table.insert(focus_order, "diff:" .. project_dir .. ":" .. base)
	return { status = "opened", reason = "diff_opened" }
end
idle.open_plan = function(project_dir)
	table.insert(focus_order, "plan:" .. project_dir)
	return { status = "opened", reason = "plan_focused" }
end

local handoff = idle._open_handoff({ project_dir = root, base = "abc123", open_diff = true })
eq(focus_order, { "diff:" .. root .. ":abc123", "plan:" .. root }, "combined handoff opens Diffview before focusing plan")
assert_status(handoff.diff, "opened", "diff_opened")
assert_status(handoff.plan, "opened", "plan_focused")

idle.open_diff = original_open_diff
idle.open_plan = original_open_plan

assert(vim.fn.delete(root, "rf") == 0, "failed to remove temporary project")

print("PASS exact normal-mode handoff gate")
print("PASS reusable plan tab and disk conflict handling")
print("PASS conflicted plan autosave guards and resolution")
print("PASS Diffview command, range retarget, and handoff focus order")

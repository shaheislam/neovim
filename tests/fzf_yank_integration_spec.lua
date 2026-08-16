package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local lazy_root = vim.fn.stdpath("data") .. "/lazy"
vim.opt.runtimepath:prepend(lazy_root .. "/fzf-lua")

package.loaded["config.fzf_yank"] = dofile("lua/config/fzf_yank.lua")
local fzf = require("fzf-lua")
local plugin = dofile("lua/plugins/fzf-lua.lua")
fzf.setup(plugin[1].opts())

local function resolved_actions(name, opts)
	opts = vim.tbl_extend("force", opts or {}, { _start = false })
	local _, command, resolved = fzf[name](opts)
	assert(command and resolved, name .. " resolves without opening fzf")
	return resolved.actions
end

for _, name in ipairs({ "commands", "registers" }) do
	local actions = resolved_actions(name)
	assert(actions and actions["ctrl-y"], name .. " exposes an explicit semantic Ctrl-y")
end

for _, name in ipairs({ "files", "buffers", "oldfiles", "tabs", "lines", "git_files", "git_status" }) do
	local actions = resolved_actions(name)
	assert(actions and actions["ctrl-y"], name .. " exposes an explicit absolute path/location Ctrl-y")
end

for _, name in ipairs({ "help_tags", "colorschemes" }) do
	local actions = resolved_actions(name)
	assert(not actions or not actions["ctrl-y"], name .. " does not expose an ambiguous display-row Ctrl-y")
end

local _, command, resolved = fzf.fzf_exec({ "generic row" }, { _start = false })
assert(command and resolved, "fzf_exec resolves without opening fzf")
assert(not resolved.actions or not resolved.actions["ctrl-y"], "arbitrary fzf_exec pickers do not inherit an ambiguous Ctrl-y fallback")

local plugin_source = table.concat(vim.fn.readfile("lua/plugins/fzf-lua.lua"), "\n")
assert(not plugin_source:find("#line > 2", 1, true), "search history retains one- and two-character queries")
assert(plugin_source:find('preserve_whitespace = true', 1, true), "search history uses an exact Ctrl-y resolver")

print("PASS pinned fzf-lua applies explicit semantic Ctrl-y actions without a generic fallback")

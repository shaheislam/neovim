package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local lazy_root = vim.fn.stdpath("data") .. "/lazy"
vim.opt.runtimepath:prepend(lazy_root .. "/fzf-lua")

local fzf = require("fzf-lua")
local plugin = dofile("lua/plugins/fzf-lua.lua")
fzf.setup(plugin[1].opts())

local function resolved_actions(name, opts)
	opts = vim.tbl_extend("force", opts or {}, { _start = false })
	local _, command, resolved = fzf[name](opts)
	assert(command and resolved, name .. " resolves without opening fzf")
	return resolved.actions
end

for _, name in ipairs({ "help_tags", "marks", "commands", "registers", "colorschemes" }) do
	local actions = resolved_actions(name)
	assert(actions and actions["ctrl-y"], name .. " inherits Ctrl-y from the configured defaults")
end

local _, command, resolved = fzf.fzf_exec({ "generic row" }, { _start = false })
assert(command and resolved, "fzf_exec resolves without opening fzf")
assert(resolved.actions and resolved.actions["ctrl-y"], "arbitrary fzf_exec pickers inherit the generic Ctrl-y fallback")

print("PASS pinned fzf-lua applies Ctrl-y defaults to standard and custom providers")

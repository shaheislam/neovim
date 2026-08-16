package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local lazy_root = vim.fn.stdpath("data") .. "/lazy"
vim.opt.runtimepath:prepend(lazy_root .. "/fzf-lua")
vim.opt.runtimepath:prepend(lazy_root .. "/nvim-dap")

local core = require("fzf-lua.core")
local original_wrap = core.fzf_wrap
local captured
core.fzf_wrap = function(command, opts, convert_actions)
	if opts and opts._start == false then
		return original_wrap(command, opts, convert_actions)
	end
	local no_start = vim.tbl_extend("force", {}, opts, { _start = false })
	local input_actions = vim.deepcopy(opts.actions)
	local _, converted_command, converted_opts = original_wrap(command, no_start, convert_actions)
	captured = { command = converted_command, opts = converted_opts, input_actions = input_actions, convert_actions = convert_actions }
	return nil, converted_command, converted_opts
end

local owner = {
	insert = function() end,
	restore = function() end,
}
local prompt = dofile("lua/config/fzf_prompt.lua")

prompt.launch("files", owner)
assert(captured and captured.command, "the pinned files provider returns a relaunchable command")
assert(captured.convert_actions == true, "files relaunch converts the replacement action")
assert(
	vim.tbl_count(captured.opts.actions) == 2 and captured.opts.actions.enter and captured.opts.actions["ctrl-y"],
	"files retains only insertion Enter and semantic Ctrl-y: input="
		.. vim.inspect(captured.input_actions)
		.. " converted="
		.. vim.inspect(captured.opts.actions)
)

captured = nil
prompt.launch("live_grep", owner)
assert(captured and captured.command, "the pinned live_grep provider returns a relaunchable command")
assert(captured.opts.is_live == true, "the live provider keeps its resolved live-search options")
assert(
	vim.tbl_count(captured.opts.actions) == 2 and captured.opts.actions.enter and captured.opts.actions["ctrl-y"],
	"live grep retains only insertion Enter and semantic Ctrl-y"
)

package.loaded["dap"] = {
	session = function()
		return {
			stopped_thread_id = 1,
			threads = {
				[1] = {
					frames = {
						{ name = "main", source = { name = "main.lua", path = "/tmp/main.lua", sourceReference = 0 }, line = 12 },
					},
				},
			},
		}
	end,
}
package.loaded["fzf-lua.providers.dap"] = nil
captured = nil
prompt.launch("dap_frames", owner)
assert(captured and captured.command, "the pinned DAP frames provider returns a relaunchable command")
assert(
	vim.tbl_count(captured.opts.actions) == 2 and captured.opts.actions.enter and captured.opts.actions["ctrl-y"],
	"the adapter replaces DAP's frame-switch action with safe prompt actions"
)

core.fzf_wrap = original_wrap

print("PASS pinned fzf-lua static, live, and DAP providers accept prompt-safe relaunch actions")

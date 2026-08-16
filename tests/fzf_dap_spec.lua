package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

package.loaded["dap"] = {
	session = function()
		return {
			stopped_thread_id = 7,
			threads = {
				[7] = {
					frames = {
						{ name = "main", source = { path = "/tmp/main.lua" }, line = 8 },
						{ name = "worker", source = { path = "/tmp/worker file.lua" }, line = 12, column = 4 },
						{ name = "remote", source = { sourceReference = 3 }, line = 2 },
						{ name = "uri", source = { path = "file:///tmp/uri source.lua" }, line = 14, column = 2 },
						{ name = "generated", source = { path = "jdt://contents/java/lang/String.class" }, line = 5 },
					},
				},
			},
		}
	end,
}
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(value) return value:gsub("\27%[[%d;]*m", "") end,
}

local wrapped
package.loaded["fzf-lua.core"] = {
	fzf_wrap = function(command, opts, convert_actions)
		wrapped = { command = command, opts = opts, convert_actions = convert_actions }
	end,
}
local switched = 0
package.loaded["fzf-lua"] = {
	dap_frames = function(opts)
		assert(opts._start == false, "adapter resolves the provider without starting it")
		return nil, "dap-command", {
			_start = false,
			previewer = "dap-preview",
			actions = { enter = function() switched = switched + 1 end },
		}
	end,
}

local dap = dofile("lua/config/fzf_dap.lua")
eq(dap.frame_location("\27[35m2\27[0m. [worker] worker.lua:12"), "/tmp/worker file.lua:12:4", "frame rows resolve through the live DAP frame")
eq(dap.frame_location("3. [remote] generated.lua:2"), nil, "frames without a usable source path fail closed")
eq(dap.frame_location("4. [uri] source.lua:14"), "/tmp/uri source.lua:14:2", "file URI frames become absolute file locations")
eq(dap.frame_location("5. [generated] String.class:5"), "jdt://contents/java/lang/String.class:5", "non-file URI frames remain URI locations")

local original_setreg = vim.fn.setreg
local original_notify = vim.notify
local writes = {}
vim.fn.setreg = function(register, value) table.insert(writes, { register = register, value = value }) end
vim.notify = function() end

dap.yank({ "1. [main] main.lua:8" })
eq(writes, { { register = "+", value = "/tmp/main.lua:8" } }, "DAP Ctrl-y copies the absolute frame location")

dap.launch()
eq(wrapped.command, "dap-command", "adapter starts the resolved DAP command")
eq(wrapped.opts._start, nil, "adapter removes the no-start marker")
eq(wrapped.opts.previewer, "dap-preview", "adapter preserves the DAP preview")
assert(wrapped.opts.actions.enter, "adapter preserves frame switching")
assert(wrapped.opts.actions["ctrl-y"], "adapter adds semantic Ctrl-y")
wrapped.opts.actions.enter()
eq(switched, 1, "preserved Enter still switches frames")

vim.fn.setreg = original_setreg
vim.notify = original_notify

print("PASS DAP frame yanks resolve live absolute source locations")

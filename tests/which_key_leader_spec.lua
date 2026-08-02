local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

vim.g.mapleader = " "

local spec = dofile("lua/plugins/which-key.lua")[1]
local autocmds = {}
local cleared = {}
local refreshed = {}
local original_create_augroup = vim.api.nvim_create_augroup
local original_create_autocmd = vim.api.nvim_create_autocmd
local original_buf_call = vim.api.nvim_buf_call
local original_maparg = vim.fn.maparg
local original_schedule = vim.schedule
local test_buf = vim.api.nvim_get_current_buf()

package.loaded["which-key"] = {
	setup = function() end,
	add = function() end,
}
package.loaded["which-key.state"] = { state = nil }
package.loaded["which-key.buf"] = {
	clear = function(opts)
		table.insert(cleared, opts)
	end,
	get = function(opts)
		table.insert(refreshed, opts)
	end,
}

vim.api.nvim_create_augroup = function(name, opts)
	eq({ name, opts }, { "nvim_mini_which_key_leader", { clear = true } }, "leader guard uses a clear project group")
	return 42
end
vim.api.nvim_create_autocmd = function(events, opts)
	autocmds.events = events
	autocmds.opts = opts
	return 1
end
vim.api.nvim_buf_call = function(_, callback)
	return callback()
end
vim.fn.maparg = function()
	return {}
end
vim.schedule = function(callback)
	callback()
end

spec.config(nil, spec.opts)
assert(autocmds.opts, "leader guard autocmd is registered")
autocmds.opts.callback({ buf = test_buf })

vim.api.nvim_create_augroup = original_create_augroup
vim.api.nvim_create_autocmd = original_create_autocmd
vim.api.nvim_buf_call = original_buf_call
vim.fn.maparg = original_maparg
vim.schedule = original_schedule

eq(autocmds.events, { "BufEnter", "WinEnter", "ModeChanged" }, "leader guard watches context transitions")
eq(autocmds.opts.group, 42, "leader guard autocmd belongs to its project group")
eq(cleared, { { buf = test_buf, mode = "n" } }, "a stale leader trigger registration is removed")
eq(refreshed, { { buf = test_buf, mode = "n" } }, "a missing leader trigger is rebuilt")

print("PASS missing which-key leader triggers are rebuilt")

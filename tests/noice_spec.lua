local spec = dofile("lua/plugins/noice.lua")

local original = {
	notify = vim.notify,
	schedule = vim.schedule,
	defer_fn = vim.defer_fn,
	create_autocmd = vim.api.nvim_create_autocmd,
	create_augroup = vim.api.nvim_create_augroup,
}

local notify = setmetatable({
	setup = function() end,
}, {
	__call = function() end,
})

package.loaded["notify"] = notify
package.loaded["noice"] = { setup = function() end }
package.loaded["noice.ui"] = { get_handler = function() end }
vim.schedule = function() end
vim.defer_fn = function() end
vim.api.nvim_create_autocmd = function() return 1 end
vim.api.nvim_create_augroup = function() return 1 end

local opts = vim.deepcopy(spec.opts)
spec.config(nil, opts)

vim.notify = original.notify
vim.schedule = original.schedule
vim.defer_fn = original.defer_fn
vim.api.nvim_create_autocmd = original.create_autocmd
vim.api.nvim_create_augroup = original.create_augroup

local mini_timeouts = { opts.views.mini.timeout }
for _, route in ipairs(opts.routes) do
	if route.view == "mini" and route.opts and route.opts.timeout ~= nil then
		table.insert(mini_timeouts, route.opts.timeout)
	end
end

assert(#mini_timeouts == 2, "the mini view and confirmation route both define a timeout")
for _, timeout in ipairs(mini_timeouts) do
	assert(type(timeout) == "number" and timeout > 0, "Noice mini timeouts must be positive numbers")
end

print("PASS Noice mini views only receive numeric timeouts")

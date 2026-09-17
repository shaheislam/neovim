local original = {
	notify = vim.notify,
	schedule = vim.schedule,
	defer_fn = vim.defer_fn,
	create_autocmd = vim.api.nvim_create_autocmd,
	create_augroup = vim.api.nvim_create_augroup,
	persistent = vim.g.noice_persistent_messages,
	modules = {
		notify = package.loaded["notify"],
		noice = package.loaded["noice"],
		ui = package.loaded["noice.ui"],
		config = package.loaded["noice.config"],
		view = package.loaded["noice.view"],
	},
}

local notifications = {}
local notify = setmetatable({
	setup = function() end,
}, {
	__call = function(_, ...)
		table.insert(notifications, { ... })
	end,
})

local ok, err = xpcall(function()
	local spec = dofile("lua/plugins/noice.lua")
	local persistent_mapping
	for _, key in ipairs(spec.keys) do
		if key[1] == "<leader>mP" then
			persistent_mapping = key
		end
		assert(key[1] ~= "<leader>mp", "Noice no longer owns <leader>mp")
	end
	assert(persistent_mapping, "Noice owns <leader>mP")
	assert(persistent_mapping.desc == "Toggle Persistent Messages", "persistent toggle keeps its description")

	package.loaded["notify"] = notify
	package.loaded["noice"] = { setup = function() end }
	package.loaded["noice.ui"] = { get_handler = function() end }
	vim.schedule = function() end
	vim.defer_fn = function() end
	vim.api.nvim_create_autocmd = function() return 1 end
	vim.api.nvim_create_augroup = function() return 1 end

	local opts = vim.deepcopy(spec.opts)
	package.loaded["noice.config"] = { options = opts }
	package.loaded["noice.view"] = {
		_views = {
			first = { _opts = { timeout = 3000 } },
			second = { opts = { timeout = 3000 } },
		},
	}
	spec.config(nil, opts)

	local mini_timeouts = { opts.views.mini.timeout }
	local mini_route
	for _, route in ipairs(opts.routes) do
		if route.view == "mini" and route.opts and route.opts.timeout ~= nil then
			mini_route = route
			table.insert(mini_timeouts, route.opts.timeout)
		end
	end

	assert(#mini_timeouts == 2, "the mini view and confirmation route both define a timeout")
	for _, timeout in ipairs(mini_timeouts) do
		assert(type(timeout) == "number" and timeout > 0, "Noice mini timeouts must be positive numbers")
	end

	persistent_mapping[2]()
	assert(vim.g.noice_persistent_messages == true, "persistent toggle enables persistent messages")
	assert(opts.views.mini.timeout == 30000, "persistent toggle extends the mini timeout")
	assert(opts.smart_move.enabled == false, "persistent toggle disables smart move")
	assert(mini_route.opts.timeout == 30000, "persistent toggle extends mini routes")
	assert(package.loaded["noice.view"]._views.first._opts.timeout == 30000, "persistent toggle updates mounted view options")
	assert(package.loaded["noice.view"]._views.second.opts.timeout == 30000, "persistent toggle updates alternate mounted view options")
	assert(notifications[#notifications][1] == "Persistent messages: ON (30s)", "persistent toggle reports enabled state")

	persistent_mapping[2]()
	assert(vim.g.noice_persistent_messages == false, "persistent toggle disables persistent messages")
	assert(opts.views.mini.timeout == 3000, "persistent toggle restores the mini timeout")
	assert(opts.smart_move.enabled == true, "persistent toggle restores smart move")
end, debug.traceback)

vim.notify = original.notify
vim.schedule = original.schedule
vim.defer_fn = original.defer_fn
vim.api.nvim_create_autocmd = original.create_autocmd
vim.api.nvim_create_augroup = original.create_augroup
vim.g.noice_persistent_messages = original.persistent
package.loaded["notify"] = original.modules.notify
package.loaded["noice"] = original.modules.noice
package.loaded["noice.ui"] = original.modules.ui
package.loaded["noice.config"] = original.modules.config
package.loaded["noice.view"] = original.modules.view

assert(ok, err)

print("PASS Noice persistent messages use <leader>mP and update live timeout state")

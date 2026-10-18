-- Region adapter for the pinned Diffview fork; standalone views keep its tab lifecycle.
local M = {}
local api = vim.api
local installed = false

function M.serialize_refresh(view)
	if view.region_serialized then
		return
	end
	view.region_serialized = true
	local update, running, pending, callbacks = view.update_files, false, nil, {}
	local function drain()
		if running or not pending or view.closing:check() then
			return
		end
		local opts, listeners = pending, callbacks
		pending, callbacks, running = nil, {}, true
		update(view, opts, function(err)
			running = false
			for _, callback in ipairs(listeners) do
				callback(err)
			end
			vim.schedule(drain)
		end)
	end
	-- The fork's debounce coalesces starts but permits overlapping async renders.
	view.update_files = function(_, opts, callback)
		if type(opts) == "function" then
			opts, callback = nil, opts
		end
		pending = vim.tbl_extend("force", pending or {}, type(opts) == "table" and opts or {})
		if callback then
			callbacks[#callbacks + 1] = callback
		end
		drain()
	end
end

local function valid(win)
	return win and api.nvim_win_is_valid(win)
end

local function member(view, win)
	local zoom = package.loaded["config.window_zoom"]
	win = (zoom and zoom.origin(win)) or win
	return view.region and view.region.windows[win] and valid(win)
end

local function region_window(view)
	for _, win in ipairs(view.cur_layout and view.cur_layout.windows or {}) do
		if valid(win.id) then
			view.region.windows[win.id] = true
			return win.id
		end
	end
	for win in pairs(view.region.windows) do
		if valid(win) then
			return win
		end
	end
	error("Diffview's editor region was closed; close the review before reopening it")
end

local function install()
	if installed then
		return
	end
	installed = true
	local lib = require("diffview.lib")
	lib.get_current_view = function()
		local view = lib.tabpage_to_view(api.nvim_get_current_tabpage())
		if view and (not view.region or member(view, api.nvim_get_current_win())) then
			return view
		end
	end
	local base = require("diffview.scene.view")
	local close = base.View.close
	base.View.close = function(view, opts)
		if not view.region then
			return close(view, opts)
		end
		local region = view.region
		view.closing:send()
		DiffviewGlobal.emitter:emit("view_leave", view)
		base._test.restore_diffopt(view)
		local keep
		for win in pairs(region.windows) do
			if valid(win) then
				keep = win
				break
			end
		end
		-- Detach the retained window before destroying layouts and their render hooks.
		for _, layout in pairs(view.layouts) do
			for _, win in ipairs(layout.windows) do
				if win.id == keep then
					win:_restore_winopts()
					win:set_id(nil)
				end
			end
			layout:destroy()
		end
		for win in pairs(region.windows) do
			if valid(win) and win ~= keep then
				api.nvim_win_close(win, true)
			end
		end
		if valid(keep) then
			api.nvim_set_current_win(keep)
			if api.nvim_buf_is_valid(region.buf) then
				api.nvim_win_set_buf(keep, region.buf)
			end
			for name, value in pairs(region.options) do
				vim.wo[keep][name] = value
			end
			vim.fn.winrestview(region.saved_view)
		end
		for win, options in pairs(region.companions) do
			if valid(win) then
				vim.wo[win].winfixwidth, vim.wo[win].winfixheight = options.width, options.height
			end
		end
		DiffviewGlobal.emitter:emit("view_closed", view)
		for event, callback in pairs(view._global_callbacks) do
			DiffviewGlobal.emitter:off(callback, event)
		end
		view._global_callbacks = {}
		view.emitter:clear()
		lib.dispose_view(view)
	end
end

-- Prefer the leftmost normal editor, even when a handoff arrives in the agent panel.
local function editor_window()
	local windows = {}
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_get_config(win).relative == "" then
			windows[#windows + 1] = win
		end
	end
	if #windows < 2 then
		return
	end
	table.sort(windows, function(a, b)
		local pa, pb = api.nvim_win_get_position(a), api.nvim_win_get_position(b)
		return pa[2] == pb[2] and pa[1] < pb[1] or pa[2] < pb[2]
	end)
	for _, win in ipairs(windows) do
		if vim.bo[api.nvim_win_get_buf(win)].buftype == "" and not vim.wo[win].diff then
			return win
		end
	end
end

function M.focus(view)
	api.nvim_set_current_tabpage(view.tabpage)
	if view.region then
		api.nvim_set_current_win(region_window(view))
	end
end

-- Keep the native split tree and window identities when moving between tabs.
local function region_tree(view, tree)
	if tree[1] == "leaf" then
		return member(view, tree[2]) and tree or nil
	end
	local children = {}
	for _, child in ipairs(tree[2]) do
		local owned = region_tree(view, child)
		if owned then
			children[#children + 1] = owned
		end
	end
	return #children == 1 and children[1] or (#children > 1 and { tree[1], children } or nil)
end

local function first_window(tree)
	return tree[1] == "leaf" and tree[2] or first_window(tree[2][1])
end

local function move_tree(tree, anchor)
	api.nvim_win_set_config(first_window(tree), { split = "left", win = anchor })
	local function populate(node)
		if node[1] == "leaf" then
			return
		end
		local previous = first_window(node[2][1])
		for i = 2, #node[2] do
			local win = first_window(node[2][i])
			api.nvim_win_set_config(win, { split = node[1] == "row" and "right" or "below", win = previous })
			previous = win
		end
		for _, child in ipairs(node[2]) do
			populate(child)
		end
	end
	populate(tree)
end

local function toggle_zoom(view)
	local region, focus = view.region, api.nvim_get_current_win()
	local tree = assert(region_tree(view, vim.fn.winlayout()), "Diffview region has no windows")
	-- Migration must not run tab/window lifecycle hooks on a half-moved view.
	local ignored = vim.o.eventignore
	vim.o.eventignore = "all"
	local ok, err = xpcall(function()
		if region.zoom then
			local zoom = region.zoom
			assert(valid(zoom.anchor), "Diffview zoom's return window was closed")
			local empty = api.nvim_open_win(region.buf, false, { split = "below", win = first_window(tree) })
			move_tree(tree, zoom.anchor)
			view.tabpage = zoom.host
			api.nvim_set_current_tabpage(zoom.host)
			api.nvim_win_close(zoom.anchor, true)
			api.nvim_win_close(empty, true)
			if zoom.showtabline then
				vim.o.showtabline = zoom.showtabline
			end
			vim.cmd(zoom.restore)
			region.zoom = nil
		else
			local zoom = { host = view.tabpage, restore = vim.fn.winrestcmd() }
			if #api.nvim_list_tabpages() == 1 and vim.o.showtabline == 1 then
				zoom.showtabline, vim.o.showtabline = vim.o.showtabline, 0
			end
			zoom.anchor = api.nvim_open_win(region.buf, false, { split = "left", win = first_window(tree) })
			vim.cmd("tabnew")
			local empty = api.nvim_get_current_win()
			zoom.tab = api.nvim_get_current_tabpage()
			region.zoom, view.tabpage = zoom, zoom.tab
			move_tree(tree, empty)
			api.nvim_win_close(empty, true)
			vim.cmd("wincmd =")
			if view.panel:is_open() then
				api.nvim_win_set_width(view.panel.winid, view.panel:get_config().width)
			end
		end
		api.nvim_set_current_win(focus)
	end, debug.traceback)
	vim.o.eventignore = ignored
	if not ok then
		error(err)
	end
	return true
end

function M.toggle_zoom()
	local pane = package.loaded["config.window_zoom"]
	if pane then
		pane.restore()
	end
	local lib = package.loaded["diffview.lib"]
	local view = lib and lib.get_current_view()
	if not view or not view.region then
		return false
	end
	local settled = vim.wait(1000, function()
		local pending = view:set_file_in_flight()
		return not view.panel.updating and (not pending or pending:is_done())
	end, 10)
	if not settled or view.closing:check() or lib.get_current_view() ~= view then
		return true
	end
	return toggle_zoom(view)
end

function M.open(view)
	local lib = require("diffview.lib")
	local existing = lib.tabpage_to_view(api.nvim_get_current_tabpage())
	if existing and existing.region then
		require("diffview").close(existing.tabpage, { force = false })
		if not existing.closing:check() then
			return false
		end
	end
	local origin = editor_window()
	if not origin then
		view:open()
		return true
	end
	install()
	M.serialize_refresh(view)
	api.nvim_set_current_win(origin)
	local region = {
		windows = { [origin] = true },
		companions = {},
		options = {},
		buf = api.nvim_win_get_buf(origin),
		saved_view = vim.fn.winsaveview(),
	}
	for _, name in ipairs({
		"diff",
		"scrollbind",
		"cursorbind",
		"foldmethod",
		"foldenable",
		"foldcolumn",
		"wrap",
		"winfixwidth",
		"winfixheight",
	}) do
		region.options[name] = vim.wo[origin][name]
	end
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if win ~= origin and api.nvim_win_get_config(win).relative == "" then
			region.companions[win] = { width = vim.wo[win].winfixwidth, height = vim.wo[win].winfixheight }
			vim.wo[win].winfixwidth, vim.wo[win].winfixheight = true, true
		end
	end
	view.region, view.tabpage = region, api.nvim_get_current_tabpage()
	local close_view = view.close
	view.close = function(self, opts)
		local pane = package.loaded["config.window_zoom"]
		if pane and region.windows[pane.origin()] then
			pane.restore()
		end
		if region.zoom and self:can_close(opts) then
			local zoom = region.zoom
			if api.nvim_tabpage_is_valid(self.tabpage) then
				M.focus(self)
				toggle_zoom(self)
			else
				-- :tabclose already removed the review windows; retain the host anchor.
				self.tabpage, region.zoom = zoom.host, nil
				region.windows[zoom.anchor] = true
				if zoom.showtabline then
					vim.o.showtabline = zoom.showtabline
				end
			end
		end
		return close_view(self, opts)
	end
	local stage = view._stage_layout
	view._stage_layout = function(self, layout)
		local staged = stage(self, layout)
		staged.pivot_producer = function()
			local pivot
			api.nvim_win_call(region_window(self), function()
				vim.cmd("aboveleft vsplit")
				pivot = api.nvim_get_current_win()
				region.windows[pivot] = true
			end)
			return pivot
		end
		if not staged.region then
			staged.region = region
			local create = staged.create_wins
			staged.create_pre = function(layout_self)
				layout_self.state.save_equalalways = vim.o.equalalways
			end
			staged.create_wins = require("diffview.async").void(function(layout_self, ...)
				require("diffview.async").await(create(layout_self, ...))
				for _, win in ipairs(layout_self.windows) do
					if valid(win.id) then
						region.windows[win.id] = true
					end
				end
			end)
		end
		return staged
	end
	local config = view.panel.get_config
	view.panel.get_config = function(panel)
		local options = vim.deepcopy(config(panel))
		options.relative, options.win = "win", region_window(view)
		options.width = math.max(12, math.min(28, math.floor(api.nvim_win_get_width(options.win) / 3)))
		return options
	end
	view.init_layout = function(self)
		self:use_layout(require("diffview.scene.view").View.get_temp_layout())
		self.cur_layout:create(origin)
		self.panel:focus(not self:should_show_panel())
		region.windows[self.panel.winid] = true
		self.emitter:emit("post_layout")
	end
	local panel_open = view.panel.open
	view.panel.open = function(panel)
		panel_open(panel)
		if panel.winid then
			region.windows[panel.winid] = true
		end
	end
	local ok, err = xpcall(function()
		lib.add_view(view)
		view:init_layout()
		view:post_open()
		require("diffview.scene.view")._test.apply_diffopt(view)
		DiffviewGlobal.emitter:emit("view_opened", view)
		DiffviewGlobal.emitter:emit("view_enter", view)
	end, debug.traceback)
	if not ok then
		local closed = pcall(view.close, view, { force = true })
		if not closed then
			view.panel:destroy()
			require("diffview.scene.view").View.close(view)
		end
		error(err)
	end
	return true
end

return M

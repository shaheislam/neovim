local M = {}

local state = {
	generation = 0,
	list_id = nil,
	view = nil,
}

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

local function review_keymaps()
	return package.loaded["codecompanion.interactions.code_review.keymaps"]
end

local function owned_quickfix()
	local keymaps = review_keymaps()
	if not keymaps then
		return nil
	end
	if not keymaps.owns_quickfix() then
		keymaps.restore()
		return nil
	end
	return vim.fn.getqflist({ id = 0, idx = 0, items = 0, qfbufnr = 0, context = 0 })
end

local function hunk_id(item)
	return type(item) == "table"
		and type(item.user_data) == "table"
		and item.user_data.code_review_hunk
		or nil
end

local function quickfix()
	local info = owned_quickfix()
	if not info then
		return nil
	end
	for _, item in ipairs(info.items) do
		if hunk_id(item) then
			return info
		end
	end
	review_keymaps().restore()
	return nil
end

local function current_item(info)
	local line = vim.api.nvim_win_get_cursor(0)[1]
	return info.items[line]
end

local function quicker_context_only(info)
	if type(info.context) ~= "table" or type(info.context.quicker) ~= "table" then
		return false
	end
	for _, item in ipairs(info.items) do
		if item.valid ~= 0 or type(item.user_data) ~= "table" or item.user_data.lnum == nil then
			return false
		end
	end
	return #info.items > 0
end

local function matching_view(view, target)
	return view
		and view.tabpage
		and vim.api.nvim_tabpage_is_valid(view.tabpage)
		and view.adapter
		and view.adapter.ctx
		and canonical(view.adapter.ctx.toplevel) == canonical(target.root)
		and view.rev_arg == target.baseline_ref
end

local function target_is_live(target, generation)
	if generation ~= state.generation or state.list_id == nil then
		return false
	end
	local info = quickfix()
	if not info or info.id ~= state.list_id then
		return false
	end
	for _, item in ipairs(info.items) do
		if hunk_id(item) == target.id then
			return true
		end
	end
	return false
end

local function position(view, target, generation)
	if not target_is_live(target, generation) or not matching_view(view, target) then
		return
	end
	if not view.cur_entry or view.cur_entry.path ~= target.path or not view.cur_layout then
		return
	end
	local main = view.cur_layout:get_main_win()
	local win = type(main) == "table" and main.id or main
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.api.nvim_win_call(win, function()
		pcall(vim.api.nvim_win_set_cursor, win, { target.line, 0 })
		pcall(vim.cmd, "normal! zv")
		pcall(vim.cmd, "normal! zz")
	end)
end

local function after_switch(future, view, target, generation)
	local done = function()
		vim.schedule(function()
			position(view, target, generation)
		end)
	end
	if future and type(future.finally) == "function" then
		future:finally(done)
	else
		done()
	end
end

local function retarget(view, target, generation)
	if not target_is_live(target, generation) or not matching_view(view, target) then
		return
	end

	local in_flight = type(view.set_file_in_flight) == "function" and view:set_file_in_flight() or nil
	local busy = in_flight and type(in_flight.is_done) == "function" and not in_flight:is_done()
	if busy or not view.cur_entry or view.cur_entry.path ~= target.path then
		local future = view:set_file_by_path(target.path, false, true)
		after_switch(future, view, target, generation)
		return
	end

	vim.schedule(function()
		position(view, target, generation)
	end)
end

local function restore_quickfix(info, source_tab)
	if source_tab and vim.api.nvim_tabpage_is_valid(source_tab) then
		vim.api.nvim_set_current_tabpage(source_tab)
	end
	local current = vim.fn.getqflist({ id = 0 })
	if current.id ~= info.id then
		return
	end
	pcall(vim.cmd, "copen 10")
	pcall(vim.cmd, "wincmd J")
	pcall(vim.cmd, "resize 10")
	pcall(vim.api.nvim_win_set_cursor, 0, { info.cursor, 0 })
end

local function open_view(target, generation)
	local info = quickfix()
	if not info then
		return nil
	end
	info.cursor = vim.api.nvim_win_get_cursor(0)[1]
	local source_tab = vim.api.nvim_get_current_tabpage()
	pcall(vim.cmd, "cclose")

	local absolute_path = vim.fs.joinpath(target.root, target.path)
	local command = table.concat({
		"DiffviewOpen -C" .. vim.fn.fnameescape(target.root),
		vim.fn.fnameescape(target.baseline_ref),
		"--selected-file=" .. vim.fn.fnameescape(absolute_path),
	}, " ")
	local ok, err = pcall(vim.cmd, command)
	local view = ok and require("diffview.lib").get_current_view() or nil
	if not ok or not matching_view(view, target) then
		restore_quickfix(info, source_tab)
		vim.notify("CodeCompanion review Diffview failed: " .. tostring(err or "no matching view"), vim.log.levels.WARN)
		return nil
	end

	restore_quickfix(info)
	state.view = view
	if view.initialized then
		vim.schedule(function()
			retarget(view, target, generation)
		end)
	else
		view.emitter:once("files_updated", function()
			vim.schedule(function()
				retarget(view, target, generation)
			end)
		end)
	end
	return view
end

function M.provider(target)
	local info = quickfix()
	if not info then
		return
	end
	state.generation = state.generation + 1
	state.list_id = info.id
	local generation = state.generation

	if matching_view(state.view, target) and vim.api.nvim_get_current_tabpage() == state.view.tabpage then
		retarget(state.view, target, generation)
		return
	end
	open_view(target, generation)
end

function M.follow_current(opts)
	opts = opts or {}
	local info = quickfix()
	if not info then
		return false
	end
	local item = current_item(info)
	if not hunk_id(item) then
		return true
	end

	local generation = state.generation + 1
	state.generation = generation
	local run = function()
		if generation ~= state.generation then
			return
		end
		local current = quickfix()
		if not current or current.id ~= info.id then
			return
		end
		require("codecompanion.interactions.code_review").open_diff()
	end
	if opts.immediate then
		run()
	else
		vim.defer_fn(run, 45)
	end
	return true
end

function M.run(action)
	local keymaps = review_keymaps()
	if not keymaps or not keymaps.owns_quickfix() then
		if keymaps then
			keymaps.restore()
		end
		return
	end
	local info = quickfix()
	if not info or not hunk_id(current_item(info)) then
		return
	end
	require("codecompanion.interactions.code_review")[action]()
end

function M.resync_after(action)
	local keymaps = review_keymaps()
	if not keymaps or not keymaps.owns_quickfix() then
		if keymaps then
			keymaps.restore()
		end
		return
	end
	local info = quickfix()
	if not info then
		return
	end
	if not hunk_id(current_item(info)) then
		return
	end
	local before = vim.api.nvim_win_get_cursor(0)[1]
	require("codecompanion.interactions.code_review")[action]()
	vim.schedule(function()
		local current = owned_quickfix()
		if not current then
			return
		end
		if #current.items == 0 then
			keymaps.restore()
			return
		end
		local start = math.min(before, #current.items)
		local line
		for index = start, #current.items do
			if hunk_id(current.items[index]) then
				line = index
				break
			end
		end
		if not line then
			for index = start - 1, 1, -1 do
				if hunk_id(current.items[index]) then
					line = index
					break
				end
			end
		end
		if not line then
			if quicker_context_only(current) then
				vim.fn.setqflist({}, "r", { title = current.title, items = {} })
			end
			keymaps.restore()
			return
		end
		vim.api.nvim_win_set_cursor(0, { line, 0 })
		M.follow_current({ immediate = true })
	end)
end

return M

local M = {}
local snapshots = setmetatable({}, { __mode = "k" })

local function version(view, entry)
	local path = view.adapter.ctx.toplevel .. "/" .. entry.path
	local stat, _, code = vim.uv.fs_lstat(path)
	local content
	if not stat then
		if code ~= "ENOENT" then
			return nil
		end
		content = "missing"
	elseif stat.type == "link" then
		content = vim.uv.fs_readlink(path)
	elseif stat.type == "file" then
		local fd = vim.uv.fs_open(path, "r", 0)
		if not fd then
			return nil
		end
		content = vim.uv.fs_read(fd, stat.size, 0)
		vim.uv.fs_close(fd)
	else
		-- Directory/submodule contents cannot be verified as a single file.
		return nil
	end
	if not content then
		return nil
	end
	return vim.fn.sha256(vim.json.encode({
		view.left.commit,
		view.right.type,
		view.right.commit or "",
		entry.oldpath or "",
		stat and stat.mode or 0,
		content,
	}))
end

function M.attach(view, context)
	local panel = view.panel
	local versions = snapshots[context] or {}
	snapshots[context] = versions
	local function capture()
		for key in pairs(versions) do
			if not panel.selected_files[key] then
				versions[key] = nil
			end
		end
		for _, entry in ipairs(panel:get_selected_files()) do
			local key = entry.kind .. ":" .. entry.path
			if versions[key] == nil then
				versions[key] = version(view, entry) or false
			end
		end
	end
	local changed = panel.on_selection_changed
	panel.on_selection_changed = function(selected)
		capture()
		if changed then
			changed(selected)
		end
	end
	view.emitter:on("files_updated", function()
		for _, entry in ipairs(panel:get_selected_files()) do
			local key = entry.kind .. ":" .. entry.path
			local current = version(view, entry)
			if versions[key] ~= nil and (not current or versions[key] ~= current) then
				require("diffview.api.selections").deselect({ entry.path }, { view = view, kind = entry.kind })
			else
				versions[key] = current or false
			end
		end
	end)
	-- Persisted marks without a live snapshot are baselined when first loaded.
	capture()
end

return M

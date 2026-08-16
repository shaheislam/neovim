local M = {}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.clean(value)
	local ok, utils = pcall(require, "fzf-lua.utils")
	if ok then
		value = utils.strip_ansi_coloring(value or "")
	end
	return trim((value or ""):gsub("\194\160", " "):gsub("%s+", " "))
end

local function relative(path, reference_dir)
	if not path or path == "" then
		return nil
	end
	if not reference_dir or reference_dir == "" then
		return vim.fn.fnamemodify(path, ":.")
	end

	local absolute_path = vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
	local absolute_reference = vim.fn.fnamemodify(reference_dir, ":p"):gsub("/+$", "")
	if absolute_path == absolute_reference then
		return "."
	end
	local prefix = absolute_reference .. "/"
	if absolute_path:sub(1, #prefix) == prefix then
		return absolute_path:sub(#prefix + 1)
	end
	return absolute_path
end

local function path_value(entry, opts, location, config)
	local file = require("fzf-lua.path").entry_to_file(entry, opts or {})
	local reference_dir = config and config.reference_dir
	if type(reference_dir) == "function" then
		reference_dir = reference_dir(opts or {})
	end
	local path = file and relative(file.path, reference_dir)
	if not path or path == "" then
		return nil
	end
	if location and (file.line or 0) > 0 then
		path = path .. ":" .. file.line
		if (file.col or 0) > 0 then
			path = path .. ":" .. file.col
		end
	end
	return path
end

local function git_status_value(entry, opts)
	local value = entry or ""
	local ok, utils = pcall(require, "fzf-lua.utils")
	if ok then value = utils.strip_ansi_coloring(value) end
	value = value:gsub("\194\160", " ")
	local destination = value:match("%s+%-%>%s+(.+)$")
	if destination then
		value = M.clean(destination):gsub('^"(.*)"$', "%1")
		return value ~= "" and value or nil
	end

	local porcelain = value:gsub("^[%?MADRCU! ][%?MADRCU! ]%s+", "")
	if porcelain ~= value then
		porcelain = M.clean(porcelain):gsub('^"(.*)"$', "%1")
		return porcelain ~= "" and porcelain or nil
	end

	local parsed_ok, file = pcall(function()
		return require("fzf-lua.path").entry_to_file(entry, opts or {})
	end)
	local path = parsed_ok and file and relative(file.path) or nil
	return path ~= "" and path or nil
end

function M.entry_value(kind, entry, opts, config)
	if config and config.resolve then
		local value = config.resolve(entry, opts or {})
		if config.preserve_whitespace then
			value = trim(value)
		else
			value = M.clean(value)
		end
		return value ~= "" and value or nil
	elseif kind == "path" then
		return path_value(entry, opts, false, config)
	elseif kind == "location" then
		return path_value(entry, opts, true, config)
	elseif kind == "git_status" then
		return git_status_value(entry, opts)
	elseif kind == "branch" then
		return M.clean(entry):match("^[*+]?%s*([^%s]+)")
	elseif kind == "commit" then
		return M.clean(entry):match("^([a-fA-F0-9]+)")
	elseif kind == "worktree" then
		return M.clean(entry):match("^(%S+)")
	elseif kind == "stash" then
		return M.clean(entry):match("^(stash@{%d+})")
	elseif kind == "command" then
		local value = M.clean(entry)
		return value ~= "" and ":" .. value:gsub("^:", "") or nil
	elseif kind == "register" then
		local register = M.clean(entry):match("^%[(.)%]")
		if not register then return nil end
		local ok, value = pcall(vim.fn.getreg, register)
		value = ok and M.clean(value) or ""
		return value ~= "" and value or nil
	elseif kind == "zoxide" then
		local value = M.clean(entry)
		return value:match("^%S+%s+(.+)$") or value
	elseif kind == "aws_account" then
		local decoded = require("config.aws_profiles").decode_row(entry)
		return decoded.account_id ~= "" and decoded.account_id or nil
	end
	local value = M.clean(entry)
	return value ~= "" and value or nil
end

local function values(kind, selected, opts, config)
	local result = {}
	local seen = {}
	for _, entry in ipairs(selected or {}) do
		local value = M.entry_value(kind, entry, opts or {}, config or {})
		if value and value ~= "" and not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end
	return result
end

function M.clipboard_text(kind, selected, opts, config)
	local decoded = values(kind, selected, opts, config)
	if #decoded == 0 then return nil end
	return table.concat(decoded, (config and config.separator) or " ")
end

function M.insert_text(kind, selected, opts, config)
	local text = M.clipboard_text(kind, selected, opts, config)
	return text and (text .. " ") or nil
end

function M.action(kind, config)
	return function(selected, opts)
		local text = M.clipboard_text(kind, selected, opts, config)
		if not text then return end
		vim.fn.setreg("+", text)
		vim.notify(("Yanked %d FZF selection%s"):format(#(selected or {}), #(selected or {}) == 1 and "" or "s"))
	end
end

return M

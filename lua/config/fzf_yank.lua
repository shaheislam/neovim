local M = {}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function strip_display(value)
	local ok, utils = pcall(require, "fzf-lua.utils")
	if ok then
		value = utils.strip_ansi_coloring(value or "")
	end
	return (value or ""):gsub("\194\160", " ")
end

function M.clean(value)
	return trim(strip_display(value):gsub("%s+", " "))
end

local function configured_base(opts, config)
	local base = config and (config.base_dir or config.reference_dir)
	if type(base) == "function" then
		base = base(opts or {})
	end
	return base or (opts and (opts.cwd or opts._cwd)) or vim.fn.getcwd()
end

local function absolute(path, base)
	if not path or path == "" then
		return nil
	end
	if path == "~" then
		path = vim.env.HOME
	elseif path:match("^~/") then
		path = vim.fs.joinpath(vim.env.HOME, path:sub(3))
	end
	local is_absolute = path:match("^/") or path:match("^%a:[/\\]")
	if not is_absolute then
		path = vim.fs.joinpath(base or vim.fn.getcwd(), path)
	end
	local normalized = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
	return normalized == "/" and normalized or normalized:gsub("/+$", "")
end

local function path_value(entry, opts, location, config)
	opts = opts or {}
	local file = require("fzf-lua.path").entry_to_file(entry, opts, opts._uri)
	if not file then return nil end

	local path
	if file.uri and file.uri ~= "" then
		if file.uri:match("^file://") then
			local ok, filename = pcall(vim.uri_to_fname, file.uri)
			path = ok and absolute(filename, configured_base(opts, config)) or nil
		else
			path = file.uri
		end
	else
		path = absolute(file.path or file.bufname, configured_base(opts, config))
	end
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
	opts = opts or {}
	local value = strip_display(entry)
	local destination = value:match("%s+%-%>%s+(.+)$")
	if destination then
		value = trim(destination):gsub('^"(.*)"$', "%1")
		return absolute(value, opts.cwd or opts._cwd)
	end

	local porcelain = value:gsub("^[%?MADRCU! ][%?MADRCU! ]%s+", "")
	if porcelain ~= value then
		porcelain = trim(porcelain):gsub('^"(.*)"$', "%1")
		return absolute(porcelain, opts.cwd or opts._cwd)
	end

	local parsed_ok, file = pcall(function()
		return require("fzf-lua.path").entry_to_file(entry, opts)
	end)
	local path = parsed_ok and file and absolute(file.path or file.bufname, opts.cwd or opts._cwd) or nil
	return path ~= "" and path or nil
end

local function register_name(entry)
	return M.clean(entry):match("^%[(.)%]")
end

local function worktree_value(entry, opts, config)
	local value = trim(strip_display(entry))
	local path = value:match("^(.-)%s+[%da-fA-F]+%s+%b[]%s*$")
		or value:match("^(.-)%s+[%da-fA-F]+%s+%b()%s*$")
		or value
	return absolute(trim(path), configured_base(opts, config))
end

local function zoxide_value(entry, opts, config)
	local value = trim(strip_display(entry))
	local path = value:match("^%S+\t(.+)$") or value:match("^%S+%s+(.+)$") or value
	return absolute(trim(path), configured_base(opts, config))
end

function M.entry_value(kind, entry, opts, config)
	if config and config.resolve then
		local value = config.resolve(entry, opts or {})
		if config.preserve_whitespace then
			value = value or ""
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
		return worktree_value(entry, opts or {}, config)
	elseif kind == "stash" then
		return M.clean(entry):match("^(stash@{%d+})")
	elseif kind == "command" then
		local value = trim(strip_display(entry))
		return value ~= "" and ":" .. value:gsub("^:", "") or nil
	elseif kind == "register" then
		local register = register_name(entry)
		if not register then return nil end
		local ok, value = pcall(vim.fn.getreg, register, 1)
		value = ok and value or ""
		return value ~= "" and value or nil
	elseif kind == "zoxide" then
		return zoxide_value(entry, opts or {}, config)
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
	return table.concat(decoded, (config and config.separator) or "\n")
end

function M.insert_text(kind, selected, opts, config)
	local insert_config = vim.tbl_extend("force", {}, config or {})
	insert_config.separator = insert_config.insert_separator or " "
	local text = M.clipboard_text(kind, selected, opts, insert_config)
	return text and (text .. " ") or nil
end

function M.action(kind, config)
	return function(selected, opts)
		if kind == "register" then
			local registers = {}
			for _, entry in ipairs(selected or {}) do
				local register = register_name(entry)
				if register then table.insert(registers, register) end
			end
			if #registers == 0 then return end
			if #registers == 1 then
				vim.fn.setreg("+", vim.fn.getreg(registers[1], 1, true), vim.fn.getregtype(registers[1]))
			else
				local blocks = vim.tbl_map(function(register)
					return ("Register %s\n%s"):format(register, vim.fn.getreg(register, 1))
				end, registers)
				vim.fn.setreg("+", table.concat(blocks, "\n\n"), "V")
			end
			vim.notify(("Yanked %d FZF selection%s"):format(#registers, #registers == 1 and "" or "s"))
			return
		end
		local text = M.clipboard_text(kind, selected, opts, config)
		if not text then return end
		vim.fn.setreg("+", text)
		vim.notify(("Yanked %d FZF selection%s"):format(#(selected or {}), #(selected or {}) == 1 and "" or "s"))
	end
end

return M

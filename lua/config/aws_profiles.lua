local M = {}

local SEP = "  •  "

local function resolve_path(path)
	if path and path ~= "" then
		return path
	end
	local env = os.getenv("AWS_CONFIG_FILE")
	if env and env ~= "" then
		return vim.fn.expand(env)
	end
	return vim.fn.expand("~/.aws/config")
end

function M.profiles(path)
	local resolved = resolve_path(path)
	local ok, lines = pcall(vim.fn.readfile, resolved)
	if not ok or not lines then
		return {}
	end

	local result = {}
	local current

	for _, line in ipairs(lines) do
		local profile_name = line:match("^%[profile%s+(.-)%]%s*$")
		if line:match("^%[default%]%s*$") then
			profile_name = "default"
		end
		if profile_name then
			current = { profile = profile_name }
			table.insert(result, current)
		elseif line:match("^%[.-%]%s*$") then
			current = nil
		elseif current then
			local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
			if key == "sso_account_id" or key == "granted_sso_account_id" then
				current.account_id = value
			elseif key == "sso_role_name" or key == "granted_sso_role_name" then
				current.role = value
			elseif key == "region" then
				current.region = value
			end
		end
	end

	local accounts = {}
	for _, entry in ipairs(result) do
		if entry.account_id then
			table.insert(accounts, {
				profile = entry.profile,
				account_id = entry.account_id,
				role = entry.role,
				region = entry.region,
			})
		end
	end

	return accounts
end

function M.row(entry)
	return string.format("%s%s%s%s%s", entry.profile or "", SEP, entry.account_id or "", SEP, entry.role or "")
end

function M.decode_row(display_row)
	local ok, utils = pcall(require, "fzf-lua.utils")
	local value = display_row or ""
	if ok then
		value = utils.strip_ansi_coloring(value)
	end
	value = value:gsub("\194\160", " ")
	local profile, account_id, role = value:match("^(.-)  •  (.-)  •  (.*)$")
	if not profile then
		return { profile = value, account_id = "", role = "" }
	end
	return { profile = profile, account_id = account_id, role = role }
end

function M.yank_account_id(display_row)
	local decoded = M.decode_row(display_row)
	vim.fn.setreg("+", decoded.account_id)
	vim.notify(("Yanked account ID: %s (%s)"):format(decoded.account_id, decoded.profile), vim.log.levels.INFO)
	return decoded
end

function M.yank_profile_name(display_row)
	local decoded = M.decode_row(display_row)
	vim.fn.setreg("+", decoded.profile)
	vim.notify(("Yanked profile name: %s"):format(decoded.profile), vim.log.levels.INFO)
	return decoded
end

function M.combined(entry)
	return ("%s (%s)"):format(entry.profile or "", entry.account_id or "")
end

function M.yank_both(display_row)
	local decoded = M.decode_row(display_row)
	local value = M.combined(decoded)
	vim.fn.setreg("+", value)
	vim.notify(("Yanked account: %s"):format(value), vim.log.levels.INFO)
	return decoded
end

return M

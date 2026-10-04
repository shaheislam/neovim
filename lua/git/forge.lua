local M = {}
local command = require("git.command")
local cache = {}

vim.api.nvim_create_autocmd("DirChanged", {
	callback = function() cache = {} end,
})

function M.parse(url)
	if not url then return nil end
	local host, path = url:match("^git@([^:]+):(.+)$")
	if not host then
		local without_scheme = url:match("^https?://(.+)$")
		if without_scheme then
			without_scheme = without_scheme:gsub("^[^/@]+@", "")
			host, path = without_scheme:match("^([^/]+)/(.+)$")
		else
			local ssh_url = url:match("^ssh://(.+)$")
			if ssh_url then
				local user_host
				user_host, path = ssh_url:match("^([^/]+)/(.+)$")
				if user_host then host = user_host:gsub("^.+@", "") end
			end
		end
	end
	if not host or not path then return nil end
	path = path:gsub("%.git$", ""):gsub("/$", "")
	local forge_type, web_host = "github", host
	if host:find("github%.com") then
		web_host = "github.com"
	elseif host:find("gitlab%.com") then
		forge_type, web_host = "gitlab", "gitlab.com"
	elseif host == "bitbucket.org" then
		forge_type, web_host = "bitbucket", "bitbucket.org"
	end
	return { type = forge_type, host = web_host, path = path }
end

function M.get()
	local cwd = vim.fn.getcwd()
	if cache[cwd] then return cache[cwd] end
	local ok, url = command.output({ "remote", "get-url", "origin" }, { cwd = cwd })
	if not ok then return nil end
	local result = M.parse(url)
	cache[cwd] = result
	return result
end

return M

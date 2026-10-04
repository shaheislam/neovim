local M = {}
local git = require("git.command")

local function notify(message, level)
	vim.notify("Bitbucket: " .. message, level or vim.log.levels.ERROR)
end

local function run(args, cwd, callback)
	local argv = { "bkt", "pr" }
	vim.list_extend(argv, args)
	vim.system(argv, { cwd = cwd, text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				local error_text = vim.trim((result.stderr and result.stderr ~= "" and result.stderr) or result.stdout or "")
				notify(error_text ~= "" and error_text or "bkt failed")
				return
			end
			callback(result.stdout or "")
		end)
	end)
end

local function decode(text, field)
	local ok, data = pcall(vim.json.decode, text)
	if not ok or type(data) ~= "table" or type(data[field]) ~= "table" then
		notify("unexpected bkt JSON output")
		return nil
	end
	return data[field]
end

local function create(cwd, scope)
	vim.ui.input({ prompt = "New Bitbucket PR title: " }, function(title)
		if not title or vim.trim(title) == "" then return end
		local args = { "create", "--title", vim.trim(title), "--json" }
		vim.list_extend(args, scope)
		run(args, cwd, function(output)
			local ok, pr = pcall(vim.json.decode, output)
			if not ok or type(pr) ~= "table" or type(pr.id) ~= "number" then
				notify("PR created, but bkt returned an unexpected response; run bkt pr list to find it")
				return
			end
			run(vim.list_extend({ "view", tostring(pr.id), "--web" }, scope), cwd, function() end)
		end)
	end)
end

function M.open()
	if vim.fn.executable("bkt") ~= 1 then
		notify("bkt is missing; install avivsinai/tap/bitbucket-cli")
		return
	end
	local forge = require("git.forge").get()
	if not forge or forge.type ~= "bitbucket" then return end
	local workspace, repo = forge.path:match("^([^/]+)/([^/]+)$")
	local ok, cwd = git.output({ "rev-parse", "--show-toplevel" })
	if not workspace or not ok then
		notify("could not determine Bitbucket repository")
		return
	end
	local scope = { "--workspace", workspace, "--repo", repo }
	run(vim.list_extend({ "list", "--state", "OPEN", "--json" }, scope), cwd, function(output)
		local prs = decode(output, "pull_requests")
		if not prs then return end
		local rows = { "+ Create pull request" }
		local ids = {}
		for _, pr in ipairs(prs) do
			if type(pr.id) == "number" and type(pr.title) == "string" then
				local row = string.format("#%d %s", pr.id, pr.title:gsub("[\r\n]", " "))
				table.insert(rows, row)
				ids[row] = pr.id
			end
		end
		require("fzf-lua").fzf_exec(rows, {
			prompt = "Bitbucket PRs> ",
			fzf_opts = { ["--no-multi"] = "", ["--header"] = "enter: open PR  |  ctrl-o: create PR" },
			actions = {
				["default"] = function(selected)
					local row = selected and selected[1]
					if row == rows[1] then
						create(cwd, scope)
					elseif row and ids[row] then
						run(vim.list_extend({ "view", tostring(ids[row]), "--web" }, scope), cwd, function() end)
					end
				end,
				["ctrl-o"] = function() create(cwd, scope) end,
			},
		})
	end)
end

return M

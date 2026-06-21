local M = {}

local function trim(text)
	return vim.trim(text or "")
end

---@class GitCommandResult
---@field ok boolean
---@field code integer
---@field stdout string
---@field stderr string
---@field output string

---Run a git command with table arguments to avoid shell quoting bugs.
---@param args string[] git arguments, excluding the `git` executable
---@param opts? {cwd?: string}
---@return GitCommandResult
function M.run(args, opts)
	opts = opts or {}
	local cmd = { "git" }
	vim.list_extend(cmd, args or {})

	if vim.system then
		local obj = vim.system(cmd, {
			cwd = opts.cwd,
			env = { MISE_QUIET = "1" },
			text = true,
		})
		local result = obj:wait()
		local code = result.code or 0
		local stdout = result.stdout or ""
		local stderr = result.stderr or ""
		return {
			ok = code == 0,
			code = code,
			stdout = stdout,
			stderr = stderr,
			output = trim(stdout ~= "" and stdout or stderr),
		}
	end

	local fallback = { "env", "MISE_QUIET=1" }
	if opts.cwd then
		cmd = { "git", "-C", opts.cwd, unpack(args or {}) }
	end
	vim.list_extend(fallback, cmd)
	local output = vim.fn.system(fallback)
	local code = vim.v.shell_error
	return {
		ok = code == 0,
		code = code,
		stdout = output,
		stderr = code == 0 and "" or output,
		output = trim(output),
	}
end

---@param args string[]
---@param opts? {cwd?: string}
---@return boolean, string
function M.output(args, opts)
	local result = M.run(args, opts)
	return result.ok, result.output
end

---@param args string[]
---@param opts? {cwd?: string}
---@return boolean
function M.succeeds(args, opts)
	return M.run(args, opts).ok
end

return M

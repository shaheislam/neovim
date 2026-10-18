-- Worktree preference is durable; live ownership is always revalidated.
local M = {}
local harnesses = { "opencode", "claude", "codex", "hermes" }

function M.root()
	local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
	assert(result.code == 0, "Agent sessions require a Git worktree")
	return vim.uv.fs_realpath(vim.trim(result.stdout))
end

function M.file(root, name)
	local result = vim.system({ "git", "-C", root, "rev-parse", "--absolute-git-dir" }, { text = true }):wait()
	assert(result.code == 0, "Agent sessions require a Git worktree")
	return vim.trim(result.stdout) .. "/dotfiles-" .. name
end

function M.preference(root)
	local file = M.file(root, "harness")
	local value = vim.fn.filereadable(file) == 1 and vim.trim(table.concat(vim.fn.readfile(file), "\n")) or "opencode"
	assert(vim.tbl_contains(harnesses, value), "Invalid worktree harness metadata")
	return value
end

function M.set_preference(root, harness)
	assert(vim.tbl_contains(harnesses, harness), "Unsupported harness")
	local file = M.file(root, "harness")
	local tmp = file .. "." .. vim.fn.getpid()
	assert(vim.fn.writefile({ harness }, tmp) == 0)
	assert(vim.uv.fs_rename(tmp, file))
	return true
end

function M.capture(root)
	local acp = require("config.agent_acp").capture(root)
	local native = require("config.opencode_handoff").capture_route(root)
	if acp and native then
		return nil
	end
	return acp or native
end

function M.resolve(provenance)
	if type(provenance) ~= "table" then
		return nil
	end
	if provenance.kind == "acp" then
		if require("config.agent_acp").resolve(provenance) then
			return { directory = provenance.project, sessionID = provenance.sessionID, harness = provenance.harness }
		end
		return nil
	end
	return require("config.opencode_handoff").resolve_plan_route(provenance)
end

function M.submit(provenance, text, callback)
	local route = M.resolve(provenance)
	if not route then
		return false
	end
	if provenance.kind == "acp" then
		return require("config.agent_acp").submit(provenance, text, callback)
	end
	require("config.opencode_http").prompt_async(route.sessionID, text, { dir = route.directory }, function(ok, err)
		callback(ok and "submitted" or "uncertain", ok and nil or tostring(err))
	end)
	return true
end

function M.open(harness, root, opts)
	root, opts = root or M.root(), opts or {}
	harness = harness or M.preference(root)
	assert(vim.tbl_contains(harnesses, harness), "Unsupported harness")
	if require("config.agent_acp").capture(root) and require("config.opencode_handoff").capture_route(root) then
		vim.notify("Multiple live owners; close the extra agent before opening another", vim.log.levels.ERROR)
		return nil
	end
	local current = M.capture(root)
	local native_terminal = package.loaded["config.opencode_terminal"]
	local generation = native_terminal and native_terminal.generation_for and native_terminal.generation_for(root)
	if harness ~= "opencode" and generation and native_terminal.job_pid_for(root, generation) then
		vim.notify(
			"The OpenCode terminal still owns this worktree; use :AgentSwitch after it binds",
			vim.log.levels.WARN
		)
		return nil
	end
	if current and (current.harness or "opencode") ~= harness then
		vim.notify("Use :AgentSwitch to hand off the active harness", vim.log.levels.WARN)
		return nil
	end
	if opts.new and current and current.kind == "native" then
		local stopped, err = require("config.agent_switch").quiesce(current, false)
		if not stopped then
			vim.notify(tostring(err), vim.log.levels.WARN)
			return nil
		end
	end
	if harness ~= "opencode" then
		return require("config.agent_acp").open(harness, root, opts)
	end
	require("lazy").load({ plugins = { "opencode.nvim" } })
	local terminal = require("config.opencode_terminal")
	if current and current.kind == "native" and not opts.new then
		if opts.model then
			vim.notify("A startup model cannot replace an already-open OpenCode client", vim.log.levels.ERROR)
			return nil
		end
		if not opts.hidden then
			terminal.open(root)
		end
		return current
	end
	local file = M.file(root, "agent-opencode.json")
	local context = { model = opts.model }
	if not opts.new and vim.fn.filereadable(file) == 1 then
		local saved = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
		assert(
			saved.project == root and type(saved.sessionID) == "string" and saved.sessionID:match("^[%w_-]+$"),
			"Invalid saved OpenCode session"
		)
		context.session_id = saved.sessionID
	end
	if not context.session_id then
		local done, session
		require("config.opencode_http").request("POST", "/session", { title = "Worktree agent" }, function(ok, output)
			if ok then
				local valid, value = pcall(vim.json.decode, output)
				if valid then
					session = value
				end
			end
			done = true
		end, { dir = root, timeout = 5 })
		if
			not vim.wait(6000, function()
				return done
			end, 20)
			or type(session) ~= "table"
			or type(session.id) ~= "string"
			or not session.id:match("^[%w_-]+$")
		then
			vim.notify("Could not create an exact OpenCode session; no terminal launched", vim.log.levels.ERROR)
			return nil
		end
		context.session_id = session.id
	end
	terminal.start(root, context)
	generation = terminal.generation_for(root)
	if not opts.hidden then
		terminal.open(root)
	end
	local bound = vim.wait(10000, function()
		local route = require("config.opencode_handoff").capture_route(root)
		return route and route.generation == generation and route.sessionID == context.session_id
	end, 50)
	if not bound then
		if generation then
			terminal.close_generation(root, generation)
		end
		vim.notify("OpenCode did not bind the requested session; nothing redirected", vim.log.levels.ERROR)
		return nil
	end
	return M.capture(root)
end

function M.setup()
	local startup, layout = vim.env.NVIM_AGENT_HARNESS, vim.env.NVIM_AGENT_LAYOUT == "1"
	local startup_file = vim.env.NVIM_AGENT_STARTUP_FILE
	vim.env.NVIM_AGENT_HARNESS, vim.env.NVIM_AGENT_LAYOUT = nil, nil
	vim.env.NVIM_AGENT_STARTUP_FILE = nil
	local group = vim.api.nvim_create_augroup("agent_sessions", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeHandoffEvent:binding_changed",
		callback = function()
			for root, _ in pairs(require("config.opencode_handoff").active_bindings()) do
				local route = require("config.opencode_handoff").capture_route(root)
				if route then
					local file = M.file(root, "agent-opencode.json")
					local tmp = file .. "." .. vim.fn.getpid()
					assert(
						vim.fn.writefile({ vim.json.encode({ project = root, sessionID = route.sessionID }) }, tmp) == 0
					)
					assert(vim.uv.fs_rename(tmp, file))
				end
			end
		end,
	})
	vim.api.nvim_create_user_command("AgentOpen", function(opts)
		M.open(opts.args ~= "" and opts.args or nil, nil, { new = opts.bang })
	end, {
		nargs = "?",
		bang = true,
		complete = function()
			return harnesses
		end,
		desc = "Open the worktree's exact owned agent",
	})
	vim.api.nvim_create_user_command("AgentStatus", function()
		local route = M.capture(M.root())
		vim.notify(
			route and vim.inspect(route) or "No unambiguous live agent binding",
			vim.log.levels.INFO,
			{ title = "Agent session" }
		)
	end, {})
	require("config.agent_switch").setup()
	if startup then
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
			once = true,
			callback = function()
				vim.schedule(function()
					local root, editor = M.root(), vim.api.nvim_get_current_win()
					if layout then
						require("config.project_terminal").open(root)
						if vim.api.nvim_win_is_valid(editor) then
							vim.api.nvim_set_current_win(editor)
						end
					end
					if startup_file then
						require("config.agent_startup").run(startup_file, root, startup)
					else
						M.open(startup, root)
					end
				end)
			end,
		})
	end
end

return M

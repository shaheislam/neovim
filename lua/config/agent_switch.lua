local M = {}
local drafts = {}

local function native_request(route, method, path)
	local done, success, result = false, false, nil
	require("config.opencode_http").request(method, path, nil, function(ok, output)
		success, result, done = ok, output, true
	end, { dir = route.project, timeout = 3 })
	assert(vim.wait(4000, function()
		return done
	end, 20) and success, "Cannot verify the OpenCode session state")
	return result ~= "" and vim.json.decode(result) or {}
end

function M.quiesce(route, cancel)
	local agent = require("config.agent_session")
	if not agent.resolve(route) then
		return false, "The source owner changed; start the handoff again"
	end
	if route.kind == "acp" then
		local acp = require("config.agent_acp")
		if acp.busy(route.project) and not cancel then
			return false, "Agent is busy; finish it or use :AgentSwitchContinue! to cancel and wait"
		end
		if cancel then
			acp.cancel(route.project)
		end
		if not vim.wait(15000, function()
			return not acp.busy(route.project)
		end, 25) then
			return false, "Cancellation was not acknowledged; the destination was not started"
		end
		if not agent.resolve(route) then
			return false, "The source disconnected; inspect it before continuing"
		end
		return acp.close(route.project)
	end
	local ok, err = pcall(function()
		local session = native_request(route, "GET", "/session/" .. route.sessionID)
		assert(session.id == route.sessionID, "OpenCode did not confirm the exact source session")
		local function idle()
			assert(agent.resolve(route), "The source session changed during handoff")
			local status = native_request(route, "GET", "/session/status")[route.sessionID]
			return not status or status.type == "idle"
		end
		if not idle() then
			assert(cancel, "Agent is busy; finish it or use :AgentSwitchContinue! to cancel and wait")
			native_request(route, "POST", "/session/" .. route.sessionID .. "/abort")
			assert(vim.wait(15000, idle, 100), "OpenCode cancellation was not acknowledged")
		end
		assert(
			require("config.opencode_terminal").close_generation(route.project, route.generation),
			"Source terminal ownership changed"
		)
	end)
	return ok, err
end

function M.begin(harness)
	local agent = require("config.agent_session")
	if not vim.tbl_contains({ "opencode", "claude", "codex", "hermes" }, harness) then
		return false
	end
	local root = agent.root()
	local source = agent.capture(root)
	if not source then
		vim.notify("No unambiguous source agent; open it before handing off", vim.log.levels.WARN)
		return false
	end
	if (source.harness or "opencode") == harness then
		return agent.open(harness, root)
	end
	local file = agent.file(root, "agent-handoff.md")
	local status = vim.system({ "git", "-C", root, "status", "--short" }, { text = true }):wait()
	local lines = {
		"# Agent handoff",
		"",
		"Source: " .. (source.harness or "opencode") .. " / " .. source.sessionID,
		"Destination: " .. harness,
		"",
		"## Objective",
		"Replace this with the current objective.",
		"",
		"## Decisions",
		"Record the decisions the next agent must preserve.",
		"",
		"## Changes",
		status.stdout or "",
		"",
		"## Checks",
		"Record checks already run and their results.",
		"",
		"## Remaining work",
		"Record the next concrete steps.",
		"",
		"Run :AgentSwitchContinue after saving. Use ! to cancel a busy source and wait for acknowledgement.",
	}
	assert(vim.fn.writefile(lines, file) == 0)
	vim.cmd("split " .. vim.fn.fnameescape(file))
	drafts[vim.api.nvim_get_current_buf()] = { root = root, source = source, harness = harness }
	vim.bo.filetype = "markdown"
	return true
end

function M.continue(cancel)
	local draft = drafts[vim.api.nvim_get_current_buf()]
	if not draft then
		vim.notify("Open a handoff with :AgentSwitch first", vim.log.levels.WARN)
		return false
	end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local text = table.concat(lines, "\n")
	if text:find("Replace this with the current objective.", 1, true) then
		vim.notify("Write the objective and inspect the handoff before continuing", vim.log.levels.WARN)
		return false
	end
	vim.cmd.write()
	local stopped, err = M.quiesce(draft.source, cancel)
	if not stopped then
		vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Agent handoff" })
		return false
	end
	local agent = require("config.agent_session")
	local owner = agent.open(draft.harness, draft.root)
	if not owner then
		vim.notify(
			"Destination failed to open; source conversation is saved. Resume it with :AgentOpen "
				.. (draft.source.harness or "opencode"),
			vim.log.levels.ERROR
		)
		return false
	end
	local target = assert(agent.capture(draft.root))
	agent.set_preference(draft.root, draft.harness)
	require("config.opencode_review").rebind(draft.source, target)
	local lib_ok, lib = pcall(require, "diffview.lib")
	for _, view in pairs(lib_ok and lib.views or {}) do
		if view.opencode_review and vim.deep_equal(view.opencode_review.provenance, draft.source) then
			view.opencode_review.provenance = vim.deepcopy(target)
		end
	end
	drafts[vim.fn.bufnr(agent.file(draft.root, "agent-handoff.md"))] = nil
	agent.submit(
		target,
		"Human-approved harness handoff. Re-read the worktree before making changes.\n\n" .. text,
		function(state, detail)
			vim.notify("Handoff " .. state .. (detail and ": " .. detail or ""), vim.log.levels.INFO)
		end
	)
	vim.ui.select(
		{ "Keep feedback with its original session", "Transfer outstanding feedback to the new session" },
		{ prompt = "Review feedback ownership" },
		function(choice)
			if choice == "Transfer outstanding feedback to the new session" then
				local items = vim.tbl_filter(function(item)
					return not item.draft
				end, require("config.annotations").transfer(draft.root, draft.source, target))
				if #items > 0 then
					require("config.opencode_review").submit(items, draft.root)
				end
			end
		end
	)
	return true
end

function M.setup()
	vim.api.nvim_create_user_command("AgentSwitch", function(opts)
		if opts.args ~= "" then
			M.begin(opts.args)
		else
			vim.ui.select(
				{ "opencode", "claude", "codex", "hermes" },
				{ prompt = "Destination harness" },
				function(choice)
					if choice then
						M.begin(choice)
					end
				end
			)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "opencode", "claude", "codex", "hermes" }
		end,
		desc = "Prepare an inspectable harness handoff",
	})
	vim.api.nvim_create_user_command("AgentSwitchContinue", function(opts)
		M.continue(opts.bang)
	end, { bang = true, desc = "Activate the inspected handoff (! cancels and waits)" })
end

return M

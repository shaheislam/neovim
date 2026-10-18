local M = {}

local function claim(path)
	local stat = assert(vim.uv.fs_lstat(path), "Startup request is missing or already consumed")
	assert(
		stat.type == "file" and stat.uid == vim.uv.getuid() and bit.band(stat.mode, 63) == 0,
		"Startup request must be a private, owned regular file"
	)
	local claimed = path .. ".claimed." .. vim.fn.getpid()
	assert(not vim.uv.fs_lstat(claimed), "Startup request was already claimed")
	assert(vim.uv.fs_rename(path, claimed))
	return claimed
end

local function get(path, root)
	local done, success, output
	local cancel = require("config.opencode_http").get(path, function(ok, value)
		success, output, done = ok, value, true
	end, { dir = root, timeout = 5 })
	if not vim.wait(6000, function()
		return done
	end, 20) then
		if cancel then
			cancel()
		end
		error("OpenCode discovery timed out")
	end
	assert(success, "OpenCode discovery failed: " .. tostring(output))
	return vim.json.decode(output)
end

function M.run(path, root, harness)
	local claimed
	local function failed(reason)
		vim.notify(
			"Initial agent prompt stopped: " .. tostring(reason) .. "\nDraft: " .. (claimed or path),
			vim.log.levels.ERROR
		)
	end
	local ok, err = pcall(function()
		claimed = claim(path)
		local payload = vim.json.decode(table.concat(vim.fn.readfile(claimed), "\n"))
		assert(
			payload.version == 1 and payload.project == root and payload.harness == harness,
			"Startup request does not match this project and harness"
		)
		assert(
			vim.tbl_contains({ "opencode", "claude", "codex" }, harness)
				and type(payload.prompt) == "string"
				and type(payload.model) == "string",
			"Invalid startup request"
		)
		local selected = payload.model ~= "" and payload.model or nil
		local model
		if harness == "opencode" and selected then
			local provider, id = selected:match("^([^/]+)/(.+)$")
			assert(provider and id, "Model must use provider/model format")
			local catalog = get("/provider", root)
			local available = false
			for _, item in ipairs(catalog.all or {}) do
				if item.id == provider and vim.tbl_contains(catalog.connected or {}, provider) and item.models[id] then
					available = true
				end
			end
			assert(available, "Requested model is unavailable: " .. selected)
			model = { providerID = provider, modelID = id }
		end
		local agent = require("config.agent_session")
		local opened, reason = agent.open(harness, root, { model = selected })
		assert(opened, reason or "The requested session could not be opened")
		local route = agent.capture(root)
		assert(route and (route.harness or "opencode") == harness, "The requested session did not bind")
		assert(
			route.sessionID == opened.sessionID and route.generation == opened.generation,
			"The startup session ownership changed"
		)
		if vim.trim(payload.prompt) == "" then
			assert(vim.uv.fs_unlink(claimed))
			return
		end
		local command, arguments = payload.prompt:match("^/([^%s]+)%s?(.*)$")
		local skill = harness == "codex" and payload.prompt:match("^(%$[^%s]+)") or nil
		local catalog
		if command or skill then
			if harness == "opencode" then
				catalog = get("/command", root)
			else
				catalog, reason = require("config.agent_acp").commands(route)
				assert(catalog, reason or "The adapter has not published its commands")
			end
			local found = false
			for _, item in ipairs(catalog) do
				if item.name == (skill or command) then
					found = true
				end
			end
			assert(
				found,
				"Unknown command or skill: "
					.. (skill or command)
					.. (harness == "codex" and "; use $name for Codex skills" or "")
			)
		end
		assert(agent.resolve(route), "The session owner changed before submission")
		local finished = false
		local function complete(success, detail)
			if finished then
				return
			end
			finished = true
			if success then
				vim.uv.fs_unlink(claimed)
			else
				failed(
					"Submission may be uncertain; inspect the conversation before retrying. " .. tostring(detail or "")
				)
			end
		end
		if harness ~= "opencode" then
			assert(
				agent.submit(route, payload.prompt, function(state, detail)
					if state == "turn_ended" then
						complete(true)
					elseif
						state == "failed"
						or state == "blocked"
						or state == "uncertain"
						or state == "interrupted"
					then
						complete(false, detail)
					end
				end),
				"The ACP owner rejected the prompt"
			)
		else
			assert(route.sessionID:match("^[%w_-]+$"), "Invalid exact OpenCode session")
			local body = command and { command = command, arguments = arguments, model = selected }
				or { parts = { { type = "text", text = payload.prompt } }, model = model }
			require("config.opencode_http").post(
				"/session/" .. route.sessionID .. (command and "/command" or "/prompt_async"),
				body,
				complete,
				{ dir = root, timeout = command and 120 or 5 }
			)
		end
	end)
	if not ok then
		failed(err)
	end
	return ok
end

return M

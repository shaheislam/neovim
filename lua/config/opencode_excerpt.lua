local M = {}

function M.open(provenance, selection)
	local agent = require("config.agent_session")
	if M.prompt_open or not agent.resolve(provenance) then
		return false
	end
	M.prompt_open = true
	vim.cmd.stopinsert()
	vim.ui.input(
		{ prompt = "Annotation (Enter: send to " .. provenance.sessionID .. "; Esc: cancel): " },
		function(text)
			M.prompt_open = false
			if not text or vim.trim(text) == "" then
				return
			end
			if not agent.resolve(provenance) then
				vim.notify("Annotation not sent: the captured agent session changed", vim.log.levels.WARN)
				return
			end
			local refs = {}
			for _, ref in ipairs(selection.references) do
				refs[#refs + 1] = ref.role
					.. " message "
					.. ref.messageID
					.. (ref.partID and (", part " .. ref.partID) or "")
			end
			local prompt = table.concat({
				"Feedback on a selected conversation excerpt (not a source-file location).",
				"Session: " .. provenance.sessionID,
				"References: " .. table.concat(refs, "; "),
				"Selected text:",
				selection.text,
				"",
				"User annotation:",
				text,
			}, "\n")
			agent.submit(provenance, prompt, function(status)
				vim.notify(
					"Annotation " .. tostring(status),
					status == "submitted" and vim.log.levels.INFO or vim.log.levels.WARN
				)
			end, { return_to_prompt = true })
		end
	)
	return true
end

return M

-- Opt in: AGENT_LIVE_HARNESS=claude|codex nvim --headless -u ./init.lua -l ...
local harness = assert(vim.env.AGENT_LIVE_HARNESS, "set AGENT_LIVE_HARNESS")
assert(harness == "claude" or harness == "codex")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
local acp = require("config.agent_acp")
local owner = assert(acp.open(harness, root, { hidden = true }))
local route = assert(acp.capture(root))
local ended, failure = 0, nil
local function receipt(state, err)
	if state == "turn_ended" then
		ended = ended + 1
	end
	if state == "failed" or state == "uncertain" then
		failure = err or state
	end
end
assert(
	acp.submit(route, "Remember the code REVIEW_7281. Reply exactly ACP_OK. Do not run tools or change files.", receipt)
)
assert(acp.submit(route, "Reply exactly QUEUE_OK. Do not run tools or change files.", receipt))
assert(
	vim.wait(180000, function()
		return ended == 2 or failure
	end, 20),
	"live prompts timed out"
)
assert(not failure, failure)
assert(acp.close(root), "completed session should close")
local restored = assert(acp.open(harness, root, { hidden = true }))
assert(
	restored.sessionID == owner.sessionID and restored.generation ~= owner.generation,
	"new process loads only the exact saved session"
)
assert(not acp.resolve(route), "old ownership stays stale after restore")
local before = table.concat(vim.api.nvim_buf_get_lines(restored.chat.bufnr, 0, -1, false), "\n")
local _, remembered_before = before:gsub("REVIEW_7281", "")
assert(
	acp.submit(
		acp.capture(root),
		"What code did I ask you to remember? Reply with only that code. Do not run tools.",
		receipt
	)
)
assert(
	vim.wait(120000, function()
		return ended == 3 or failure
	end, 20),
	"resumed prompt timed out"
)
assert(not failure, failure)
local text = table.concat(vim.api.nvim_buf_get_lines(restored.chat.bufnr, 0, -1, false), "\n")
local _, remembered_after = text:gsub("REVIEW_7281", "")
assert(remembered_after > remembered_before, "the new reply did not recall the restored conversation")
assert(acp.close(root))
require("config.hotreload").unwatch_directory(root)
vim.fn.delete(root, "rf")
print("PASS " .. harness .. " owned ACP chat, queued turns, subscription login, and exact process-restart resume")

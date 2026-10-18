package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
root = vim.uv.fs_realpath(root)
local destination = vim.env.AGENT_TEST_DESTINATION or "codex"
local source = {
	kind = "acp",
	project = root,
	harness = destination == "hermes" and "claude" or "hermes",
	sessionID = "old",
	generation = "first",
}
local target = { kind = "acp", project = root, harness = destination, sessionID = "new", generation = "second" }
local route, busy, cancelled, closed, launched, preference = source, true, false, false, false, "claude"
local sent, transferred = {}, false
local view = { opencode_review = { base = "unchanged-sha", provenance = source } }
local gitdir =
	vim.trim(vim.system({ "git", "-C", root, "rev-parse", "--absolute-git-dir" }, { text = true }):wait().stdout)
package.loaded["config.agent_session"] = {
	root = function()
		return root
	end,
	capture = function()
		return route
	end,
	resolve = function(value)
		return value == route and value
	end,
	file = function(_, name)
		return gitdir .. "/dotfiles-" .. name
	end,
	open = function(harness)
		assert(closed and not busy, "source must be quiescent and retired before destination launch")
		assert(harness == destination)
		launched, route = true, target
		return target
	end,
	set_preference = function(_, harness)
		assert(launched)
		preference = harness
	end,
	submit = function(value, text)
		assert(value == target)
		sent[#sent + 1] = text
		return true
	end,
}
package.loaded["config.agent_acp"] = {
	busy = function()
		return busy
	end,
	cancel = function()
		cancelled = true
		vim.schedule(function()
			busy = false
		end)
	end,
	close = function()
		assert(not busy)
		closed, route = true, nil
		return true
	end,
}
package.loaded["diffview.lib"] = { views = { view } }
package.loaded["config.annotations"] = {
	transfer = function(_, old, new)
		assert(vim.deep_equal(old, source) and vim.deep_equal(new, target))
		transferred = true
		return { { text = "Send existing feedback" }, { text = "Keep draft feedback", draft = true } }
	end,
}
local switch = require("config.agent_switch")
local feedback
require("config.opencode_review").submit = function(items)
	feedback = items
end
assert(not switch.quiesce(source, false) and not closed and not launched, "busy source cannot be hidden and replaced")
assert(switch.begin(destination))
local draftbuf = vim.api.nvim_get_current_buf()
assert(not switch.continue(false) and not cancelled, "uninspected placeholder handoff cannot launch")
local lines = vim.api.nvim_buf_get_lines(draftbuf, 0, -1, false)
for i, line in ipairs(lines) do
	if line:find("Replace this", 1, true) then
		lines[i] = "Finish the reviewed feature"
	end
end
vim.api.nvim_buf_set_lines(draftbuf, 0, -1, false, lines)
vim.ui.select = function(_, _, callback)
	callback("Transfer outstanding feedback to the new session")
end
assert(switch.continue(true))
assert(cancelled and launched and closed and preference == destination)
assert(view.opencode_review.base == "unchanged-sha" and vim.deep_equal(view.opencode_review.provenance, target))
assert(transferred and #sent == 1 and sent[1]:find("Finish the reviewed feature", 1, true))
assert(#feedback == 1 and feedback[1].text == "Send existing feedback", "handoff transfer must not send drafts")
local native = { kind = "native", project = root, sessionID = "ses_exact", generation = "native" }
route, busy = native, true
local aborted, terminal_closed = false, false
package.loaded["config.opencode_http"] = {
	request = function(method, path, _, cb, opts)
		assert(opts.dir == root)
		if path == "/session/ses_exact" then
			cb(true, vim.json.encode({ id = "ses_exact" }))
		elseif path == "/session/status" then
			cb(true, vim.json.encode(busy and { ses_exact = { type = "busy" } } or {}))
		else
			assert(method == "POST" and path == "/session/ses_exact/abort")
			aborted, busy = true, false
			cb(true, "true")
		end
	end,
}
package.loaded["config.opencode_terminal"] = {
	close_generation = function(_, gen)
		assert(gen == "native" and not busy)
		terminal_closed = true
		return true
	end,
}
assert(not switch.quiesce(native, false) and not terminal_closed)
assert(
	switch.quiesce(native, true) and aborted and terminal_closed,
	"native source abort waits for server idle and closes only its generation"
)
vim.api.nvim_buf_delete(draftbuf, { force = true })
vim.fn.delete(root, "rf")
print("PASS inspected handoff, cancel acknowledgement, single writer, explicit transfer and pinned review")

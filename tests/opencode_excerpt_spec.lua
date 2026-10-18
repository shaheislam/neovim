package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local handoff = require("config.opencode_handoff")
local root = vim.uv.fs_realpath(vim.fn.getcwd())
handoff.__reset()
assert(handoff.register_terminal(root, "generation_one"))
local lease = handoff.receive({ version = 1, type = "hello", directory = root, generation = "generation_one" }).lease
local function bind(session, revision)
	assert(
		handoff.receive({
			version = 1,
			type = "bind",
			directory = root,
			generation = "generation_one",
			lease = lease,
			sessionID = session,
			routeRevision = revision,
		}).status == "handled"
	)
end
bind("ses_one", 1)
local sent, pending, notices = {}, nil, {}
package.loaded["config.agent_session"] = {
	resolve = handoff.resolve_plan_route,
	submit = function(provenance, text, callback)
		assert(handoff.resolve_plan_route(provenance), "submitted a stale route")
		sent[#sent + 1] = { provenance = provenance, text = text }
		callback("submitted")
		return true
	end,
}
vim.notify = function(text)
	notices[#notices + 1] = text
end
vim.ui.input = function(opts, callback)
	assert(opts.prompt:find("ses_one", 1, true) and opts.prompt:find("Esc:", 1, true))
	pending = callback
end
local request = {
	version = 1,
	type = "annotate_selection",
	directory = root,
	generation = "generation_one",
	lease = lease,
	sessionID = "ses_one",
	routeRevision = 1,
	selection = {
		sessionID = "ses_one",
		text = "selected code\nwith Unicode λ",
		mode = "char",
		references = { { messageID = "msg_one", partID = "part_one", role = "assistant" } },
	},
}
local function open()
	pending = nil
	assert(handoff.receive(request).status == "queued", "valid excerpt request was rejected")
	assert(
		vim.wait(1000, function()
			return pending ~= nil
		end, 10),
		"annotation prompt did not open"
	)
end
open()
assert(#sent == 0, "opening a comment prompt sent a message")
pending(nil)
assert(#sent == 0, "cancel sent a message")
open()
pending("   ")
assert(#sent == 0, "empty annotation sent a message")
open()
pending("Explain this choice")
assert(#sent == 1 and sent[1].provenance.sessionID == "ses_one")
assert(sent[1].text:find(request.selection.text, 1, true) and sent[1].text:find("msg_one", 1, true))
assert(sent[1].text:find("Explain this choice", 1, true))
open()
bind("ses_two", 2)
bind("ses_one", 3)
pending("Stale comment")
assert(#sent == 1, "switch-away/back redirected old feedback")
assert(table.concat(notices, "\n"):find("not sent", 1, true), "stale route was not explained")
assert(handoff.receive(request).status == "rejected", "stale revision accepted")
request.routeRevision = 3
request.selection.sessionID = "ses_other"
assert(handoff.receive(request).status == "rejected", "mismatched excerpt session accepted")
request.selection.sessionID = "ses_one"
request.selection.text = string.rep("x", 128 * 1024 + 1)
assert(handoff.receive(request).status == "rejected", "unbounded excerpt accepted")
request.selection.text = "replacement"
assert(handoff.register_terminal(root, "generation_two"))
assert(handoff.receive(request).status == "rejected", "retired terminal accepted an excerpt")
handoff.__reset()
print("PASS excerpt feedback: authenticated route, cancellation, exact submission and stale-route rejection")

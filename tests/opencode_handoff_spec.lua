package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local root = vim.fn.tempname()
local sibling = root .. "-sibling"
assert(vim.fn.mkdir(root, "p") == 1, "failed to create temporary project")
assert(vim.fn.mkdir(sibling, "p") == 1, "failed to create sibling project")
root = canonical(root)
sibling = canonical(sibling)
assert(vim.fn.writefile({ "alpha" }, root .. "/alpha.txt") == 0, "failed to create alpha file")
assert(vim.fn.writefile({ "beta" }, root .. "/beta.txt") == 0, "failed to create beta file")
assert(vim.fn.writefile({ "# Plan" }, root .. "/.plan.md") == 0, "failed to create plan")
assert(vim.fn.writefile({ "outside" }, sibling .. "/outside.txt") == 0, "failed to create outside file")
assert(vim.uv.fs_symlink(sibling, root .. "/escape"), "failed to create symlink escape")

local reloads = {}
local handoffs = {}
local terminal_closes = {}
local binding_changes = 0

local binding_group = vim.api.nvim_create_augroup("opencode_handoff_spec_bindings", { clear = true })
vim.api.nvim_create_autocmd("User", {
	group = binding_group,
	pattern = "OpencodeHandoffEvent:binding_changed",
	callback = function()
		binding_changes = binding_changes + 1
	end,
})

package.loaded["config.hotreload"] = {
	reload_paths = function(paths)
		table.insert(reloads, vim.deepcopy(paths))
	end,
}
package.loaded["config.diffview_idle"] = {
	open_handoff = function(options)
		table.insert(handoffs, vim.deepcopy(options))
		return { status = "opened", reason = "plan_focused" }
	end,
}
package.loaded["config.opencode_terminal"] = {
	close_generation = function(project, generation)
		table.insert(terminal_closes, { project = project, generation = generation })
		return true
	end,
}

local handoff = dofile("lua/config/opencode_handoff.lua")
handoff.__reset()
handoff.setup()
assert(vim.v.servername ~= "", "handoff setup starts an RPC server even outside tmux")

local generation = "gen_0123456789abcdef"
handoff.register_terminal(root, generation)
eq(handoff.active_bindings(), {}, "an unbound terminal is not exposed as an active session")
eq(binding_changes, 0, "registering an unbound generation does not report a binding change")

local rejected = handoff.receive({
	version = 1,
	type = "hello",
	directory = root,
	generation = "gen_stale",
})
eq(rejected.status, "rejected", "a stale terminal generation is rejected")
eq(rejected.reason, "stale_generation", "generation rejection is explicit")

local hello = handoff.receive({
	version = 1,
	type = "hello",
	directory = root,
	generation = generation,
})
eq(hello.status, "handled", "the owning terminal receives a native lease")
assert(type(hello.lease) == "string" and #hello.lease >= 16, "native lease is opaque and non-empty")
eq(hello.routeRevision, 0, "a new route starts at revision zero")

local bound = handoff.receive({
	version = 1,
	type = "bind",
	directory = root,
	generation = generation,
	lease = hello.lease,
	sessionID = "ses_one",
	routeRevision = 1,
})
eq(bound.status, "handled", "the lease authenticates first session binding")
eq(handoff.active_bindings(), {
	[root] = {
		project = root,
		generation = generation,
		sessionID = "ses_one",
		routeRevision = 1,
	},
}, "the exact live binding is exposed as an immutable snapshot")
eq(binding_changes, 1, "the first exact bind reports one binding change")

local mutated_snapshot = handoff.active_bindings()
mutated_snapshot[root].sessionID = "mutated"
eq(handoff.active_bindings()[root].sessionID, "ses_one", "mutating a binding snapshot cannot alter handoff state")

local repeated_bind = handoff.receive({
	version = 1,
	type = "bind",
	directory = root,
	generation = generation,
	lease = hello.lease,
	sessionID = "ses_one",
	routeRevision = 1,
})
eq(repeated_bind.status, "handled", "repeating the exact current binding remains idempotent")
eq(binding_changes, 1, "repeating the current binding does not report a false change")

local replay = handoff.receive({
	version = 1,
	type = "bind",
	directory = root,
	generation = generation,
	lease = hello.lease,
	sessionID = "ses_replayed",
	routeRevision = 1,
})
eq(replay.status, "rejected", "the same revision cannot retarget a session")
eq(replay.reason, "stale_route_revision", "session replay fails closed")
eq(binding_changes, 1, "a rejected replay does not report a binding change")

local switched = handoff.receive({
	version = 1,
	type = "bind",
	directory = root,
	generation = generation,
	lease = hello.lease,
	sessionID = "ses_two",
	routeRevision = 2,
})
eq(switched.status, "handled", "a newer revision can switch the active TUI session")
eq(handoff.active_bindings()[root].sessionID, "ses_two", "a newer route revision replaces the exposed session")
eq(handoff.active_bindings()[root].routeRevision, 2, "the exposed binding follows the monotonic route revision")
eq(binding_changes, 2, "a real session switch reports one additional binding change")

local function batch(paths, overrides)
	return handoff.receive(vim.tbl_extend("force", {
		version = 1,
		type = "idle_batch",
		directory = root,
		generation = generation,
		lease = hello.lease,
		sessionID = "ses_two",
		routeRevision = 2,
		paths = paths,
	}, overrides or {}))
end

eq(batch({ root .. "/alpha.txt" }, { sessionID = "ses_one" }).reason, "wrong_session", "old-session idle is rejected")
eq(batch({ sibling .. "/outside.txt" }).reason, "path_outside_project", "a similarly prefixed sibling is rejected")
eq(batch({ root .. "/../" .. vim.fn.fnamemodify(sibling, ":t") .. "/outside.txt" }).reason, "path_outside_project", "dot-dot escape is rejected")
eq(batch({ root .. "/escape/new.txt" }).reason, "path_outside_project", "a nonexistent file below a symlinked parent is rejected")

local accepted = batch({ "alpha.txt", ".plan.md", "alpha.txt", "beta.txt" })
eq(accepted.status, "queued", "a valid idle batch is queued onto Neovim's main loop")

assert(vim.wait(1000, function()
	return #handoffs == 1
end, 10), "queued handoff did not run")

eq(terminal_closes, {}, "idle keeps the bridge-owned terminal generation open")
eq(reloads, { { root .. "/alpha.txt", root .. "/.plan.md", root .. "/beta.txt" } }, "idle reloads one ordered deduplicated batch")
eq(canonical(vim.api.nvim_buf_get_name(0)), root .. "/beta.txt", "idle focuses the latest changed non-plan file")

local quickfix = vim.fn.getqflist()
eq(#quickfix, 3, "quickfix contains every changed file without opening it")
eq(vim.fn.getqflist({ winid = 0 }).winid, 0, "quickfix remains closed")

eq(handoffs[1].project_dir, root, "plan handoff targets the bound project")
eq(handoffs[1].open_diff, true, "a changed root plan refreshes Diffview")
eq(handoffs[1].provenance.kind, "native", "plan records native provenance")
eq(handoffs[1].provenance.sessionID, "ses_two", "plan provenance records the exact session")
eq(handoffs[1].provenance.generation, generation, "plan provenance records the exact terminal generation")

vim.bo.modified = true
eq(batch({ "alpha.txt" }).status, "queued", "a batch received over a modified buffer remains queued")
local deferred_attempt_serviced = false
vim.schedule(function()
	deferred_attempt_serviced = true
end)
assert(vim.wait(1000, function()
	return deferred_attempt_serviced
end, 10), "deferred handoff callback was not serviced")
eq(#reloads, 1, "a modified current buffer defers reload and focus work")
eq(terminal_closes, {}, "a deferred idle handoff keeps the terminal generation open")
vim.bo.modified = false
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })
assert(vim.wait(1000, function()
	return #reloads == 2
end, 10), "deferred handoff did not retry after the editor became safe")
eq(reloads[2], { root .. "/alpha.txt" }, "retry preserves the deferred path batch")
eq(terminal_closes, {}, "a retried idle handoff keeps the terminal generation open")

local route = handoff.resolve_plan_route(handoffs[1].provenance)
eq(route.sessionID, "ses_two", "a live native plan route resolves to its exact session")

vim.bo.modified = true
eq(batch({ "alpha.txt" }).status, "queued", "the old route can queue work while the editor is unsafe")
local old_route_attempt_serviced = false
vim.schedule(function()
	old_route_attempt_serviced = true
end)
assert(vim.wait(1000, function()
	return old_route_attempt_serviced
end, 10), "old-route deferred callback was not serviced")
eq(#reloads, 2, "old-route work remains deferred while the editor is unsafe")

local rebound = handoff.receive({
	version = 1,
	type = "bind",
	directory = root,
	generation = generation,
	lease = hello.lease,
	sessionID = "ses_three",
	routeRevision = 3,
})
eq(rebound.status, "handled", "a newer route replaces the session while old work is deferred")
eq(handoff.active_bindings()[root].sessionID, "ses_three", "the replacement route becomes active")
eq(handoff.resolve_plan_route(handoffs[1].provenance), nil, "the previous route provenance becomes stale")

vim.bo.modified = false
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })
local replaced_route_retry_serviced = false
vim.schedule(function()
	replaced_route_retry_serviced = true
end)
assert(vim.wait(1000, function()
	return replaced_route_retry_serviced
end, 10), "replacement-route retry callback was not serviced")
eq(#reloads, 2, "replacing a route discards accepted pending work from the old route")

eq(batch({ "beta.txt" }, { sessionID = "ses_three", routeRevision = 3 }).status, "queued", "the replacement route queues fresh work")
assert(vim.wait(1000, function()
	return #reloads == 3
end, 10), "fresh work for the replacement route did not run")
eq(reloads[3], { root .. "/beta.txt" }, "the replacement route processes only its fresh path batch")
eq(terminal_closes, {}, "route replacement and fresh idle work keep the terminal generation open")

handoff.unregister_terminal(root, generation)
eq(handoff.resolve_plan_route(handoffs[1].provenance), nil, "native plan provenance fails closed after terminal exit")
eq(handoff.active_bindings(), {}, "terminal exit removes the active binding")
eq(binding_changes, 4, "removing a bound terminal reports one binding change")
eq(handoff.unregister_terminal(root, generation), false, "a stale unregister remains rejected")
eq(binding_changes, 4, "a rejected unregister does not report a binding change")

local encoded = vim.base64.encode(vim.json.encode({
	version = 1,
	type = "hello",
	directory = root,
	generation = generation,
}))
local decoded_result = vim.json.decode(handoff.receive_base64(encoded))
eq(decoded_result.status, "rejected", "the real base64 RPC entrypoint decodes and dispatches its payload")
eq(decoded_result.reason, "unbound_project", "base64 transport reaches ownership validation")

local oversized_result = vim.json.decode(handoff.receive_base64(string.rep("A", 512 * 1024 + 1)))
eq(oversized_result.status, "rejected", "oversized RPC payloads are rejected")
eq(oversized_result.reason, "invalid_encoding", "oversized RPC rejection happens before decoding")

handoff.__reset()
pcall(vim.api.nvim_del_augroup_by_name, "opencode_handoff_spec_bindings")
assert(vim.fn.delete(root, "rf") == 0, "failed to remove temporary project")
assert(vim.fn.delete(sibling, "rf") == 0, "failed to remove sibling project")

print("PASS native OpenCode handoff ownership, routing, path safety, and idle UI")

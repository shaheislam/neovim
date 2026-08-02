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

eq(terminal_closes, { { project = root, generation = generation } }, "idle closes only the bridge-owned terminal generation")
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

local route = handoff.resolve_plan_route(handoffs[1].provenance)
eq(route.sessionID, "ses_two", "a live native plan route resolves to its exact session")
handoff.unregister_terminal(root, generation)
eq(handoff.resolve_plan_route(handoffs[1].provenance), nil, "native plan provenance fails closed after terminal exit")

local encoded = vim.base64.encode(vim.json.encode({
	version = 1,
	type = "hello",
	directory = root,
	generation = generation,
}))
local decoded_result = vim.json.decode(handoff.receive_base64(encoded))
eq(decoded_result.status, "rejected", "the real base64 RPC entrypoint decodes and dispatches its payload")
eq(decoded_result.reason, "unbound_project", "base64 transport reaches ownership validation")

handoff.__reset()
assert(vim.fn.delete(root, "rf") == 0, "failed to remove temporary project")
assert(vim.fn.delete(sibling, "rf") == 0, "failed to remove sibling project")

print("PASS native OpenCode handoff ownership, routing, path safety, and idle UI")

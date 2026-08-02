package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local original_env = {
	pane = vim.env.TMUX_PANE,
	helper = vim.env.OPENCODE_TMUX_STATE_HELPER,
	disabled = vim.env.OPENCODE_TMUX_STATE_DISABLE,
}

vim.env.TMUX_PANE = "%77"
vim.env.OPENCODE_TMUX_STATE_HELPER = "/tmp/tmux-agent-state-spec"
vim.env.OPENCODE_TMUX_STATE_DISABLE = nil

local bindings = {}
local job_pids = {}

package.loaded["config.opencode_handoff"] = {
	active_bindings = function()
		return vim.deepcopy(bindings)
	end,
}
package.loaded["config.opencode_terminal"] = {
	job_pid_for = function(project, generation)
		return job_pids[project .. "\0" .. generation]
	end,
}

package.loaded["config.opencode_status"] = nil
local status = dofile("lua/config/opencode_status.lua")

local async_calls = {}
local running = {}
local sync_calls = {}
local stopped = {}
local waited = {}
local next_job = 100
local helper_available = true

status.__set_test_hooks({
	helper_path = function()
		return helper_available and "/tmp/tmux-agent-state-spec" or nil
	end,
	getpid = function()
		return 4242
	end,
	owner_nonce = function()
		return "spec"
	end,
	jobstart = function(argv, opts)
		next_job = next_job + 1
		local item = { id = next_job, argv = vim.deepcopy(argv), opts = opts }
		table.insert(async_calls, item)
		table.insert(running, item)
		return item.id
	end,
	system = function(argv)
		table.insert(sync_calls, vim.deepcopy(argv))
		return ""
	end,
	jobstop = function(job)
		table.insert(stopped, job)
		return 1
	end,
	jobwait = function(jobs, timeout)
		table.insert(waited, { jobs = vim.deepcopy(jobs), timeout = timeout })
		return { -3 }
	end,
})

local function emit(pattern, properties)
	vim.api.nvim_exec_autocmds("User", {
		pattern = pattern,
		modeline = false,
		data = { event = { properties = properties or {} } },
	})
end

local function finish_one()
	local item = table.remove(running, 1)
	assert(item, "expected one in-flight tmux-agent-state job")
	item.opts.on_exit(item.id, 0)
	return item
end

local function last_async_argv()
	assert(#async_calls > 0, "expected an asynchronous helper call")
	return async_calls[#async_calls].argv
end

local function bind(project, generation, session_id, job_pid)
	bindings[project] = {
		project = project,
		generation = generation,
		sessionID = session_id,
		routeRevision = 1,
	}
	job_pids[project .. "\0" .. generation] = job_pid
end

status.setup()
local autocmd_count = #vim.api.nvim_get_autocmds({ group = "opencode_status_bridge" })
status.setup()
eq(#vim.api.nvim_get_autocmds({ group = "opencode_status_bridge" }), autocmd_count, "setup is idempotent")

emit("OpencodeEvent:server.connected")
eq(vim.g.opencode_status, "connected", "server connection is lualine-only without an exact binding")
eq(last_async_argv()[2], "clear", "server connection never publishes a tmux color")
finish_one()

bind("/tmp/a", "gen-a", "ses-bound", 500)
emit("OpencodeEvent:session.status", { sessionID = "ses-unrelated", status = { type = "busy" } })
eq(last_async_argv()[2], "clear", "an unrelated shared-server session fails closed")
finish_one()

bindings = {}
emit("OpencodeEvent:session.status", { sessionID = "ses-bound", status = { type = "busy" } })
finish_one()
bind("/tmp/a", "gen-a", "ses-bound", 500)
emit("OpencodeHandoffEvent:binding_changed")
local first_publish = last_async_argv()
eq(first_publish[2], "publish", "a cached pre-bind status publishes once its exact binding arrives")
eq(first_publish[3], "%77", "the helper targets the containing tmux pane")
eq(first_publish[4], "nvim", "the helper records the Neovim source")
eq(first_publish[6], "busy", "a non-idle exact status maps to busy")
eq(first_publish[9], "4242", "the Neovim pid is the pane ownership proof")
eq(first_publish[10], "500", "the exact bound terminal job is published")
local owner = first_publish[5]
assert(owner:match("^nvim:4242:"), "the pane owner token is process-scoped and opaque")

emit("OpencodeEvent:message.updated", {
	info = { sessionID = "ses-bound", providerID = "openai", modelID = "o3" },
})
eq(#async_calls, 4, "an event arriving during publish is coalesced instead of racing it")
finish_one()
eq(#async_calls, 5, "the coalesced recompute runs once after the current helper exits")
local model_publish = last_async_argv()
eq(model_publish[5], owner, "every publish from one Neovim instance uses the same owner")
eq(model_publish[7], "openai", "provider identity is forwarded independently")
eq(model_publish[8], "o3", "model identity is forwarded independently")
finish_one()

emit("OpencodeEvent:session.status", { sessionID = "ses-unrelated", status = { type = "idle" } })
eq(last_async_argv()[6], "busy", "an unrelated idle event cannot recolor an exact busy binding")
finish_one()

bindings["/tmp/a"].sessionID = "ses-new"
bindings["/tmp/a"].routeRevision = 2
emit("OpencodeHandoffEvent:binding_changed")
eq(last_async_argv()[2], "clear", "a rebind fails closed until the replacement session reports status")
finish_one()

emit("OpencodeEvent:message.updated", {
	info = { sessionID = "ses-new", providerID = "openai", modelID = "o3" },
})
emit("OpencodeEvent:session.status", { sessionID = "ses-new", status = { type = "idle" } })
finish_one()
local idle_publish = last_async_argv()
eq(idle_publish[2], "publish", "a fresh exact idle status publishes after rebind")
eq(idle_publish[6], "idle", "idle is preserved once every binding is known idle")
eq(idle_publish[7], "openai", "idle color receives the authoritative provider id")
eq(idle_publish[8], "o3", "idle color receives the model id fallback")
finish_one()

bind("/tmp/b", "gen-b", "ses-b", 400)
emit("OpencodeEvent:message.updated", {
	info = { sessionID = "ses-b", providerID = "google", modelID = "gemini-2.5" },
})
eq(last_async_argv()[2], "clear", "idle is withheld while any exact bound session still has unknown status")
emit("OpencodeEvent:session.status", { sessionID = "ses-b", status = { type = "streaming" } })
finish_one()
local multi_publish = last_async_argv()
eq(multi_publish[6], "busy", "busy wins across multiple exact projects in one Neovim pane")
eq(multi_publish[7], "google", "the newest busy session supplies provider metadata")
eq(multi_publish[8], "gemini-2.5", "the newest busy session supplies model metadata")
eq(multi_publish[10], "400,500", "every live exact terminal job pid is sorted into the proof")
finish_one()

emit("OpencodeEvent:session.deleted", { info = { id = "ses-b" } })
eq(last_async_argv()[2], "clear", "deleting an exact bound session drops its cache and fails closed")
finish_one()

emit("OpencodeEvent:server.instance.disposed")
eq(vim.g.opencode_status, nil, "server disposal clears the exact lualine aggregate")
eq(last_async_argv()[2], "clear", "server disposal clears the pane fact")
finish_one()
emit("OpencodeEvent:server.connected")
eq(last_async_argv()[2], "clear", "reconnect cannot republish pre-disposal status")
finish_one()

emit("OpencodeEvent:session.status", { sessionID = "ses-new", status = { type = "busy" } })
assert(#running == 1, "a fresh publish is in flight before shutdown")
vim.api.nvim_exec_autocmds("VimLeavePre", { modeline = false })
eq(stopped, { running[1].id }, "shutdown stops the in-flight helper before clearing")
eq(waited[1].jobs, { running[1].id }, "shutdown waits only for the tracked helper")
eq(sync_calls[#sync_calls], {
	"/tmp/tmux-agent-state-spec",
	"clear",
	"%77",
	owner,
}, "shutdown synchronously owner-clears through the validated helper")

status.__reset()
async_calls = {}
running = {}
sync_calls = {}
helper_available = false
status.__set_test_hooks({
	helper_path = function()
		return nil
	end,
	getpid = function()
		return 4242
	end,
	owner_nonce = function()
		return "missing"
	end,
	jobstart = function(argv)
		table.insert(async_calls, argv)
		return 1
	end,
	system = function(argv)
		table.insert(sync_calls, argv)
		return ""
	end,
})
status.setup()
emit("OpencodeEvent:session.status", { sessionID = "ses-new", status = { type = "busy" } })
eq(#async_calls, 0, "a missing dotfiles helper degrades without writing partial pane state")

status.__reset()
helper_available = true
vim.env.OPENCODE_TMUX_STATE_DISABLE = "1"
status.__set_test_hooks({
	helper_path = function()
		return "/tmp/tmux-agent-state-spec"
	end,
	getpid = function()
		return 4242
	end,
	owner_nonce = function()
		return "disabled"
	end,
	system = function(argv)
		table.insert(sync_calls, vim.deepcopy(argv))
		return ""
	end,
})
status.setup()
eq(sync_calls[#sync_calls][2], "clear", "the rollback kill switch synchronously clears any owned pane fact")

status.__reset()
vim.env.TMUX_PANE = original_env.pane
vim.env.OPENCODE_TMUX_STATE_HELPER = original_env.helper
vim.env.OPENCODE_TMUX_STATE_DISABLE = original_env.disabled
package.loaded["config.opencode_handoff"] = nil
package.loaded["config.opencode_terminal"] = nil
package.loaded["config.opencode_status"] = nil

print("PASS exact-session OpenCode status aggregation and owner-safe tmux publication")

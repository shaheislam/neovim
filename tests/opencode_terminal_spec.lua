package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

-- Accurate fake ToggleTerm registry: Terminal:new() does NOT register a
-- terminal (only spawn() does, matching toggleterm.nvim/lua/toggleterm/
-- terminal.lua), "hidden" only filters get_all()/get() rather than meaning
-- UI-closed, and shutdown() closes+deletes+deregisters.
local registry = {}
local next_id = 1

local function make_terminal(term)
	term.id = next_id
	next_id = next_id + 1
	term.hidden = term.hidden or false
	term.__window_open = false
	term.bufnr = vim.api.nvim_create_buf(false, true)

	function term:is_open()
		return self.__window_open == true
	end

	function term:spawn()
		self.__spawn_count = (self.__spawn_count or 0) + 1
		registry[self.id] = self
		if self.on_create then
			self:on_create()
		end
	end

	function term:open(size)
		self.__open_count = (self.__open_count or 0) + 1
		self.__last_open_size = size
		if not registry[self.id] then
			self:spawn()
		end
		self.__window_open = true
	end

	function term:focus()
		self.__focus_count = (self.__focus_count or 0) + 1
	end

	function term:toggle(size)
		if self:is_open() then
			self:close()
		else
			self:open(size)
		end
	end

	function term:close()
		self.__window_open = false
	end

	function term:shutdown()
		self.__shutdown_count = (self.__shutdown_count or 0) + 1
		if self:is_open() then
			self:close()
		end
		if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
			pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
		end
		registry[self.id] = nil
		self.__alive = false
	end

	function term:simulate_exit(exit_code)
		self:on_exit(self.job_id, exit_code)
		self.__alive = false
		if self.close_on_exit then
			if self:is_open() then
				self:close()
			end
			if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
				vim.api.nvim_buf_delete(self.bufnr, { force = true })
			end
			registry[self.id] = nil
		end
	end

	return term
end

package.loaded["toggleterm.terminal"] = {
	Terminal = {
		new = function(_, term)
			return make_terminal(term)
		end,
	},
	get_all = function(include_hidden)
		local result = {}
		for _, term in pairs(registry) do
			if include_hidden or not term.hidden then
				table.insert(result, term)
			end
		end
		table.sort(result, function(a, b)
			return a.id < b.id
		end)
		return result
	end,
}

local terminal_adapter = dofile("lua/config/opencode_terminal.lua")
package.loaded["config.opencode_terminal"] = terminal_adapter

-- Deterministic liveness/write hooks: __alive is a plain flag the test sets
-- directly instead of needing a real terminal job, and sent_payloads
-- captures exact bytes without needing a real PTY channel.
local sent_payloads = {}
terminal_adapter.__set_test_hooks({
	terminal_live = function(term)
		return term.__alive == true
	end,
	terminal_job_pid = function(term)
		return term.__job_pid
	end,
	terminal_write = function(term, payload, on_result)
		if term.__alive ~= true then
			on_result(false, "OpenCode terminal is not running")
			return
		end
		table.insert(sent_payloads, { term = term, payload = payload })
		on_result(true)
	end,
})

local function setup_adapter(overrides)
	registry = {}
	terminal_adapter.__reset()
	terminal_adapter.setup(vim.tbl_extend("force", {
		display_name = "OpenCode",
		launch = function(dir)
			return {
				cmd = "TESTCMD --dir " .. dir,
				env = { OPENCODE_TEST_REVISION = "1" },
				clear_env = false,
			}
		end,
		project_root = function(explicit_dir)
			return explicit_dir or "/tmp/opencode-terminal-spec/project-a"
		end,
		size = function()
			return 42
		end,
		notify_title = "opencode-test",
		ready_timeout_ms = 60,
		adopted_ready_timeout_ms = 30,
		generation = function()
			return "test-generation"
		end,
	}, overrides or {}))
end

-- ===== Section 1: cache reuse across repeated resolution =====

setup_adapter()
local term1 = terminal_adapter.get_terminal("/tmp/opencode-terminal-spec/project-a")
term1.__alive = true
term1:open(10)
local term2 = terminal_adapter.get_terminal("/tmp/opencode-terminal-spec/project-a")
assert(term1 == term2, "repeated resolution for the same project reuses the same terminal object")
eq(#package.loaded["toggleterm.terminal"].get_all(true), 1, "no duplicate terminal was registered")

print("PASS repeated resolution reuses the cached terminal")

-- ===== Section 2: reconciliation adopts the live/open duplicate =====

setup_adapter()
local dir = "/tmp/opencode-terminal-spec/project-b"
local cmd = "TESTCMD --dir " .. dir
local Terminal = require("toggleterm.terminal").Terminal
local launch_env = { OPENCODE_TEST_REVISION = "1", OPENCODE_NVIM_GENERATION = "test-generation" }

local legacy_open = Terminal:new({
	cmd = cmd,
	dir = dir,
	display_name = "OpenCode",
	hidden = true,
	env = vim.deepcopy(launch_env),
	clear_env = false,
})
legacy_open.__alive = true
legacy_open:open(50)

local legacy_hidden = Terminal:new({
	cmd = cmd,
	dir = dir,
	display_name = "OpenCode",
	hidden = true,
	env = vim.deepcopy(launch_env),
	clear_env = false,
})
legacy_hidden.__alive = true
legacy_hidden:spawn() -- live, but never opened -> UI-closed duplicate

eq(#package.loaded["toggleterm.terminal"].get_all(true), 2, "two pre-existing candidates are registered before adoption")

local adopted = terminal_adapter.get_terminal(dir)
assert(adopted == legacy_open, "reconciliation adopts the live, UI-open candidate over a live-but-hidden one")
assert(registry[legacy_open.id] ~= nil, "the adopted, UI-open terminal is left running")
assert(registry[legacy_hidden.id] == nil, "the live-but-UI-closed duplicate is shut down")

print("PASS reconciliation adopts the live UI-open duplicate and retires the hidden one")

-- ===== Section 3: dead terminal with a valid buffer is reconstructed =====

setup_adapter()
local dead_dir = "/tmp/opencode-terminal-spec/project-c"
local dead_term = terminal_adapter.get_terminal(dead_dir)
dead_term.__alive = true
terminal_adapter.open(dead_dir)
assert(vim.api.nvim_buf_is_valid(dead_term.bufnr), "the original terminal has a valid buffer after opening")

dead_term.__alive = false -- job died; buffer/window still present, matching ToggleTerm's real behavior
local reopened = terminal_adapter.open(dead_dir)
assert(reopened ~= dead_term, "a dead terminal with a valid buffer is replaced, not just reopened")
assert(registry[dead_term.id] == nil, "the dead terminal was shut down rather than left registered")

print("PASS opening a dead terminal reconstructs it instead of redisplaying a stale buffer")

-- ===== Section 4: split readiness marker across two stdout chunks =====

setup_adapter()
local split_dir = "/tmp/opencode-terminal-spec/project-d"
sent_payloads = {}
local split_result
local split_win = vim.api.nvim_get_current_win()
terminal_adapter.send("hello", {
	dir = split_dir,
	on_success = function()
		split_result = "success"
	end,
	on_failure = function(message)
		split_result = "failure: " .. message
	end,
})

local split_term = terminal_adapter.get_terminal(split_dir)
eq(split_term.__spawn_count, 1, "a cold send spawns the terminal process exactly once")
assert(not split_term:is_open(), "a cold send leaves the spawned terminal UI closed")
eq(vim.api.nvim_get_current_win(), split_win, "a cold send does not change the current Neovim window")
split_term.__alive = true
eq(split_result, nil, "the request stays queued until the terminal is marked ready")

split_term:on_stdout(split_term.job_id, { "\27[?" })
eq(split_result, nil, "half of the ready marker does not mark the terminal ready")
split_term:on_stdout(split_term.job_id, { "2004h" })
eq(split_result, "success", "the remainder of a split ready marker flushes the queued request exactly once")
eq(#sent_payloads, 1, "the queued payload is written exactly once")
eq(sent_payloads[1].payload, "\27[200~hello\27[201~", "the exact bracketed-paste payload is sent unchanged")

print("PASS a ready marker split across stdout chunks still flushes exactly once")

-- ===== Section 5: fresh spawn fails closed if the marker never arrives =====

setup_adapter({ ready_timeout_ms = 30 })
local timeout_dir = "/tmp/opencode-terminal-spec/project-e"
local timeout_result
terminal_adapter.send("hello", {
	dir = timeout_dir,
	on_success = function()
		timeout_result = "success"
	end,
	on_failure = function(message)
		timeout_result = "failure: " .. message
	end,
})
local timeout_term = terminal_adapter.get_terminal(timeout_dir)
timeout_term.__alive = true

vim.wait(200, function()
	return timeout_result ~= nil
end, 5)
assert(timeout_result, "a fresh spawn that never emits the ready marker eventually fails the queued request")
assert(timeout_result:match("^failure:"), "a fresh spawn fails closed rather than assuming readiness")

print("PASS a fresh spawn without a ready marker fails closed after its timeout")

-- ===== Section 6: adopted legacy terminal gets a short assume-ready fallback =====

setup_adapter({ adopted_ready_timeout_ms = 20 })
local adopt_dir = "/tmp/opencode-terminal-spec/project-f"
local adopt_cmd = "TESTCMD --dir " .. adopt_dir
local legacy = Terminal:new({
	cmd = adopt_cmd,
	dir = adopt_dir,
	display_name = "OpenCode",
	hidden = true,
	env = { OPENCODE_TEST_REVISION = "1", OPENCODE_NVIM_GENERATION = "test-generation" },
	clear_env = false,
})
legacy.__alive = true
legacy:open(50) -- live and UI-open, but never marked _nvim_mini_ready (pre-adapter generation)

local adopted_term = terminal_adapter.get_terminal(adopt_dir)
assert(adopted_term == legacy, "the pre-existing live terminal is adopted rather than recreated")
assert(not adopted_term._nvim_mini_ready, "an adopted terminal's readiness is unknown immediately after adoption")

local adopt_result
terminal_adapter.send("hello", {
	dir = adopt_dir,
	on_success = function()
		adopt_result = "success"
	end,
	on_failure = function(message)
		adopt_result = "failure: " .. message
	end,
})

vim.wait(200, function()
	return adopt_result ~= nil
end, 5)
eq(adopt_result, "success", "a live adopted terminal assumes readiness after its short fallback and flushes its queue")

print("PASS an adopted live terminal becomes ready via the short fallback instead of hanging forever")

-- ===== Section 7: process exit fails pending, finalizes, and wipes the buffer =====

local natural_exits = {}
setup_adapter({
	on_exit = function(_, project, generation, code)
		table.insert(natural_exits, { project = project, generation = generation, code = code })
	end,
})
local exit_dir = "/tmp/opencode-terminal-spec/project-g"
local exit_result
terminal_adapter.send("hello", {
	dir = exit_dir,
	on_success = function()
		exit_result = "success"
	end,
	on_failure = function(message)
		exit_result = "failure: " .. message
	end,
})
local exit_term = terminal_adapter.get_terminal(exit_dir)
exit_term.__alive = true

exit_term:simulate_exit(1)
assert(exit_result, "the queued request is failed when the terminal process exits")
assert(exit_result:match("^failure:"), "process exit fails the request rather than silently dropping it")
eq(exit_term._nvim_mini_ready, false, "readiness is reset to false on exit")
assert(not vim.api.nvim_buf_is_valid(exit_term.bufnr), "natural process exit wipes the OpenCode terminal buffer")
eq(terminal_adapter.generation_for(exit_dir), nil, "natural process exit releases the terminal generation")
eq(#natural_exits, 1, "natural process exit finalizes external lifecycle exactly once")
exit_term:on_exit(exit_term.job_id, 1)
eq(#natural_exits, 1, "a repeated late process-exit callback cannot finalize twice")

print("PASS process exit fails pending requests, finalizes once, and wipes its buffer")

-- ===== Section 8: a command/project change retires the old generation first =====

setup_adapter()
local order = {}
local change_dir = "/tmp/opencode-terminal-spec/project-h"
local current_cmd = "TESTCMD --dir " .. change_dir .. " --rev 1"
terminal_adapter.setup({
	display_name = "OpenCode",
	launch = function()
		return {
			cmd = current_cmd,
			env = { OPENCODE_TEST_REVISION = "1" },
			clear_env = false,
		}
	end,
	project_root = function(explicit_dir)
		return explicit_dir or change_dir
	end,
	size = function()
		return 42
	end,
	ready_timeout_ms = 60,
	adopted_ready_timeout_ms = 30,
})

local original_term = terminal_adapter.get_terminal(change_dir)
original_term.__alive = true
local original_shutdown = original_term.shutdown
original_term.shutdown = function(self)
	table.insert(order, "shutdown-old")
	return original_shutdown(self)
end
terminal_adapter.open(change_dir)

current_cmd = "TESTCMD --dir " .. change_dir .. " --rev 2"
local new_term = terminal_adapter.get_terminal(change_dir)
table.insert(order, "create-new")

assert(new_term ~= original_term, "changing the resolved command creates a new terminal generation")
eq(order, { "shutdown-old", "create-new" }, "the old generation is retired before the new one is created")
assert(registry[original_term.id] == nil, "the retired terminal is removed from the registry")

print("PASS a command/project change retires the old terminal before creating the new one")

-- ===== Section 9: environment revisions and registry reconciliation =====

setup_adapter()
local env_dir = "/tmp/opencode-terminal-spec/project-env"
local current_env = { OPENCODE_TEST_REVISION = "1", OPENCODE_SERVER_PASSWORD = "password-1" }
terminal_adapter.setup({
	display_name = "OpenCode",
	launch = function(dir)
		return {
			cmd = "TESTCMD --dir " .. dir,
			env = vim.deepcopy(current_env),
			clear_env = false,
		}
	end,
	project_root = function(explicit_dir)
		return explicit_dir or env_dir
	end,
	size = function()
		return 42
	end,
	ready_timeout_ms = 60,
	adopted_ready_timeout_ms = 30,
})

local env_original = terminal_adapter.get_terminal(env_dir)
env_original.__alive = true
env_original:spawn()
local env_reused = terminal_adapter.get_terminal(env_dir)
assert(env_reused == env_original, "value-equal launch descriptors reuse the cached terminal")

local env_order = {}
local env_original_shutdown = env_original.shutdown
env_original.shutdown = function(self)
	table.insert(env_order, "shutdown-old")
	return env_original_shutdown(self)
end
current_env = { OPENCODE_TEST_REVISION = "2", OPENCODE_SERVER_PASSWORD = "password-2" }
local env_replacement = terminal_adapter.get_terminal(env_dir)
table.insert(env_order, "create-new")

assert(env_replacement ~= env_original, "an environment-only revision creates a new terminal generation")
eq(env_order, { "shutdown-old", "create-new" }, "the stale-auth generation is retired before replacement")
eq(
	env_replacement.env,
	vim.tbl_extend("force", current_env, { OPENCODE_NVIM_GENERATION = env_replacement._nvim_mini_generation }),
	"the replacement terminal receives the revised environment and generation"
)

setup_adapter()
local registry_dir = "/tmp/opencode-terminal-spec/project-registry"
local stale_hidden = Terminal:new({
	cmd = "TESTCMD --dir " .. registry_dir,
	dir = registry_dir,
	display_name = "OpenCode",
	hidden = true,
	env = { OPENCODE_TEST_REVISION = "stale" },
	clear_env = false,
})
stale_hidden.__alive = true
stale_hidden:spawn()

local stale_visible = Terminal:new({
	cmd = "TESTCMD --dir " .. registry_dir,
	dir = registry_dir,
	display_name = "OpenCode",
	hidden = true,
	env = { OPENCODE_TEST_REVISION = "visible-stale" },
	clear_env = false,
})
stale_visible.__alive = true
stale_visible:open(42)

local registry_replacement = terminal_adapter.get_terminal(registry_dir)
assert(registry_replacement ~= stale_hidden, "a hidden stale-env registry terminal is not adopted")
assert(registry[stale_hidden.id] == nil, "a hidden stale-env registry terminal is retired")
assert(registry[stale_visible.id] == stale_visible, "a live visible mismatched terminal is left untouched")

print("PASS environment revisions replace stale generations and reconcile same-project registry terminals")

-- ===== Section 10: dead reconstruction reuses one resolved launch snapshot =====

local launch_resolutions = 0
local reconstruction_dir = "/tmp/opencode-terminal-spec/project-reconstruction"
setup_adapter({
	launch = function(dir)
		launch_resolutions = launch_resolutions + 1
		return {
			cmd = "TESTCMD --dir " .. dir,
			env = { OPENCODE_TEST_REVISION = "stable" },
			clear_env = false,
		}
	end,
	project_root = function(explicit_dir)
		return explicit_dir or reconstruction_dir
	end,
})

local reconstruction_original = terminal_adapter.get_terminal(reconstruction_dir)
reconstruction_original:spawn()
reconstruction_original.__alive = false
local reconstruction = terminal_adapter.open(reconstruction_dir)

assert(reconstruction ~= reconstruction_original, "a dead terminal is reconstructed")
eq(launch_resolutions, 2, "dead reconstruction does not resolve a second launch snapshot within open()")
eq(
	reconstruction.env,
	{ OPENCODE_TEST_REVISION = "stable", OPENCODE_NVIM_GENERATION = reconstruction._nvim_mini_generation },
	"dead reconstruction reuses the resolved environment"
)

print("PASS dead-terminal reconstruction reuses the current operation's launch snapshot")

-- ===== Section 11: exact PTY payload bytes for append / append+submit / submit-only =====

setup_adapter()
local payload_dir = "/tmp/opencode-terminal-spec/project-i"
sent_payloads = {}
terminal_adapter.send("hello", { dir = payload_dir })
local payload_term = terminal_adapter.get_terminal(payload_dir)
payload_term.__alive = true
payload_term:on_stdout(payload_term.job_id, { "\27[?2004h" })
eq(sent_payloads[1].payload, "\27[200~hello\27[201~", "append without submit sends bracketed paste only")

terminal_adapter.send("hello", { dir = payload_dir, submit = true })
eq(sent_payloads[2].payload, "\27[200~hello\27[201~\r", "append and submit sends bracketed paste plus a trailing carriage return")

terminal_adapter.send("", { dir = payload_dir, submit = true })
eq(sent_payloads[3].payload, "\r", "submit-only with no text sends just a carriage return")

print("PASS exact PTY payload bytes match bracketed-paste and submit conventions")

-- ===== Section 12: hidden start opens once, while visible toggle retires =====

local visibility_generation = 0
local visibility_exits = {}
local visibility_starts = 0
setup_adapter({
	generation = function()
		visibility_generation = visibility_generation + 1
		return "visibility-generation-" .. visibility_generation
	end,
	on_exit = function(_, _, generation)
		table.insert(visibility_exits, generation)
	end,
	on_start = function()
		visibility_starts = visibility_starts + 1
	end,
})
local visibility_dir = "/tmp/opencode-terminal-spec/project-visibility"
local editor_win = vim.api.nvim_get_current_win()
local hidden_term = terminal_adapter.start(visibility_dir)

eq(hidden_term.__spawn_count, 1, "start() spawns a cold terminal exactly once")
assert(not hidden_term:is_open(), "start() keeps the terminal UI hidden")
eq(vim.api.nvim_get_current_win(), editor_win, "start() leaves editor focus unchanged")
assert(registry[hidden_term.id] == hidden_term, "start() registers the hidden terminal")

hidden_term.__alive = true
eq(terminal_adapter.start(visibility_dir), hidden_term, "repeated start() reuses the live hidden terminal")
eq(hidden_term.__spawn_count, 1, "repeated start() does not spawn another process")

eq(terminal_adapter.toggle(visibility_dir), hidden_term, "the first toggle displays the live hidden terminal")
assert(hidden_term:is_open(), "the first toggle makes a background-started terminal visible")
eq(hidden_term.__last_open_size, 42, "the first toggle resolves the configured split size")

local starts_before_close = visibility_starts
eq(terminal_adapter.toggle(visibility_dir), hidden_term, "closing toggle returns the terminal it retired")
eq(visibility_starts, starts_before_close, "closing a visible toggle does not redundantly re-register terminal ownership")
assert(not vim.api.nvim_buf_is_valid(hidden_term.bufnr), "closing a visible OpenCode toggle wipes its buffer")
eq(registry[hidden_term.id], nil, "closing a visible OpenCode toggle deregisters its terminal")
eq(terminal_adapter.generation_for(visibility_dir), nil, "closing toggle releases the retired generation")
eq(visibility_exits, { "visibility-generation-1" }, "closing toggle finalizes the retired generation once")

local replacement_term = terminal_adapter.toggle(visibility_dir)
assert(replacement_term ~= hidden_term, "the next toggle creates a fresh terminal generation")
assert(replacement_term:is_open(), "the fresh terminal is opened by the next toggle")
eq(replacement_term.__spawn_count, 1, "the fresh terminal process starts exactly once")
eq(replacement_term._nvim_mini_generation, "visibility-generation-2", "reopen uses a fresh generation")

print("PASS hidden toggle opens once and visible toggle destructively retires before fresh recreation")

-- ===== Section 12b: open() is idempotent - focuses instead of reopening =====
--
-- ToggleTerm's real Terminal:open() unconditionally calls
-- ui.set_origin_window(), even when the terminal is already open. Calling
-- open() a second time on an already-visible OCV terminal would therefore
-- silently reset ToggleTerm's remembered origin window to whatever window
-- happens to be current at that moment, breaking the coordinated worktree
-- startup layout's split placement. open() must focus rather than reopen.

setup_adapter()
local idempotent_dir = "/tmp/opencode-terminal-spec/project-idempotent"
local idempotent_term = terminal_adapter.start(idempotent_dir)
idempotent_term.__alive = true

local first_open = terminal_adapter.open(idempotent_dir)
eq(first_open.__open_count, 1, "open() on a hidden terminal opens it once")
eq(first_open.__focus_count or 0, 0, "open() on a hidden terminal does not also focus it")

local second_open = terminal_adapter.open(idempotent_dir)
assert(second_open == first_open, "open() twice returns the same terminal")
eq(second_open.__open_count, 1, "open() twice does not call term:open() a second time once already open")
eq(second_open.__focus_count, 1, "open() on an already-open terminal focuses it instead of reopening")

print("PASS open() is idempotent and focuses an already-open terminal instead of reopening it")

-- ===== Section 12c: exact generation resolves only its live terminal job =====

setup_adapter()
local pid_dir = "/tmp/opencode-terminal-spec/project-pid"
local pid_term = terminal_adapter.start(pid_dir)
pid_term.__alive = true
pid_term.__job_pid = 4242

eq(
	terminal_adapter.job_pid_for(pid_dir, "test-generation"),
	4242,
	"the owning live generation resolves to its exact ToggleTerm job pid"
)
eq(terminal_adapter.job_pid_for(pid_dir, "stale-generation"), nil, "a stale terminal generation cannot borrow the job pid")
pid_term.__alive = false
eq(terminal_adapter.job_pid_for(pid_dir, "test-generation"), nil, "a dead terminal never proves generation liveness")

print("PASS exact terminal generation exposes only its own live job pid")

-- ===== Section 12d: close APIs retire exact generations, including hidden terminals =====

local close_generation = 0
local close_exits = {}
setup_adapter({
	generation = function()
		close_generation = close_generation + 1
		return "close-generation-" .. close_generation
	end,
	on_exit = function(_, _, generation)
		table.insert(close_exits, generation)
	end,
})
local close_dir = "/tmp/opencode-terminal-spec/project-close"
local close_term = terminal_adapter.open(close_dir)
close_term.__alive = true
terminal_adapter.close(close_dir)
assert(not vim.api.nvim_buf_is_valid(close_term.bufnr), "close() wipes the OpenCode terminal buffer")
eq(close_term.__shutdown_count, 1, "close() shuts the terminal down exactly once")
eq(close_exits, { "close-generation-1" }, "close() finalizes its generation exactly once")
terminal_adapter.close(close_dir)
eq(close_term.__shutdown_count, 1, "repeated close() does not retire an already-released terminal twice")

local hidden_close_term = terminal_adapter.start(close_dir)
hidden_close_term.__alive = true
eq(
	terminal_adapter.close_generation(close_dir, "close-generation-1"),
	false,
	"close_generation() rejects a stale generation"
)
assert(vim.api.nvim_buf_is_valid(hidden_close_term.bufnr), "a stale generation cannot delete the live terminal")
eq(
	terminal_adapter.close_generation(close_dir, "close-generation-2"),
	true,
	"close_generation() retires the matching hidden terminal"
)
assert(not vim.api.nvim_buf_is_valid(hidden_close_term.bufnr), "matching generation close wipes a hidden terminal buffer")
eq(close_exits, { "close-generation-1", "close-generation-2" }, "each retired generation finalizes exactly once")

print("PASS close APIs destructively retire only their exact live generation")

-- ===== Section 12e: adopted terminals receive destructive buffer lifecycle =====

local adopted_creates = {}
local adopted_exits = {}
local foreign_exits = 0
setup_adapter({
	on_create = function(_, _, generation)
		table.insert(adopted_creates, generation)
	end,
	on_exit = function(_, _, generation)
		table.insert(adopted_exits, generation)
	end,
})
local adopted_close_dir = "/tmp/opencode-terminal-spec/project-adopted-close"
local adopted_close_term = Terminal:new({
	cmd = "TESTCMD --dir " .. adopted_close_dir,
	dir = adopted_close_dir,
	display_name = "OpenCode",
	hidden = true,
	env = { OPENCODE_TEST_REVISION = "1", OPENCODE_NVIM_GENERATION = "test-generation" },
	clear_env = false,
	on_exit = function()
		foreign_exits = foreign_exits + 1
	end,
})
adopted_close_term.__alive = true
adopted_close_term:open(42)
eq(terminal_adapter.get_terminal(adopted_close_dir), adopted_close_term, "the live terminal is adopted")
eq(vim.bo[adopted_close_term.bufnr].bufhidden, "wipe", "adopted OpenCode buffers wipe when their split closes")
eq(adopted_close_term.close_on_exit, true, "adopted terminals wipe on natural process exit")
eq(adopted_creates, { "test-generation" }, "adoption runs current on_create lifecycle once")

local editor_window = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
local terminal_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(terminal_window, adopted_close_term.bufnr)
vim.cmd("quit")
assert(vim.api.nvim_win_is_valid(editor_window), "closing the terminal split preserves the editor window")
assert(not vim.api.nvim_buf_is_valid(adopted_close_term.bufnr), "direct :quit wipes an adopted terminal buffer")
eq(terminal_adapter.generation_for(adopted_close_dir), nil, "direct :quit releases adopted terminal ownership")
adopted_close_term:on_exit(adopted_close_term.job_id, 0)
adopted_close_term:on_exit(adopted_close_term.job_id, 0)
eq(adopted_exits, { "test-generation" }, "direct close finalizes adapter lifecycle exactly once on process exit")
eq(foreign_exits, 1, "an adopted terminal's foreign on_exit callback is preserved exactly once")

print("PASS adopted terminals gain destructive direct-close lifecycle without duplicate finalization")

-- ===== Section 13: one stable generation owns start and exit callbacks =====

local started = {}
local exited = {}
setup_adapter({
	on_start = function(_, project, generation)
		table.insert(started, { project = project, generation = generation })
	end,
	on_exit = function(_, project, generation, code)
		table.insert(exited, { project = project, generation = generation, code = code })
	end,
})
local generation_dir = "/tmp/opencode-terminal-spec/project-generation"
local generation_term = terminal_adapter.start(generation_dir)
eq(generation_term.env.OPENCODE_NVIM_GENERATION, "test-generation", "the child TUI receives its stable capability generation")
eq(started, { { project = generation_dir, generation = "test-generation" } }, "ownership is registered before the TUI starts")
generation_term.__alive = true
terminal_adapter.start(generation_dir)
eq(#started, 2, "reusing a live process reasserts the same ownership binding")
eq(started[2].generation, "test-generation", "repeated start keeps the generation stable")
generation_term:on_exit(generation_term.job_id, 0)
eq(exited, { { project = generation_dir, generation = "test-generation", code = 0 } }, "exit invalidates only the matching generation")

print("PASS terminal generation remains stable and is registered before spawn")

for _, term in pairs(registry) do
	pcall(function()
		term:shutdown()
	end)
end

print("PASS config.opencode_terminal adapter lifecycle, reconciliation, and readiness")

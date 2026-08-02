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
		registry[self.id] = self
		if self.on_create then
			self:on_create()
		end
	end

	function term:open(size)
		self.__last_open_size = size
		if not registry[self.id] then
			self:spawn()
		end
		self.__window_open = true
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
		if self:is_open() then
			self:close()
		end
		if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
			pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
		end
		registry[self.id] = nil
		self.__alive = false
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

local terminal_adapter = require("config.opencode_terminal")

-- Deterministic liveness/write hooks: __alive is a plain flag the test sets
-- directly instead of needing a real terminal job, and sent_payloads
-- captures exact bytes without needing a real PTY channel.
local sent_payloads = {}
terminal_adapter.__set_test_hooks({
	terminal_live = function(term)
		return term.__alive == true
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
		cmd = function(dir)
			return "TESTCMD --dir " .. dir
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

local legacy_open = Terminal:new({ cmd = cmd, display_name = "OpenCode", hidden = true })
legacy_open.__alive = true
legacy_open:open(50)

local legacy_hidden = Terminal:new({ cmd = cmd, display_name = "OpenCode", hidden = true })
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
local legacy = Terminal:new({ cmd = adopt_cmd, display_name = "OpenCode", hidden = true })
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

-- ===== Section 7: process exit fails pending and resets readiness =====

setup_adapter()
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

exit_term:on_exit(exit_term.job_id, 1)
assert(exit_result, "the queued request is failed when the terminal process exits")
assert(exit_result:match("^failure:"), "process exit fails the request rather than silently dropping it")
eq(exit_term._nvim_mini_ready, false, "readiness is reset to false on exit")

print("PASS process exit fails pending requests and resets readiness")

-- ===== Section 8: a command/project change retires the old generation first =====

setup_adapter()
local order = {}
local change_dir = "/tmp/opencode-terminal-spec/project-h"
local current_cmd = "TESTCMD --dir " .. change_dir .. " --rev 1"
terminal_adapter.setup({
	display_name = "OpenCode",
	cmd = function(dir)
		return current_cmd
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

-- ===== Section 9: exact PTY payload bytes for append / append+submit / submit-only =====

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

-- ===== Section 10: M.focus opens/reuses the terminal and moves current-window focus =====

setup_adapter()
local focus_dir = "/tmp/opencode-terminal-spec/project-focus"
local scratch_win = vim.api.nvim_get_current_win()

local focus_term = terminal_adapter.get_terminal(focus_dir)
focus_term.__alive = true

-- The shared fake's term:open() only flips a flag; it never displays a real
-- window. Wrap it locally (this instance only) so focus() has a genuine
-- window to find, without changing the fake other sections depend on.
local original_focus_open = focus_term.open
function focus_term:open(size)
	original_focus_open(self, size)
	if not vim.fn.win_findbuf(self.bufnr)[1] then
		vim.cmd("botright vsplit")
		vim.api.nvim_win_set_buf(0, self.bufnr)
	end
end

assert(not focus_term:is_open(), "the focus-test terminal starts closed")
terminal_adapter.focus(focus_dir)
local focus_win = vim.fn.win_findbuf(focus_term.bufnr)[1]
assert(focus_win, "focus() opens a real window for a terminal that wasn't visible yet")
eq(vim.api.nvim_get_current_win(), focus_win, "focus() moves current-window focus onto the terminal's window")

-- Calling focus() again on an already-open terminal must not create a
-- duplicate/rearranged window or replace the terminal instance.
vim.api.nvim_set_current_win(scratch_win)
terminal_adapter.focus(focus_dir)
eq(
	terminal_adapter.get_terminal(focus_dir),
	focus_term,
	"a second focus() call on an already-open terminal reuses the same instance"
)
eq(
	vim.api.nvim_get_current_win(),
	vim.fn.win_findbuf(focus_term.bufnr)[1],
	"a second focus() call still lands on the terminal's existing window"
)

print("PASS focus() opens an unopened terminal once and reuses an already-open one without rearranging splits")

for _, term in pairs(registry) do
	pcall(function()
		term:shutdown()
	end)
end

print("PASS config.opencode_terminal adapter lifecycle, reconciliation, and readiness")

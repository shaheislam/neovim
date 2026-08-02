package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local state_home = vim.fn.tempname()
assert(vim.fn.mkdir(state_home, "p") == 1, "failed to create temporary state home")
vim.env.XDG_STATE_HOME = state_home
local attach_dir = state_home .. "/opencode/attaches"

local registry = dofile("lua/config/opencode_attach_registry.lua")

local function read_fields(path)
	local lines = vim.fn.readfile(path)
	local fields = {}
	for _, line in ipairs(lines) do
		local key, value = line:match("^([^=]+)=(.*)$")
		if key then
			fields[key] = value
		end
	end
	return fields
end

local function no_tmp_files_remain()
	local entries = vim.fn.glob(attach_dir .. "/*.tmp.*", true, true)
	return #entries == 0
end

local ORIGINAL_TMUX_PANE = vim.env.TMUX_PANE

-- ===== Section 1: registration is a no-op outside tmux =====

registry.__reset()
vim.env.TMUX_PANE = nil
local ok = registry.register({ job_id = 1, cmd = "ocv attach http://127.0.0.1:4096 --dir /tmp/x" }, "/tmp/x")
eq(ok, false, "register() outside tmux (no TMUX_PANE) is a no-op")
eq(vim.fn.isdirectory(attach_dir), 0, "no attach directory is created outside tmux")

-- ===== Section 2: registration writes the expected attach file schema =====

registry.__reset()
vim.env.TMUX_PANE = "%42"
registry.__set_test_hooks({
	resolve_pid = function(job_id)
		eq(job_id, 999, "resolve_pid receives the terminal's job_id")
		return 54321
	end,
})

local dir = "/tmp/opencode-attach-registry-spec/project-a"
local cmd = "ocv attach http://127.0.0.1:4096 --dir " .. vim.fn.shellescape(dir)
local term = { job_id = 999, cmd = cmd }
local registered = registry.register(term, dir)
eq(registered, true, "register() succeeds inside tmux with a resolvable pid")

local attach_file = attach_dir .. "/pane-42.pid"
eq(vim.fn.filereadable(attach_file), 1, "the attach file is written under the sanitized pane key")
assert(no_tmp_files_remain(), "no leftover .tmp file remains after an atomic write")

local fields = read_fields(attach_file)
eq(fields.pid, "54321", "the recorded pid matches the resolved job pid, not the job_id")
eq(fields.pane, "%42", "the recorded pane matches TMUX_PANE verbatim")
eq(fields.cwd, dir, "the recorded cwd matches the terminal's project directory")
assert(tonumber(fields.started) ~= nil, "the recorded started timestamp is numeric")
eq(fields.command, cmd, "the recorded command matches the terminal's actual launch cmd")
assert(fields.command:match("ocv%s+attach"), "the recorded command satisfies the fish resolver's attach-command pattern")

print("PASS register() writes a well-formed, atomically-written attach file")

-- ===== Section 3: unregister() removes the attach file =====

registry.unregister()
eq(vim.fn.filereadable(attach_file), 0, "unregister() removes the attach file it created")

print("PASS unregister() removes the previously registered attach file")

-- ===== Section 4: a missing job_id or unresolvable pid is a safe no-op =====

registry.__reset()
vim.env.TMUX_PANE = "%7"
registry.__set_test_hooks({
	resolve_pid = function()
		return nil
	end,
})
local no_pid_ok = registry.register({ job_id = 1, cmd = "ocv attach" }, "/tmp/no-pid")
eq(no_pid_ok, false, "register() is a no-op when the job pid cannot be resolved")
eq(vim.fn.filereadable(attach_dir .. "/pane-7.pid"), 0, "no attach file is written when the pid is unresolvable")

registry.__reset()
vim.env.TMUX_PANE = "%8"
local no_job_ok = registry.register({ cmd = "ocv attach" }, "/tmp/no-job")
eq(no_job_ok, false, "register() is a no-op when the terminal has no job_id yet")

print("PASS register() safely no-ops without a resolvable job pid")

-- ===== Section 5: re-registering for the same pane replaces its own file =====

registry.__reset()
vim.env.TMUX_PANE = "%42"
registry.__set_test_hooks({
	resolve_pid = function()
		return 111
	end,
})
registry.register({ job_id = 2, cmd = "ocv attach --dir /tmp/first" }, "/tmp/first")
registry.register({ job_id = 3, cmd = "ocv attach --dir /tmp/second" }, "/tmp/second")
local replaced_fields = read_fields(attach_file)
eq(replaced_fields.cwd, "/tmp/second", "re-registering for the same pane updates the same attach file in place")
registry.unregister()

vim.env.TMUX_PANE = ORIGINAL_TMUX_PANE
registry.__reset()

print("PASS opencode attach registry lifecycle")

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), message or (vim.inspect(actual) .. " ~= " .. vim.inspect(expected)))
end

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

local root = vim.fn.tempname()
assert(vim.fn.mkdir(root .. "/state/opencode/attaches", "p") == 1, "failed to create temporary state")
root = canonical(root)
local state_home = root .. "/state"
local attach_dir = state_home .. "/opencode/attaches"

local function valid_record(pane, pid, cwd, command)
	return {
		"pid=" .. (pid or "300"),
		"pane=" .. (pane or "%2"),
		"cwd=" .. (cwd or root),
		"started=1",
		"command=" .. (command or "/dotfiles/scripts/bin/oc attach http://127.0.0.1:4096"),
	}
end

local function write_record(name, lines)
	assert(vim.fn.writefile(lines, attach_dir .. "/" .. name) == 0, "failed to write attach record")
end

local function clear_records()
	for name, kind in vim.fs.dir(attach_dir) do
		if kind == "file" then
			assert(vim.fn.delete(attach_dir .. "/" .. name) == 0, "failed to clear attach record")
		end
	end
end

write_record(
	"pane-2.pid",
	{
		"pid=300",
		"pane=%2",
		"cwd=" .. root,
		"started=1",
		"command=/dotfiles/scripts/bin/oc attach http://127.0.0.1:4096",
	}
)

local original_executable = vim.fn.executable
local original_system = vim.system
local original_notify = vim.notify
local original_tmux_pane = vim.env.TMUX_PANE
local original_state_home = vim.env.XDG_STATE_HOME
local calls = {}
local notifications = {}
local scenario

local function reset_scenario(overrides)
	scenario = {
		display = "%1\t@1\n",
		panes = "%1\t100\t" .. root .. "\n%2\t200\t" .. root .. "\n",
		titles = { ["%2"] = "OC | Visible root\n" },
		commands = { ["300"] = "/dotfiles/scripts/bin/oc attach http://127.0.0.1:4096\n" },
		parents = { ["300"] = "200\n" },
		load_code = 0,
		paste_code = 0,
		tmux_available = true,
		source_pane = "%1",
	}
	for key, value in pairs(overrides or {}) do
		scenario[key] = value
	end
	calls = {}
	notifications = {}
end

local function calls_for(command)
	local matches = {}
	for _, call in ipairs(calls) do
		if call.args[1] == "tmux" and call.args[2] == command then
			table.insert(matches, call)
		end
	end
	return matches
end

reset_scenario()

vim.env.TMUX_PANE = "%1"
vim.env.XDG_STATE_HOME = state_home
vim.fn.executable = function(command)
	if command == "tmux" then
		return scenario.tmux_available and 1 or 0
	end
	return original_executable(command)
end
vim.notify = function(message, level, opts)
	table.insert(notifications, { message = message, level = level, opts = opts })
end
vim.system = function(args, opts)
	table.insert(calls, { args = vim.deepcopy(args), stdin = opts and opts.stdin })
	local result = { code = 0, stdout = "", stderr = "" }
	if args[1] == "tmux" and args[2] == "display-message" then
		if args[6] == "#{pane_title}" then
			result.stdout = scenario.titles[args[5]] or ""
			result.code = result.stdout == "" and 1 or 0
		else
			result.stdout = scenario.display
		end
	elseif args[1] == "tmux" and args[2] == "list-panes" then
		result.stdout = scenario.panes
	elseif args[1] == "tmux" and args[2] == "load-buffer" then
		result.code = scenario.load_code
	elseif args[1] == "tmux" and args[2] == "paste-buffer" then
		result.code = scenario.paste_code
	elseif args[1] == "ps" and args[3] == "command=" then
		result.stdout = scenario.commands[args[5]] or ""
		result.code = result.stdout == "" and 1 or 0
	elseif args[1] == "ps" and args[3] == "ppid=" then
		result.stdout = scenario.parents[args[5]] or ""
		result.code = result.stdout == "" and 1 or 0
	end
	return {
		wait = function()
			return result
		end,
	}
end

local tmux = require("config.opencode_tmux")
eq(tmux.resolve_attach(), {
	pane = "%2",
	cwd = root,
	title = "OC | Visible root",
}, "same-window resolver exposes the validated OpenCode attachment")
tmux.append_prompt("first\nsecond", { dir = root, fallback_clipboard = true })

local load_call
local paste_call
for _, call in ipairs(calls) do
	if call.args[1] == "tmux" and call.args[2] == "load-buffer" then
		load_call = call
	elseif call.args[1] == "tmux" and call.args[2] == "paste-buffer" then
		paste_call = call
	end
end
assert(load_call, "same-window OpenCode pane loads a tmux paste buffer")
eq(load_call.stdin, "first\nsecond", "multiline prompt is passed on stdin")
assert(load_call.args[4]:match("^opencode%-nvim%-"), "paste uses a uniquely named tmux buffer")
eq(
	paste_call.args,
	{ "tmux", "paste-buffer", "-p", "-d", "-b", load_call.args[4], "-t", "%2" },
	"prompt is pasted only into the validated same-window pane"
)

local first_buffer = load_call.args[4]
calls = {}
tmux.append_prompt("another selection", { dir = root })
local second_load = calls_for("load-buffer")[1]
assert(second_load and second_load.args[4] ~= first_buffer, "consecutive sends use distinct tmux buffers")

clear_records()
write_record("pane-2.pid", valid_record("%2", "300", root .. "/state/.."))
reset_scenario({ panes = "%1\t100\t" .. root .. "\n%2\t200\t" .. root .. "/state/..\n" })
eq(tmux.append_prompt("canonical paths", { dir = root }), true, "equivalent canonical project paths are accepted")
eq(#calls_for("paste-buffer"), 1, "canonical project match reaches the target pane")

local adjacent_root = root .. "/adjacent"
assert(vim.fn.mkdir(adjacent_root, "p") == 1, "failed to create adjacent project")
clear_records()
write_record("pane-2.pid", valid_record("%2", "300", adjacent_root))
reset_scenario({ panes = "%1\t100\t" .. root .. "\n%2\t200\t" .. adjacent_root .. "\n" })
eq(tmux.resolve_attach(), {
	pane = "%2",
	cwd = adjacent_root,
	title = "OC | Visible root",
}, "resolver follows the validated adjacent OpenCode cwd")
eq(
	tmux.append_prompt("cross-project append", { dir = root, fallback_clipboard = true }),
	false,
	"append-only delivery remains constrained to the Neovim project"
)
eq(#calls_for("paste-buffer"), 0, "cross-project append never pastes into the adjacent pane")

local function expect_rejected(label, records, overrides)
	clear_records()
	for _, record in ipairs(records or {}) do
		write_record(record.name, record.lines)
	end
	reset_scenario(overrides)
	vim.env.TMUX_PANE = scenario.source_pane
	vim.fn.setreg("+", "")
	eq(
		tmux.append_prompt(label, { dir = root, fallback_clipboard = true }),
		false,
		label .. " must fail closed"
	)
	eq(#calls_for("load-buffer"), 0, label .. " must not load a tmux buffer")
	eq(#calls_for("paste-buffer"), 0, label .. " must not paste into any pane")
	eq(vim.fn.getreg("+"), label, label .. " falls back to the clipboard")
	assert(
		not notifications[#notifications].message:find("broadcast", 1, true),
		label .. " never offers a broadcast fallback"
	)
end

expect_rejected("missing record", {})
expect_rejected("tmux unavailable", {
	{ name = "pane-2.pid", lines = valid_record() },
}, { tmux_available = false })
expect_rejected("invalid source pane", {
	{ name = "pane-2.pid", lines = valid_record() },
}, { source_pane = "not-a-pane" })
expect_rejected("cross-window record", {
	{ name = "pane-9.pid", lines = valid_record("%9", "900") },
})
expect_rejected("incomplete record", {
	{ name = "pane-2.pid", lines = { "pid=300", "pane=%2", "cwd=" .. root } },
})
expect_rejected("stale process", {
	{ name = "pane-2.pid", lines = valid_record() },
}, { commands = {} })
expect_rejected("invalid recorded command", {
	{ name = "pane-2.pid", lines = valid_record("%2", "300", root, "/usr/bin/nvim") },
})
expect_rejected("lookalike recorded command", {
	{ name = "pane-2.pid", lines = valid_record("%2", "300", root, "/dotfiles/scripts/bin/ocaml attach") },
})
expect_rejected("invalid live command", {
	{ name = "pane-2.pid", lines = valid_record() },
}, { commands = { ["300"] = "/usr/bin/nvim\n" } })
expect_rejected("wrong process ancestry", {
	{ name = "pane-2.pid", lines = valid_record() },
}, { parents = { ["300"] = "999\n", ["999"] = "1\n" } })
expect_rejected("wrong recorded project", {
	{ name = "pane-2.pid", lines = valid_record("%2", "300", root .. "/other") },
})
expect_rejected("wrong live project", {
	{ name = "pane-2.pid", lines = valid_record() },
}, { panes = "%1\t100\t" .. root .. "\n%2\t200\t" .. root .. "/other\n" })
expect_rejected(
	"ambiguous same-window records",
	{
		{ name = "pane-2.pid", lines = valid_record() },
		{ name = "pane-3.pid", lines = valid_record("%3", "301") },
	},
	{
		panes = "%1\t100\t" .. root .. "\n%2\t200\t" .. root .. "\n%3\t201\t" .. root .. "\n",
		commands = {
			["300"] = "/dotfiles/scripts/bin/oc attach http://127.0.0.1:4096\n",
			["301"] = "/usr/local/bin/opencode attach http://127.0.0.1:4096\n",
		},
		parents = { ["300"] = "200\n", ["301"] = "201\n" },
	}
)

clear_records()
write_record("pane-2.pid", valid_record())
reset_scenario({ load_code = 1 })
vim.env.TMUX_PANE = scenario.source_pane
vim.fn.setreg("+", "")
eq(tmux.append_prompt("load failure", { dir = root, fallback_clipboard = true }), false, "load failure is reported")
eq(#calls_for("paste-buffer"), 0, "load failure never attempts a paste")
eq(#calls_for("delete-buffer"), 1, "load failure cleans up its named buffer")
eq(vim.fn.getreg("+"), "load failure", "load failure copies the prompt")

clear_records()
write_record("pane-2.pid", valid_record())
reset_scenario({ paste_code = 1 })
vim.env.TMUX_PANE = scenario.source_pane
vim.fn.setreg("+", "")
eq(tmux.append_prompt("paste failure", { dir = root, fallback_clipboard = true }), false, "paste failure is reported")
eq(#calls_for("paste-buffer"), 1, "paste failure attempted only the validated pane")
eq(#calls_for("delete-buffer"), 1, "paste failure cleans up its named buffer")
eq(vim.fn.getreg("+"), "paste failure", "paste failure copies the prompt")

local original_tmux_module = package.loaded["config.opencode_tmux"]
local original_http_module = package.loaded["config.opencode_http"]
local tmux_prompt_calls = {}
local http_prompt_calls = {}
package.loaded["config.opencode_tmux"] = {
	append_prompt = function(text, opts)
		table.insert(tmux_prompt_calls, { text = text, opts = opts })
	end,
}
package.loaded["config.opencode_http"] = {
	append_prompt = function(text, opts)
		table.insert(http_prompt_calls, { text = text, opts = opts })
	end,
}

local plugin_specs = dofile("lua/plugins/opencode.lua")
local send_selection
for _, key in ipairs(plugin_specs[1].keys) do
	if key[1] == "<leader>aoS" and key.mode == "x" then
		send_selection = key[2]
		break
	end
end
assert(send_selection, "visual <leader>aoS mapping is present")

local original_buffer = vim.api.nvim_get_current_buf()
local selection_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(selection_buffer)
vim.api.nvim_buf_set_name(selection_buffer, "diffview://deadbeef:lua/example.lua")
vim.api.nvim_buf_set_lines(selection_buffer, 0, -1, false, { "first", "second" })
vim.fn.setpos("'<", { selection_buffer, 1, 1, 0 })
vim.fn.setpos("'>", { selection_buffer, 2, 6, 0 })
send_selection()

eq(#http_prompt_calls, 1, "<leader>aoS delegates to the broadcast HTTP transport")
eq(#tmux_prompt_calls, 0, "<leader>aoS never uses the pane-targeted tmux transport")
eq(
	http_prompt_calls[1].text,
	"[file: lua/example.lua, lines 1-2]\nfirst\nsecond",
	"Diffview selection keeps its file and line context"
)
eq(
	http_prompt_calls[1].opts,
	{ title = "opencode", success = "Sent selection to OpenCode", fallback_clipboard = true },
	"selection keeps its existing delivery options"
)

vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(selection_buffer, { force = true })
package.loaded["config.opencode_tmux"] = original_tmux_module
package.loaded["config.opencode_http"] = original_http_module

vim.fn.executable = original_executable
vim.system = original_system
vim.notify = original_notify
vim.env.TMUX_PANE = original_tmux_pane
vim.env.XDG_STATE_HOME = original_state_home
assert(vim.fn.delete(root, "rf") == 0, "failed to remove temporary state")

print("PASS same-window OpenCode tmux prompt append")
print("PASS OpenCode attach record trust boundary")
print("PASS OpenCode tmux failure fallback")
print("PASS <leader>aoS broadcast transport wiring")

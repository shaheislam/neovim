package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
vim.opt.rtp:append(vim.fn.expand("~/.local/share/nvim/lazy/toggleterm.nvim"))
require("toggleterm").setup({ start_in_insert = false })

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/project with 'quotes'", "p")
local dir = vim.uv.fs_realpath(tmp .. "/project with 'quotes'")
local session = dir .. "/Session.vim"
local log = tmp .. "/launches"
vim.fn.writefile({ "#!/bin/sh", 'printf "%s\\n" "$*" >>"' .. log .. '"', "sleep 60" }, tmp .. "/ocv")
vim.fn.setfperm(tmp .. "/ocv", "rwx------")
vim.env.PATH = tmp .. ":" .. vim.env.PATH
vim.o.shell = "/bin/sh"
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "terminal" }

local adapter = require("config.opencode_terminal")
local starts = {}
adapter.setup({
	project_root = function(explicit)
		return explicit or dir
	end,
	launch = function(root, _, context)
		local cmd = "ocv attach http://127.0.0.1:4096 --dir " .. vim.fn.shellescape(root)
		if context and context.session_id then
			cmd = cmd .. " --session " .. context.session_id
		end
		return {
			cmd = cmd,
			env = {
				OPENCODE_RESTORE_LATEST = context and context.restore_latest and "1" or "0",
			},
		}
	end,
	on_start = function(_, root, generation)
		table.insert(starts, { root = root, generation = generation })
	end,
})
local bindings = {}
package.loaded["config.opencode_handoff"] = {
	active_bindings = function()
		return bindings
	end,
}
local persistence = require("config.opencode_session")
persistence.setup()
vim.cmd.source(vim.fn.fnameescape(vim.fn.expand("~/.local/share/nvim/lazy/vim-obsession/plugin/obsession.vim")))

vim.cmd.cd(vim.fn.fnameescape(dir))
vim.api.nvim_buf_set_name(0, dir .. "/editor.txt")
adapter.open(dir)
assert(
	vim.wait(1000, function()
		return vim.fn.filereadable(log) == 1
	end),
	"the initial TUI starts"
)
local saved_generation = adapter.generation_for(dir)
bindings[dir] = { sessionID = "ses_first", generation = saved_generation }
vim.cmd("mksession! " .. vim.fn.fnameescape(session))
vim.g.this_obsession = session
vim.api.nvim_exec_autocmds("BufEnter", {})
assert(
	table.concat(vim.fn.readfile(session), "\n"):find("ses_first", 1, true),
	"Obsession saves preserve identity when nested SessionWritePost is skipped"
)
bindings[dir].sessionID = "ses_switched"
vim.api.nvim_exec_autocmds("User", { pattern = "OpencodeHandoffEvent:binding_changed" })
local body = table.concat(vim.fn.readfile(session), "\n")
assert(body:find("ses_switched", 1, true), "switching the TUI session updates the saved snapshot")
assert(not body:find("ses_first", 1, true), "stale session identity is replaced")
assert(not body:find("OPENCODE_SERVER_PASSWORD", 1, true), "the snapshot contains no runtime credentials")
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(
	table.concat(vim.fn.readfile(session), "\n"):find("ses_switched", 1, true),
	"the final Obsession exit save preserves the switched session"
)
vim.g.this_obsession = nil

adapter.close(dir)
bindings = {}
local before = #starts
vim.cmd("source " .. vim.fn.fnameescape(session))
assert(#starts == before + 1, "restore creates one managed terminal: " .. #starts .. "/" .. before .. "\n" .. body)
local restored = adapter.get_terminal(dir)
assert(restored.cmd:match("%-%-session ses_switched$"), "restore selects the switched session, not latest")
assert(restored.env.OPENCODE_NVIM_GENERATION ~= saved_generation, "restore creates a fresh bridge generation")
assert(restored:is_open(), "the managed terminal occupies the saved window")
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, "restore preserves the two-column layout")
assert(#require("toggleterm.terminal").get_all(true) == 1, "raw replay creates no duplicate TUI")
vim.cmd("source " .. vim.fn.fnameescape(session))
assert(adapter.get_terminal(dir) == restored, "reloading the snapshot reuses the live owner")
assert(#require("toggleterm.terminal").get_all(true) == 1, "repeat restore remains duplicate-free")
assert(
	vim.wait(1000, function()
		return #vim.fn.readfile(log) == 2
	end),
	"only original and managed restore jobs start"
)

bindings[dir] = { sessionID = "ses_stale", generation = saved_generation }
vim.api.nvim_exec_autocmds("User", { pattern = "OpencodeHandoffEvent:binding_changed" })
body = table.concat(vim.fn.readfile(session), "\n")
assert(not body:find("ses_stale", 1, true), "an obsolete bridge generation cannot overwrite saved identity")
bindings = {}

-- Legacy snapshots have no saved identity; resume only this worktree's history.
vim.g.this_obsession = nil
adapter.close(dir)
local legacy = {}
for _, line in ipairs(vim.fn.readfile(session)) do
	if not line:find("opencode_session_snapshot", 1, true) then
		table.insert(legacy, line)
	end
end
vim.fn.writefile(legacy, session)
vim.cmd("source " .. vim.fn.fnameescape(session))
assert(adapter.get_terminal(dir).env.OPENCODE_RESTORE_LATEST == "1", "legacy restore opts into exact-worktree lookup")
assert(
	vim.wait(1000, function()
		return #vim.fn.readfile(log) == 3
	end),
	"legacy restore starts exactly one managed job"
)

vim.g.this_obsession = nil
adapter.close(dir)
vim.cmd("cd /tmp")
vim.fn.delete(tmp, "rf")
print("PASS OpenCode session save, switch, managed restore, layout and legacy fallback")

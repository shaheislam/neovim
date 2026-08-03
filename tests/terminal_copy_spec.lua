package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local terminal_copy = require("config.terminal_copy")

vim.cmd("enew!")
local normal_buf = vim.api.nvim_get_current_buf()
eq(terminal_copy.start_visual(), 0, "normal buffers fall back to tmux copy mode")
eq(vim.api.nvim_get_current_buf(), normal_buf, "rejected copy requests do not change buffers")
eq(vim.fn.mode(), "n", "rejected copy requests do not change mode")

vim.cmd("enew!")
local terminal_buf = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "/bin/sh", "-c", "cat" }, { term = true })
assert(job > 0, "failed to start terminal fixture")

eq(terminal_copy.start_visual(), 1, "terminal buffers handle pane-local copy requests")
eq(vim.fn.mode(), "v", "terminal copy enters Visual mode before returning")

local before_motion = vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false)
local motion = vim.api.nvim_replace_termcodes("l", true, false, true)
vim.api.nvim_feedkeys(motion, "nx", false)
vim.wait(50)
local after_motion = vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false)

eq(after_motion, before_motion, "the first Visual motion is not sent to the terminal child")
eq(vim.api.nvim_get_current_buf(), terminal_buf, "terminal copy remains in the originating buffer")
eq(vim.bo[terminal_buf].filetype, "", "terminal routing does not depend on ToggleTerm filetype")

pcall(vim.fn.jobstop, job)
vim.cmd("bdelete!")

local socket = vim.fn.tempname() .. ".sock"
local root = vim.fn.getcwd()
local server = vim.system({
	vim.v.progpath,
	"--headless",
	"--clean",
	"--listen",
	socket,
	"--cmd",
	string.format("lua vim.opt.runtimepath:prepend(%q)", root),
})

local rpc_ok, rpc_error = xpcall(function()
	assert(vim.wait(2000, function()
		local stat = vim.uv.fs_stat(socket)
		return stat and stat.type == "socket"
	end, 10), "listening Neovim fixture did not create its RPC socket")

	local expression = [[luaeval("(function() vim.cmd('enew'); local job=vim.fn.jobstart({'/bin/sh','-c','cat'},{term=true}); if job<=0 then return 'job-failed' end; local handled=require('config.terminal_copy').start_visual(); return tostring(handled)..':'..vim.fn.mode() end)()")]]
	local response = vim.system({ vim.v.progpath, "--server", socket, "--remote-expr", expression }, { text = true }):wait(2000)
	eq(response.code, 0, "terminal copy RPC completes successfully")
	eq(vim.trim(response.stdout or ""), "1:v", "terminal copy enters Visual mode before RPC returns")
end, debug.traceback)

server:kill(15)
server:wait(1000)
vim.fn.delete(socket)
assert(rpc_ok, rpc_error)

print("PASS tmux copy routing enters pane-local terminal Visual mode synchronously")

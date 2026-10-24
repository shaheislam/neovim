package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
vim.o.shell = "/bin/sh"
vim.env.SHELL = "/bin/sh"
vim.g.mapleader = " "
local picker = require("config.terminal_picker")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/shell 'cwd", "p")
local cwd = vim.uv.fs_realpath(root .. "/shell 'cwd")
local editor = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_name(0, root .. "/editor.lua")
vim.cmd("belowright split")
local terminal = vim.api.nvim_get_current_win()
vim.cmd.enew()
local channel = vim.fn.jobstart({ "/bin/sh", "-c", "cat" }, { term = true })
local pid = vim.fn.jobpid(channel)
local terminal_buf = vim.api.nvim_get_current_buf()
local original_cwd = vim.fn.getcwd(editor)
local launched, options, visible
package.loaded["fzf-lua.win"] = {
	__SELF = function()
		return visible and { fzf_winid = editor }
	end,
}
package.loaded["fzf-lua.actions"] = {
	normalize_selected = function(selected)
		return selected[1], { selected[2] }
	end,
	act = function() end,
}
vim.keymap.set("n", "<leader>gl", function()
	launched = vim.api.nvim_get_current_win()
	assert(vim.fn.getcwd() == cwd, "native callback must inherit the shell cwd")
	options = picker.options({})
	visible = true
	if options.winopts.on_create then
		options.winopts.on_create()
	end
	assert(options.winopts.relative == "editor", "picker must use editor coordinates")
end)
local function close()
	visible = false
	options.winopts.on_close()
end
local empty_called
vim.keymap.set("n", "<leader>gs", function()
	empty_called = true
	picker.options({})
end)
local function request(key, request_pid)
	return picker.request({ key = key or "gl", pid = request_pid or pid, cwd = cwd })
end
visible = true
assert(request() == "busy", "an existing native picker must not be replaced")
visible = false
assert(request("gs") == "queued")
assert(
	vim.wait(1000, function()
		return empty_called and vim.fn.getcwd(editor) == original_cwd
	end),
	"a provider without a picker must release its cwd and request"
)
assert(request() == "queued")
assert(request() == "busy", "only one request may be in flight")
assert(vim.wait(1000, function()
	return launched ~= nil
end))
assert(launched == editor, "files/actions must target the editor, not replace the terminal")
close()
assert(vim.wait(1000, function()
	return vim.api.nvim_get_current_win() == terminal
end))
assert(vim.fn.getcwd(editor) == original_cwd, "cancel must restore the editor cwd")
assert(vim.api.nvim_win_get_buf(terminal) == terminal_buf)
assert(vim.fn.jobwait({ channel }, 0)[1] == -1)

launched = nil
assert(request() == "queued")
assert(vim.wait(1000, function()
	return launched ~= nil
end))
close()
options.fn_selected({ "enter", "entry" }, {})
vim.wait(20)
assert(vim.api.nvim_get_current_win() == editor, "accepted actions keep native focus")
assert(vim.fn.getcwd(editor) == original_cwd)

local own_socket = vim.fn.serverstart(root .. "/own.sock")
local payload = vim.json.encode({ key = "gl", pid = pid, cwd = cwd }):gsub("'", "''")
local expression = "luaeval('require(\"config.terminal_picker\").request(_A)', json_decode('" .. payload .. "'))"
local response, exit_code = "", nil
launched = nil
local caller = vim.fn.jobstart({ "nvim", "--server", own_socket, "--remote-expr", expression }, {
	on_stdout = function(_, data)
		response = response .. table.concat(data, "\n")
	end,
	on_exit = function(_, code)
		exit_code = code
	end,
})
assert(vim.wait(3000, function()
	return launched ~= nil and response:find("queued", 1, true)
end))
assert(
	vim.wait(1000, function()
		return exit_code == 0
	end),
	"RPC must return before the picker closes"
)
close()
assert(vim.wait(1000, function()
	return vim.api.nvim_get_current_win() == terminal
end))
vim.fn.serverstop(own_socket)

-- A second editor may share directories, but cannot own this terminal's PID.
local other_socket = root .. "/other.sock"
local other = vim.fn.jobstart(
	{
		"nvim",
		"--headless",
		"-u",
		"NONE",
		"-i",
		"NONE",
		"--listen",
		other_socket,
		"--cmd",
		"lua package.path=" .. string.format("%q", package.path),
	},
	vim.empty_dict()
)
assert(vim.wait(3000, function()
	return vim.uv.fs_stat(other_socket) ~= nil
end))
local rpc = vim.fn.sockconnect("pipe", other_socket, { rpc = true })
assert(
	vim.rpcrequest(
		rpc,
		"nvim_exec_lua",
		"return require('config.terminal_picker').request(...)",
		{ { key = "gl", pid = pid, cwd = cwd } }
	) == "unowned"
)
vim.fn.chanclose(rpc)
vim.fn.jobstop(other)

for _, scope in ipairs({ "lcd", "tcd" }) do
	vim.api.nvim_set_current_win(editor)
	vim.cmd("noautocmd " .. scope .. " " .. vim.fn.fnameescape(original_cwd))
	local was_local = vim.fn.haslocaldir()
	vim.api.nvim_set_current_win(terminal)
	launched = nil
	assert(request() == "queued")
	assert(vim.wait(1000, function()
		return launched ~= nil
	end))
	close()
	assert(vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == terminal
	end))
	assert(vim.fn.getcwd(editor) == original_cwd)
	assert(vim.fn.haslocaldir(editor) == was_local, "restore the previous cwd scope")
end

assert(request("not-a-picker") == "unsupported")
assert(request("gl", vim.fn.getpid()) == "unowned", "another process cannot target this editor")
vim.api.nvim_set_current_win(terminal)
assert(request() == "queued")
vim.api.nvim_win_close(terminal, true)
launched = nil
vim.wait(20)
assert(not launched, "closing the source before dispatch must cancel the request")
vim.fn.jobstop(channel)
vim.fn.delete(root, "rf")
print("PASS terminal picker ownership, native actions, cwd, cancellation and stale source")

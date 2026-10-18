local plugin = vim.fn.stdpath("data") .. "/lazy/which-key.nvim"
assert(vim.fn.isdirectory(plugin) == 1, "Install the locked which-key.nvim before running this integration test")

local child = vim.fn.jobstart(
	{ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" },
	{ rpc = true }
)
assert(child > 0, "could not start the isolated Neovim")
local watchdog = vim.defer_fn(function()
	vim.fn.jobstop(child)
end, 15000)
local function lua(code, ...)
	return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
end
local function wait_for(code, message)
	local ready = vim.wait(1500, function()
		return lua(code) == true
	end, 10)
	assert(
		ready,
		message
			.. ": "
			.. lua(
				"local s=require('which-key.state').state; return vim.json.encode({mode=vim.api.nvim_get_mode(), keys=s and s.node.keys, count=vim.g.leader_commands, errors=vim.v.errmsg})"
			)
	)
end

local ok, err = xpcall(function()
	vim.rpcrequest(child, "nvim_ui_attach", 120, 40, { rgb = true })
	lua(
		[[
		local root, plugin = ...
		vim.opt.rtp:prepend(root)
		vim.opt.rtp:prepend(plugin)
		vim.g.mapleader = ' '
		vim.o.timeoutlen = 300
		dofile(root .. '/lua/config/keymaps.lua')
		vim.g.leader_commands = 0
		vim.keymap.set('n', '<leader>ff', function()
			vim.g.leader_commands = vim.g.leader_commands + 1
		end, { desc = 'Find files test action' })
		local spec = dofile(root .. '/lua/plugins/which-key.lua')[1]
		spec.config(nil, vim.deepcopy(spec.opts))
	]],
		vim.fn.getcwd(),
		plugin
	)
	wait_for("return vim.fn.maparg('<Space>', 'n', false, true).desc == 'which-key-trigger'", "leader trigger loads")

	local function leader(label, before, input)
		wait_for(
			"return not require('which-key.state').state and not require('which-key.view').valid() and vim.fn.maparg('<Space>', 'n', false, true).desc == 'which-key-trigger'",
			label .. " starts with an idle leader trigger"
		)
		lua((before or "") .. "\nvim.api.nvim_input(...)", input or " ")
		wait_for(
			"local s=require('which-key.state').state; return s and s.node.keys == '<Space>' and require('which-key.view').valid()",
			label .. " shows the popup after a single Space"
		)
		local count = lua("return vim.g.leader_commands")
		vim.rpcrequest(child, "nvim_input", "ff")
		wait_for("return vim.g.leader_commands == " .. (count + 1), label .. " executes the leader action")
		wait_for("return not require('which-key.view').valid()", label .. " closes the popup")
	end

	leader("Normal mode")
	lua(
		"vim.api.nvim_buf_set_lines(0, 0, -1, false, {'x y z'}); vim.api.nvim_win_set_cursor(0, {1, 0}); vim.api.nvim_input('f ')"
	)
	wait_for("return vim.api.nvim_win_get_cursor(0)[2] == 1", "Space remains a character argument to f")
	lua("vim.api.nvim_win_set_cursor(0, {1, 0}); vim.api.nvim_input('r ')")
	wait_for("return vim.api.nvim_get_current_line() == '  y z'", "Space remains a replacement character")
	leader("Late mapping registration", "require('which-key').add({ { '<leader>z', group = 'Late group' } })")
	leader("Buffer invalidation", "vim.api.nvim_exec_autocmds('LspAttach', { buffer = 0, data = { client_id = 1 } })")
	leader("Buffer read", "vim.api.nvim_exec_autocmds('BufReadPost', { buffer = 0 })")
	lua("vim.cmd.startinsert()")
	wait_for("return vim.fn.mode() == 'i'", "buffer enters Insert mode")
	leader("Immediate Insert exit", nil, "<Esc> ")
	vim.rpcrequest(child, "nvim_input", ":")
	wait_for("return vim.fn.mode() == 'c'", "buffer enters command-line mode")
	leader("Immediate command-line exit", nil, "<Esc> ")

	lua("vim.cmd.enew(); vim.fn.jobstart({'cat'}, {term=true}); vim.cmd.startinsert()")
	wait_for("return vim.fn.mode() == 't'", "terminal enters input mode")
	vim.rpcrequest(child, "nvim_input", "x y")
	wait_for(
		"return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'):find('x y', 1, true) ~= nil",
		"terminal receives literal Space"
	)
	vim.rpcrequest(child, "nvim_input", "<C-\\><C-n>")
	wait_for("return vim.fn.mode() == 'n'", "terminal enters Normal mode")
	leader("Terminal Normal mode")
	lua("vim.cmd.startinsert()")
	wait_for("return vim.fn.mode() == 't'", "terminal re-enters input mode")
	leader("Immediate terminal exit", nil, "<Esc><Esc> ")
	lua("vim.cmd.startinsert()")
	wait_for("return vim.fn.mode() == 't'", "terminal enters input mode before Ctrl-Space")
	leader("Terminal Ctrl-Space", nil, "<C-Space>")
	lua("vim.api.nvim_win_set_cursor(0, {1, 0}); vim.cmd.startinsert()")
	wait_for("return vim.fn.mode() == 't'", "terminal enters input mode before a native motion")
	vim.rpcrequest(child, "nvim_input", "<C-\\><C-n>0f ")
	wait_for(
		"return vim.api.nvim_win_get_cursor(0)[2] == 1 and not require('which-key.state').state",
		"terminal exit does not steal a later motion argument"
	)

	lua(
		"vim.cmd.enew(); vim.api.nvim_buf_set_lines(0, 0, -1, false, {'abcd ef'}); vim.api.nvim_win_set_cursor(0, {1, 0}); vim.api.nvim_input('  ')"
	)
	wait_for(
		"return vim.api.nvim_win_get_cursor(0)[2] == 2 and not require('which-key.state').state",
		"repeated Space falls through without recursion"
	)
	lua("vim.api.nvim_win_set_cursor(0, {1, 0}); vim.api.nvim_input(' ~')")
	wait_for(
		"return vim.api.nvim_get_current_line() == 'aBcd ef' and not require('which-key.state').state",
		"unmapped leader sequences retain native behavior"
	)

	lua("vim.api.nvim_input('qa')")
	wait_for("return vim.fn.reg_recording() == 'a'", "macro recording starts")
	local count = lua("return vim.g.leader_commands")
	vim.rpcrequest(child, "nvim_input", " ffq")
	wait_for(
		"return vim.fn.reg_recording() == '' and vim.g.leader_commands == " .. (count + 1),
		"leader actions record without opening the popup"
	)
	vim.rpcrequest(child, "nvim_input", "@a")
	wait_for(
		"return vim.fn.reg_executing() == '' and vim.g.leader_commands == " .. (count + 2),
		"leader actions replay without opening the popup"
	)
	assert(lua("return vim.v.errmsg == ''"), "leader input must not emit errors")

	print("PASS real which-key leader input survives invalidation and mode changes; native keys and macros still work")
end, debug.traceback)
watchdog:stop()
vim.fn.jobstop(child)
vim.fn.jobwait({ child }, 1000)
if not ok then
	io.stderr:write(err .. "\n")
	io.stderr:flush()
	os.exit(1)
end

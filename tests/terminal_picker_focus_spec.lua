-- Real UI input must reach fzf, never the shell underneath its floating window.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "chosen" }, root .. "/focusprobe.txt")
for _, args in ipairs({
	{ "init" },
	{ "add", "." },
	{
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.test",
		"-c",
		"commit.gpgsign=false",
		"-c",
		"core.hooksPath=/dev/null",
		"commit",
		"-m",
		"focusprobe",
	},
}) do
	local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
	assert(result.code == 0, result.stderr)
end
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--clean" }, { rpc = true })
local function rpc(method, ...)
	return vim.rpcrequest(child, method, ...)
end
local function lua(code, ...)
	return rpc("nvim_exec_lua", code, { ... })
end
local function wait_for(code, message)
	assert(
		vim.wait(5000, function()
			return lua(code)
		end, 10),
		message
			.. ": "
			.. lua(
				"return vim.inspect({mode=vim.fn.mode(), ft=vim.bo.filetype, bt=vim.bo.buftype, buf=vim.api.nvim_buf_get_name(0)})"
			)
	)
end
local ok, err = xpcall(function()
	rpc("nvim_ui_attach", 140, 45, { rgb = true })
	lua(
		[[
		local config, root = ...
		vim.opt.rtp:prepend(config)
		for _, plugin in ipairs({ "fzf-lua", "nvim-web-devicons" }) do
			vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
		end
		vim.o.shell, vim.env.SHELL = "/bin/sh", "/bin/sh"
		for _, key in ipairs({ "TMUX", "TMUX_PANE", "NVIM", "REX_SESSION", "REX_BLOCK" }) do
			vim.env[key] = nil
		end
		vim.cmd.cd(root)
		vim.g.mapleader = " "
		local spec = dofile(config .. "/lua/plugins/fzf-lua.lua")[1]
		spec.config(nil, spec.opts())
		for _, mapping in ipairs(spec.keys) do
			vim.keymap.set(mapping.mode or "n", mapping[1], mapping[2])
		end
		vim.cmd("belowright new")
		_G.shell_win = vim.api.nvim_get_current_win()
		_G.shell_job = vim.fn.jobstart({ "cat" }, { term = true })
		_G.shell_buf = vim.api.nvim_get_current_buf()
		vim.cmd.startinsert()
	]],
		vim.fn.getcwd(),
		root
	)
	wait_for("return vim.fn.mode() == 't'", "source terminal is typing")
	for _, key in ipairs({ "gl", "gl", "ff", "gl" }) do
		assert(lua(
			[[return require("config.terminal_picker").request({
			key=..., pid=vim.fn.jobpid(_G.shell_job), cwd=vim.fn.getcwd()})]],
			key
		) == "queued")
		wait_for("return vim.bo.filetype == 'fzf'", "picker opens")
		wait_for("return vim.fn.mode() == 't'", "picker accepts keyboard input")
		rpc("nvim_input", "<C-u>typedquery")
		wait_for(
			[[return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false), '\n'):find('typedquery',1,true) ~= nil]],
			"typed query reaches fzf"
		)
		rpc("nvim_input", "<Esc>")
		wait_for(
			"return vim.api.nvim_get_current_win() == _G.shell_win and vim.fn.mode() == 't'",
			"escape restores shell input"
		)
		assert(
			lua(
				[[return not table.concat(vim.api.nvim_buf_get_lines(_G.shell_buf,0,-1,false), '\n'):find('typedquery',1,true)]]
			),
			"picker query leaked into shell"
		)
	end
	-- Selecting a file keeps the editor focused, rather than resuming the shell.
	assert(lua([[return require("config.terminal_picker").request({
		key='ff', pid=vim.fn.jobpid(_G.shell_job), cwd=vim.fn.getcwd()})]]) == "queued")
	wait_for("return vim.bo.filetype == 'fzf' and vim.fn.mode() == 't'", "selection picker accepts input")
	rpc("nvim_input", "<C-u>")
	wait_for(
		[[return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false), '\n'):find('1/1',1,true) ~= nil]],
		"file candidate loads"
	)
	rpc("nvim_input", "<CR>")
	wait_for(
		[[return vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0):match('/focusprobe.txt$') ~= nil]],
		"selection opens file in editor"
	)
	wait_for("return vim.fn.mode() == 'n'", "selection must leave file in Normal mode")
end, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(root, "rf")
assert(ok, err)
print("PASS repeated Git/file picker keyboard focus, Escape and source input isolation")

-- Real fzf-lua windows and actions, with live shell/chat jobs alongside Oil.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
for _, plugin in ipairs({ "fzf-lua", "nvim-web-devicons", "canola.nvim" }) do
	vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.shell, vim.env.SHELL = "/bin/sh", "/bin/sh"
for _, key in ipairs({ "TMUX", "TMUX_PANE", "NVIM", "REX_SESSION", "REX_BLOCK" }) do
	vim.env[key] = nil
end
vim.o.hidden, vim.o.swapfile = true, false
vim.g.mapleader = " "
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
vim.fn.writefile({ "chosen" }, root .. "/picked.txt")
local function git(...)
	local args = {
		"git",
		"-C",
		root,
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.test",
		"-c",
		"commit.gpgsign=false",
		"-c",
		"core.hooksPath=/dev/null",
	}
	vim.list_extend(args, { ... })
	local result = vim.system(args, { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
git("init")
git("add", "picked.txt")
git("commit", "-m", "older revision")
local older = git("rev-parse", "HEAD")
vim.fn.writefile({ "newer" }, root .. "/picked.txt")
git("commit", "-am", "newer revision")
local spec = dofile("lua/plugins/fzf-lua.lua")[1]
spec.config(nil, spec.opts())
for _, mapping in ipairs(spec.keys) do
	vim.keymap.set(mapping.mode or "n", mapping[1], mapping[2], { desc = mapping.desc })
end
local fzf, picker = require("fzf-lua"), require("config.terminal_picker")
local api = vim.api
local editor = api.nvim_get_current_win()
vim.cmd.edit(root .. "/picked.txt")
vim.cmd("botright vnew")
local chat = api.nvim_get_current_win()
local chat_job = vim.fn.jobstart({ "cat" }, { term = true })
api.nvim_set_current_win(editor)
vim.cmd("belowright new")
local shell = api.nvim_get_current_win()
local shell_job = vim.fn.jobstart({ "cat" }, { term = true })
api.nvim_set_current_win(editor)
vim.o.columns, vim.o.lines = 140, 45
local function geometry(win)
	return { api.nvim_win_get_position(win), api.nvim_win_get_width(win), api.nvim_win_get_height(win) }
end
local shell_geometry, chat_geometry = geometry(shell), geometry(chat)
local function window()
	local instance = require("fzf-lua.win").__SELF()
	return instance and instance.fzf_winid and api.nvim_win_is_valid(instance.fzf_winid) and instance
end
local function opened()
	assert(vim.wait(5000, window, 20), "native fzf did not open")
	local instance = window()
	assert(api.nvim_win_get_width(instance.fzf_winid) > api.nvim_win_get_width(editor), "picker is pane-bound")
	return instance, geometry(instance.fzf_winid)
end
local function cancel()
	api.nvim_chan_send(vim.b[api.nvim_win_get_buf(window().fzf_winid)].terminal_job_id, "\27")
	assert(vim.wait(5000, function()
		return not window()
	end, 20))
	vim.wait(30)
end
fzf.files({ cwd = root })
local _, normal_geometry = opened()
cancel()
require("oil").setup({ default_file_explorer = false })
require("oil").open(root)
assert(vim.wait(1000, function()
	return vim.bo.filetype == "oil"
end))
fzf.files({ cwd = root })
local _, oil_geometry = opened()
assert(vim.deep_equal(normal_geometry, oil_geometry), "Oil geometry differs from normal editor")
cancel()
api.nvim_set_current_win(shell)
assert(picker.request({ key = "ff", pid = vim.fn.jobpid(shell_job), cwd = root }) == "queued")
local _, terminal_geometry = opened()
assert(vim.deep_equal(normal_geometry, terminal_geometry), "terminal geometry differs from native picker")
cancel()
assert(api.nvim_get_current_win() == shell, "cancel must return to the calling shell")
assert(vim.deep_equal(geometry(shell), shell_geometry) and vim.deep_equal(geometry(chat), chat_geometry))
assert(vim.fn.jobwait({ shell_job, chat_job }, 0)[1] == -1)

assert(picker.request({ key = "ff", pid = vim.fn.jobpid(shell_job), cwd = root }) == "queued")
local scoped = opened()
local scoped_win = scoped.fzf_winid
api.nvim_chan_send(vim.b[api.nvim_win_get_buf(scoped_win)].terminal_job_id, "\27l")
assert(
	vim.wait(5000, function()
		return window() and window().fzf_winid ~= scoped_win
	end, 20),
	"scope switch did not reopen the picker"
)
cancel()
assert(api.nvim_get_current_win() == shell, "cancelling a scope switch must return to the shell")

assert(picker.request({ key = "ff", pid = vim.fn.jobpid(shell_job), cwd = root }) == "queued")
local instance = opened()
local job = vim.b[api.nvim_win_get_buf(instance.fzf_winid)].terminal_job_id
assert(
	vim.wait(5000, function()
		return table
			.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(instance.fzf_winid), 0, -1, false), "\n")
			:find("picked.txt", 1, true)
	end, 20),
	"file candidates did not load"
)
api.nvim_chan_send(job, "\r")
assert(
	vim.wait(5000, function()
		return not window() and api.nvim_buf_get_name(api.nvim_win_get_buf(editor)) == root .. "/picked.txt"
	end, 20),
	"native selection did not open the requested file"
)
assert(api.nvim_win_get_buf(shell) ~= api.nvim_win_get_buf(editor))
assert(vim.deep_equal(geometry(shell), shell_geometry) and vim.deep_equal(geometry(chat), chat_geometry))
assert(vim.fn.jobwait({ shell_job, chat_job }, 0)[2] == -1)

-- Only the confirmation is automated; checkout is the installed native action.
local confirm = require("fzf-lua.utils").confirm
require("fzf-lua.utils").confirm = function()
	return 1
end
api.nvim_set_current_win(shell)
assert(picker.request({ key = "gl", pid = vim.fn.jobpid(shell_job), cwd = root }) == "queued")
instance = opened()
job = vim.b[api.nvim_win_get_buf(instance.fzf_winid)].terminal_job_id
assert(
	vim.wait(5000, function()
		return table
			.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(instance.fzf_winid), 0, -1, false), "\n")
			:find("older revision", 1, true)
	end, 20),
	"Git log did not use the shell repository"
)
api.nvim_chan_send(job, "older")
assert(vim.wait(5000, function()
	return table
		.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(instance.fzf_winid), 0, 1, false), "")
		:find("older", 1, true)
end, 20))
vim.wait(100)
api.nvim_chan_send(job, "\r")
assert(
	vim.wait(5000, function()
		return not window() and git("rev-parse", "HEAD") == older
	end, 20),
	"native Git checkout action was lost"
)
require("fzf-lua.utils").confirm = confirm
vim.fn.jobstop(shell_job)
vim.fn.jobstop(chat_job)
vim.fn.delete(root, "rf")
print("PASS native fzf geometry from editor/Oil/terminal, file/Git actions and companion preservation")

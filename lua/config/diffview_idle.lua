local M = {}

local return_target = require("config.return_target")
local pane_option = "@nvim_server"
local cwd_option = "@nvim_cwd"
local review_project_option = "@opencode_diffview_project"
local review_base_option = "@opencode_diffview_base"

local function tmux_set(option, value)
	local pane = vim.env.TMUX_PANE
	if not pane or pane == "" or vim.fn.executable("tmux") ~= 1 then
		return
	end

	vim.fn.jobstart({ "tmux", "set-option", "-p", "-t", pane, option, value }, { detach = true })
end

local function register_server()
	if not vim.env.TMUX_PANE or vim.env.TMUX_PANE == "" then
		return
	end

	if vim.v.servername == "" then
		pcall(vim.fn.serverstart)
	end
	if vim.v.servername == "" then
		return
	end

	tmux_set(pane_option, vim.v.servername)
	tmux_set(cwd_option, vim.fn.getcwd())
end

local function unregister_server()
	local pane = vim.env.TMUX_PANE
	if not pane or pane == "" or vim.fn.executable("tmux") ~= 1 then
		return
	end

	vim.fn.jobstart({ "tmux", "set-option", "-p", "-u", "-t", pane, pane_option }, { detach = true })
	vim.fn.jobstart({ "tmux", "set-option", "-p", "-u", "-t", pane, cwd_option }, { detach = true })
end

local function tmux_get(option)
	local pane = vim.env.TMUX_PANE
	if not pane or pane == "" or vim.fn.executable("tmux") ~= 1 then
		return ""
	end
	return vim.trim(vim.fn.system({ "tmux", "show-option", "-p", "-v", "-t", pane, option }))
end

local function tmux_unset(option)
	local pane = vim.env.TMUX_PANE
	if pane and pane ~= "" and vim.fn.executable("tmux") == 1 then
		vim.fn.system({ "tmux", "set-option", "-p", "-u", "-t", pane, option })
	end
end

local function can_interrupt_editor()
	local mode = vim.api.nvim_get_mode().mode
	return mode == "n" or mode == "no"
end

local function canonical(path)
	if not path or path == "" then
		return nil
	end
	return vim.fn.resolve(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

function M.open(project_dir, base)
	if vim.g.opencode_auto_diffview == false or not can_interrupt_editor() then
		return false
	end

	project_dir = canonical(project_dir)
	if not project_dir or vim.fn.isdirectory(project_dir) ~= 1 then
		return false
	end

	local ok, lib = pcall(require, "diffview.lib")
	local view = ok and lib.get_current_view() or nil
	if view then
		local view_root = canonical(view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel)
		if view_root ~= project_dir then
			return false
		end
		pcall(require("config.hotreload").watch_directory, project_dir)
		if view.update_files then
			view:update_files()
		end
		return true
	end

	pcall(require("config.hotreload").watch_directory, project_dir)
	return_target.capture({ force = true })
	local command = "DiffviewOpen -C" .. vim.fn.fnameescape(project_dir)
	if base and base:match("^[0-9a-fA-F]+$") then
		local result = vim.system({ "git", "-C", project_dir, "cat-file", "-e", base .. "^{commit}" }, { text = true }):wait()
		if result.code == 0 then
			command = command .. " " .. base
		end
	end
	vim.cmd(command)
	return true
end

function M.open_from_tmux()
	local project_dir = tmux_get(review_project_option)
	local base = tmux_get(review_base_option)
	tmux_unset(review_project_option)
	tmux_unset(review_base_option)
	return M.open(project_dir, base)
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	register_server()
	local group = vim.api.nvim_create_augroup("opencode_diffview_idle", { clear = true })
	vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
		group = group,
		callback = register_server,
		desc = "Register Neovim RPC endpoint for OpenCode Diffview review",
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = unregister_server,
		desc = "Unregister Neovim RPC endpoint for OpenCode Diffview review",
	})
end

return M

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local captured
package.loaded["lualine"] = {
	setup = function(opts)
		captured = opts
	end,
}
package.loaded["lualine.utils.utils"] = {
	stl_escape = function(value)
		return value:gsub("%%", "%%%%")
	end,
}

local terminals = {}
package.loaded["toggleterm.terminal"] = {
	get = function(id, include_hidden)
		assert(include_hidden == true, "statusline lookup includes hidden ToggleTerm terminals")
		return terminals[id]
	end,
}

local opencode_buffers = {}
package.loaded["config.opencode_terminal"] = {
	is_buffer = function(bufnr)
		return opencode_buffers[bufnr] == true
	end,
}

local original_buf = vim.api.nvim_get_current_buf()
local original_tab = vim.api.nvim_get_current_tabpage()
local initial_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(initial_buf)

local specs = dofile("lua/plugins/lualine.lua")
specs[1].config()

assert(captured, "lualine setup options are captured")
local active_component = captured.sections.lualine_c[3][1]
assert(type(active_component) == "function", "the active filename slot is a custom component")
local inactive_component = captured.inactive_sections.lualine_c[1][1]
assert(type(inactive_component) == "function", "inactive windows use the same safe custom component")

local terminal_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(terminal_buf)
local terminal_job = vim.fn.termopen({ "sh", "-c", "sleep 10" })
assert(terminal_job > 0, "the terminal fixture starts")
vim.api.nvim_buf_set_name(
	terminal_buf,
	"term://project//123:OPENCODE_SERVER_PASSWORD=statusline-secret ocv attach"
)
vim.b[terminal_buf].toggle_number = 7
opencode_buffers[terminal_buf] = true

terminals[7] = { display_name = "OpenCode" }
eq(active_component(), "OpenCode", "an OpenCode terminal without useful history renders its explicit display name")
assert(not active_component():find("statusline-secret", 1, true), "the raw terminal name never reaches lualine")

terminals[7] = { display_name = "" }
eq(active_component(), "Terminal", "an empty display name falls back to a safe generic label")
terminals[7] = nil
eq(active_component(), "Terminal", "a missing ToggleTerm lookup falls back to a safe generic label")
terminals[7] = { display_name = "OpenCode" }

local file_buf = vim.api.nvim_create_buf(true, false)
local file_path = vim.fn.getcwd() .. "/tests/lualine%fixture.lua"
vim.api.nvim_buf_set_name(file_buf, file_path)
vim.api.nvim_set_current_buf(file_buf)
eq(active_component(), "tests/lualine%%fixture.lua", "ordinary relative paths are preserved and statusline-escaped")
eq(inactive_component(), "tests/lualine%%fixture.lua", "inactive windows use the same escaped path rendering")
vim.api.nvim_set_current_buf(terminal_buf)
eq(active_component(), "tests/lualine%%fixture.lua", "OpenCode retains the last focused file label")

local original_oil = package.loaded["oil"]
local oil_buf = vim.api.nvim_create_buf(false, true)
vim.bo[oil_buf].filetype = "oil"
local oil_source_buf
package.loaded["oil"] = {
	get_current_dir = function(bufnr)
		oil_source_buf = bufnr
		return (vim.env.HOME or "") .. "/notes%archive/"
	end,
}
vim.api.nvim_set_current_buf(oil_buf)
eq(active_component(), "notes%%archive/", "Oil directory formatting is preserved and escaped")
vim.api.nvim_set_current_buf(terminal_buf)
eq(active_component(), "notes%%archive/", "OpenCode retains the last focused Oil directory")
eq(oil_source_buf, oil_buf, "Oil rendering receives the remembered source buffer explicitly")
package.loaded["oil"] = original_oil

local refreshed_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(refreshed_buf, vim.fn.getcwd() .. "/tests/lualine-old.lua")
vim.api.nvim_set_current_buf(refreshed_buf)
vim.api.nvim_buf_set_name(refreshed_buf, vim.fn.getcwd() .. "/tests/lualine-renamed.lua")
vim.bo[refreshed_buf].readonly = true
vim.api.nvim_set_current_buf(terminal_buf)
eq(
	active_component(),
	"tests/lualine-renamed.lua 󰌾",
	"leaving a buffer refreshes renamed and readonly label state"
)

local empty_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(file_buf)
vim.api.nvim_set_current_buf(empty_buf)
vim.api.nvim_set_current_buf(terminal_buf)
eq(active_component(), "OpenCode", "an empty last label falls back safely instead of leaking older history")

local ordinary_terminal_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(ordinary_terminal_buf)
local ordinary_terminal_job = vim.fn.termopen({ "sh", "-c", "sleep 10" })
assert(ordinary_terminal_job > 0, "the ordinary terminal fixture starts")
vim.b[ordinary_terminal_buf].toggle_number = 8
terminals[8] = { display_name = "Shell" }
vim.api.nvim_set_current_buf(terminal_buf)
eq(active_component(), "Shell", "ordinary ToggleTerm buffers remain eligible history sources")

local deleted_source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(deleted_source, vim.fn.getcwd() .. "/tests/deleted-source.lua")
vim.api.nvim_set_current_buf(deleted_source)
vim.api.nvim_set_current_buf(terminal_buf)
vim.api.nvim_buf_delete(deleted_source, { force = true })
eq(active_component(), "tests/deleted-source.lua", "remembered labels survive source buffer deletion")

local first_tab = vim.api.nvim_get_current_tabpage()
local first_tab_label = active_component()
vim.cmd.tabnew()
local second_tab = vim.api.nvim_get_current_tabpage()
local second_tab_file = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(second_tab_file, vim.fn.getcwd() .. "/tests/second-tab.lua")
vim.api.nvim_set_current_buf(second_tab_file)
vim.api.nvim_set_current_buf(terminal_buf)
eq(active_component(), "tests/second-tab.lua", "a second tab remembers its own last label")
vim.api.nvim_set_current_tabpage(first_tab)
eq(active_component(), first_tab_label, "returning to the first tab restores its independent label")
vim.api.nvim_set_current_tabpage(second_tab)
eq(active_component(), "tests/second-tab.lua", "the second tab label remains independent")
vim.api.nvim_set_current_tabpage(first_tab)
vim.api.nvim_set_current_tabpage(second_tab)
vim.cmd.tabclose()

vim.fn.jobstop(terminal_job)
vim.fn.jobstop(ordinary_terminal_job)
vim.api.nvim_set_current_tabpage(original_tab)
vim.api.nvim_set_current_buf(original_buf)
for _, bufnr in ipairs({
	initial_buf,
	terminal_buf,
	file_buf,
	oil_buf,
	refreshed_buf,
	empty_buf,
	ordinary_terminal_buf,
	second_tab_file,
}) do
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
end

print("PASS lualine retains safe non-OpenCode labels across focus changes")

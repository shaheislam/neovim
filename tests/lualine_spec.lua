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

local specs = dofile("lua/plugins/lualine.lua")
specs[1].config()

assert(captured, "lualine setup options are captured")
local active_component = captured.sections.lualine_c[3][1]
assert(type(active_component) == "function", "the active filename slot is a custom component")
local inactive_component = captured.inactive_sections.lualine_c[1][1]
assert(type(inactive_component) == "function", "inactive windows use the same safe custom component")

local original_buf = vim.api.nvim_get_current_buf()
local terminal_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(terminal_buf)
local terminal_job = vim.fn.termopen({ "sh", "-c", "sleep 10" })
assert(terminal_job > 0, "the terminal fixture starts")
vim.api.nvim_buf_set_name(
	terminal_buf,
	"term://project//123:OPENCODE_SERVER_PASSWORD=statusline-secret ocv attach"
)
vim.b[terminal_buf].toggle_number = 7

terminals[7] = { display_name = "OpenCode" }
eq(active_component(), "OpenCode", "an OpenCode terminal renders its explicit display name")
assert(not active_component():find("statusline-secret", 1, true), "the raw terminal name never reaches lualine")

terminals[7] = { display_name = "" }
eq(active_component(), "Terminal", "an empty display name falls back to a safe generic label")
terminals[7] = nil
eq(active_component(), "Terminal", "a missing ToggleTerm lookup falls back to a safe generic label")

local file_buf = vim.api.nvim_create_buf(true, false)
local file_path = vim.fn.getcwd() .. "/tests/lualine%fixture.lua"
vim.api.nvim_buf_set_name(file_buf, file_path)
vim.api.nvim_set_current_buf(file_buf)
eq(active_component(), "tests/lualine%%fixture.lua", "ordinary relative paths are preserved and statusline-escaped")
eq(inactive_component(), "tests/lualine%%fixture.lua", "inactive windows use the same escaped path rendering")

local original_oil = package.loaded["oil"]
local oil_buf = vim.api.nvim_create_buf(false, true)
vim.bo[oil_buf].filetype = "oil"
vim.api.nvim_set_current_buf(oil_buf)
package.loaded["oil"] = {
	get_current_dir = function()
		return (vim.env.HOME or "") .. "/notes%archive/"
	end,
}
eq(active_component(), "notes%%archive/", "Oil directory formatting is preserved and escaped")
package.loaded["oil"] = original_oil

vim.fn.jobstop(terminal_job)
vim.api.nvim_set_current_buf(original_buf)
for _, bufnr in ipairs({ terminal_buf, file_buf, oil_buf }) do
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
end

print("PASS lualine renders safe semantic terminal labels and escaped paths")

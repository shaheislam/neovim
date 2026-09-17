package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function plugin(path, index)
	local specs = dofile(path)
	return type(specs[1]) == "table" and specs[index or 1] or specs
end

local function mode_includes(mode, target)
	if mode == nil then
		return target == "n"
	end
	return mode == target or type(mode) == "table" and vim.tbl_contains(mode, target)
end

local function mapping(keys, lhs, mode)
	for _, key in ipairs(keys or {}) do
		if key[1] == lhs and mode_includes(key.mode, mode or "n") then
			return key
		end
	end
end

local function absent(keys, lhs, owner)
	for _, key in ipairs(keys or {}) do
		assert(key[1] ~= lhs, owner .. " no longer owns " .. lhs)
	end
end

local function capture_keymaps(callback)
	local captured = {}
	local original = vim.keymap.set
	vim.keymap.set = function(mode, lhs, rhs, opts)
		table.insert(captured, { mode = mode, lhs = lhs, rhs = rhs, opts = opts or {} })
	end
	local ok, err = xpcall(callback, debug.traceback)
	vim.keymap.set = original
	assert(ok, err)
	return captured
end

local obsidian = plugin("lua/plugins/obsidian.lua")
local pending = mapping(obsidian.keys, "<leader>oP")
local completed = mapping(obsidian.keys, "<leader>oC")
assert(pending and pending.desc == "Pending tasks", "Obsidian owns <leader>oP pending tasks")
assert(completed and completed.desc == "Completed tasks", "Obsidian owns <leader>oC completed tasks")
absent(obsidian.keys, "<leader>tt", "Obsidian")
absent(obsidian.keys, "<leader>tc", "Obsidian")

local original_fzf = package.loaded["fzf-lua"]
local grep_calls = {}
package.loaded["fzf-lua"] = { grep = function(opts) table.insert(grep_calls, opts) end }
pending[2]()
completed[2]()
package.loaded["fzf-lua"] = original_fzf
eq(grep_calls[1].search, "- \\[ \\]", "Obsidian pending tasks keeps its grep action")
eq(grep_calls[2].search, "- \\[x\\]", "Obsidian completed tasks keeps its grep action")

local neotest = plugin("lua/plugins/neotest.lua")
assert(mapping(neotest.keys, "<leader>tt") and mapping(neotest.keys, "<leader>tw"), "Neotest retains its t-prefixed mappings")

local mini = plugin("lua/plugins/mini.lua")
local trim_whitespace = mapping(mini.keys, "<leader>xw")
local trim_lines = mapping(mini.keys, "<leader>xl")
assert(trim_whitespace and trim_whitespace.desc == "Trim Trailing Whitespace", "Mini owns <leader>xw")
assert(trim_lines and trim_lines.desc == "Trim Last Empty Lines", "Mini owns <leader>xl")
absent(mini.keys, "<leader>tw", "Mini")
absent(mini.keys, "<leader>tl", "Mini")

local original_trailspace = package.loaded["mini.trailspace"]
local trim_calls = {}
package.loaded["mini.trailspace"] = {
	trim = function() table.insert(trim_calls, "whitespace") end,
	trim_last_lines = function() table.insert(trim_calls, "lines") end,
}
trim_whitespace[2]()
trim_lines[2]()
package.loaded["mini.trailspace"] = original_trailspace
eq(trim_calls, { "whitespace", "lines" }, "Mini trim callbacks retain their actions")

local typst = plugin("lua/plugins/typst.lua")
local typst_watch = mapping(typst.keys, "<leader>Tw")
local typst_compile = mapping(typst.keys, "<leader>Tc")
local typst_open = mapping(typst.keys, "<leader>To")
eq(typst_watch[2], "<cmd>TypstWatch<cr>", "Typst watch keeps its command")
assert(typst_compile and typst_compile.desc == "Typst: Compile", "Typst owns <leader>Tc")
assert(typst_open and typst_open.desc == "Typst: Open PDF", "Typst owns <leader>To")
for _, lhs in ipairs({ "<leader>tw", "<leader>tc", "<leader>to" }) do
	absent(typst.keys, lhs, "Typst")
end
local original_expand = vim.fn.expand
local original_fnamemodify = vim.fn.fnamemodify
local original_system = vim.fn.system
local original_cmd = vim.cmd
local typst_commands = {}
vim.fn.expand = function(expr)
	return expr == "%:r" and "/tmp/doc/main" or "/tmp/doc/main.typ"
end
vim.fn.fnamemodify = function(path, mods)
	eq({ path, mods }, { "/tmp/doc/main.typ", ":h:h" }, "Typst compile keeps root resolution")
	return "/tmp"
end
vim.fn.system = function(args) typst_commands.open = args end
vim.cmd = function(command) typst_commands.compile = command end
typst_compile[2]()
typst_open[2]()
vim.fn.expand = original_expand
vim.fn.fnamemodify = original_fnamemodify
vim.fn.system = original_system
vim.cmd = original_cmd
eq(typst_commands.compile, "!typst compile --root /tmp /tmp/doc/main.typ", "Typst compile callback is preserved")
eq(typst_commands.open, { "open", "/tmp/doc/main.pdf" }, "Typst PDF callback is preserved")

local kulala = plugin("lua/plugins/kulala.lua")
local kulala_commands = {
	s = "run",
	t = "toggle_view",
	n = "jump_next",
	p = "jump_prev",
	i = "inspect",
	e = "set_selected_env",
	c = "copy",
	r = "replay",
	a = "run_all",
	S = "scratchpad",
	q = "close",
	G = "download_graphql_schema",
}
for suffix, action in pairs(kulala_commands) do
	local lhs = "<leader>H" .. suffix
	local key = mapping(kulala.keys, lhs)
	assert(key and key.desc, "Kulala owns described " .. lhs)
	eq(key[2], "<cmd>lua require('kulala')." .. action .. "()<cr>", lhs .. " keeps its command")
end
for _, key in ipairs(kulala.keys) do
	assert(not key[1]:match("^<leader>R"), "Kulala no longer owns Rust's R prefix")
end

local viewport = plugin("lua/plugins/viewport.lua")
for suffix, desc in pairs({ v = "Viewport Resize Mode", n = "Viewport Navigate Mode", s = "Viewport Select Mode" }) do
	local key = mapping(viewport.keys, "<leader>v" .. suffix)
	assert(key and key.desc == desc, "Viewport owns <leader>v" .. suffix)
	absent(viewport.keys, "<leader>w" .. suffix, "Viewport")
end
local original_viewport = package.loaded["viewport"]
local original_viewport_actions = package.loaded["viewport.actions"]
local viewport_actions = {
	start_resize_mode = function() end,
	start_navigate_mode = function() end,
	start_select_mode = function() end,
}
viewport_actions.setup = function() end
package.loaded["viewport"] = viewport_actions
package.loaded["viewport.actions"] = { toggle_maximize = function() end }
local viewport_maps = capture_keymaps(viewport.config)
package.loaded["viewport"] = original_viewport
package.loaded["viewport.actions"] = original_viewport_actions
for lhs, rhs in pairs({
	["<leader>vv"] = viewport_actions.start_resize_mode,
	["<leader>vn"] = viewport_actions.start_navigate_mode,
	["<leader>vs"] = viewport_actions.start_select_mode,
}) do
	local found
	for _, key in ipairs(viewport_maps) do
		if key.lhs == lhs then found = key end
	end
	assert(found and found.mode == "n" and found.rhs == rhs, lhs .. " dispatches to viewport")
end

local global_maps = capture_keymaps(function() dofile("lua/config/keymaps.lua") end)
local quit
for _, key in ipairs(global_maps) do
	if key.lhs == "<leader>Q" then quit = key end
	assert(key.lhs ~= "<leader>q", "global keymaps no longer use quickfix prefix for quit")
end
assert(quit and quit.mode == "n" and quit.rhs == ":q<CR>" and quit.opts.desc == "Quit", "quit moves intact to <leader>Q")

local diffview = plugin("lua/plugins/git/diffview.lua")
local line_history = mapping(diffview.keys, "<leader>gi", "n")
local range_history = mapping(diffview.keys, "<leader>gi", "v")
assert(line_history.desc == "Line history (cursor)", "Diffview owns normal <leader>gi")
assert(range_history.desc == "Line history (selection)", "Diffview owns visual <leader>gi")
absent(diffview.keys, "<leader>gL", "Diffview")
local gitlab = plugin("lua/plugins/git/gitlab.lua")
assert(mapping(gitlab.keys, "<leader>gLc") and mapping(gitlab.keys, "<leader>gLo"), "GitLab gL descendants survive")
local original_line = vim.fn.line
original_expand = vim.fn.expand
original_cmd = vim.cmd
local diffview_commands = {}
vim.fn.line = function(mark)
	return ({ ["."] = 7, ["'<"] = 3, ["'>"] = 9 })[mark]
end
vim.fn.expand = function(expr)
	eq(expr, "%", "Diffview line history still resolves the current file")
	return "lua/example.lua"
end
vim.cmd = function(command) table.insert(diffview_commands, command) end
line_history[2]()
range_history[2]()
vim.fn.line = original_line
vim.fn.expand = original_expand
vim.cmd = original_cmd
eq(diffview_commands, {
	"DiffviewFileHistory -L7,7:lua/example.lua",
	"DiffviewFileHistory -L3,9:lua/example.lua",
}, "Diffview line-history callbacks are preserved")

local rust_specs = dofile("lua/plugins/lsp-rust.lua")
local rust = rust_specs[1]
local crates_spec = rust_specs[2]
local original_rustaceanvim = vim.g.rustaceanvim
rust.config()
local rust_buf = vim.api.nvim_create_buf(false, true)
local rust_maps = capture_keymaps(function()
	vim.g.rustaceanvim.server.on_attach({}, rust_buf)
end)
vim.g.rustaceanvim = original_rustaceanvim
local open_cargo
for _, key in ipairs(rust_maps) do
	if key.lhs == "<leader>Ro" then open_cargo = key end
	assert(key.lhs ~= "<leader>Rc", "Rust open Cargo no longer shadows crates")
	if key.lhs:match("^<leader>") then
		assert(key.lhs:match("^<leader>R"), "Rust on_attach retains the R prefix")
	end
end
assert(open_cargo and open_cargo.mode == "n" and open_cargo.opts.desc == "Open Cargo.toml", "Rust open Cargo moves intact to <leader>Ro")
local original_rust_lsp = vim.cmd.RustLsp
local rust_lsp_calls = {}
vim.cmd.RustLsp = function(command) table.insert(rust_lsp_calls, command) end
open_cargo.rhs()
vim.cmd.RustLsp = original_rust_lsp
eq(rust_lsp_calls, { "openCargo" }, "Rust open-Cargo callback is preserved")

local original_crates = package.loaded["crates"]
local crates_opts
package.loaded["crates"] = setmetatable({ setup = function(opts) crates_opts = opts end }, {
	__index = function() return function() end end,
})
crates_spec.config()
local cargo_buf = vim.api.nvim_create_buf(false, true)
local crates_maps = capture_keymaps(function()
	crates_opts.lsp.on_attach({}, cargo_buf)
end)
package.loaded["crates"] = original_crates
local guard
for _, key in ipairs(crates_maps) do
	if key.lhs == "<leader>Rc" then guard = key end
end
assert(guard and mode_includes(guard.mode, "n") and mode_includes(guard.mode, "v"), "crates guards <leader>Rc in normal and visual modes")
assert(guard.rhs == "<Nop>" and guard.opts.buffer == cargo_buf, "crates Rc guard is buffer-local Nop")
assert(vim.tbl_contains(vim.tbl_map(function(key) return key.lhs end, crates_maps), "<leader>Rcd"), "crates Rc descendants remain available")

local original_workflow = package.loaded["git.workflow"]
local original_gitsigns = package.loaded["gitsigns"]
local gitsigns_opts
package.loaded["git.workflow"] = { show_single_commit_info = function() end }
package.loaded["gitsigns"] = setmetatable({ setup = function(opts) gitsigns_opts = opts end }, {
	__index = function() return function() end end,
})
local gitsigns = plugin("lua/plugins/git/gitsigns.lua")
gitsigns.config()
local signs_buf = vim.api.nvim_create_buf(false, true)
local signs_maps = capture_keymaps(function()
	gitsigns_opts.on_attach(signs_buf)
end)
package.loaded["git.workflow"] = original_workflow
package.loaded["gitsigns"] = original_gitsigns
local hunk_modes = { hs = {}, hr = {} }
for _, key in ipairs(signs_maps) do
	for name, modes in pairs(hunk_modes) do
		if key.lhs == "<leader>" .. name then table.insert(modes, key.mode) end
	end
end
eq(hunk_modes.hs, { "n", "s", "x" }, "Gitsigns stage hunk uses normal, select, then visual modes")
eq(hunk_modes.hr, { "n", "s", "x" }, "Gitsigns reset hunk uses normal, select, then visual modes")

vim.api.nvim_buf_delete(rust_buf, { force = true })
vim.api.nvim_buf_delete(cargo_buf, { force = true })
vim.api.nvim_buf_delete(signs_buf, { force = true })

print("PASS reorganized keymaps stay owner-correct and preserve surviving actions")

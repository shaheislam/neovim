local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local spec = dofile("lua/plugins/which-key.lua")[1]

eq(spec.event, nil, "which-key loads eagerly so its leader trigger is ready")
eq(spec.opts.delay, 300, "the leader popup waits past the first held-Space repeat")

local mappings = {}
local registrations
local original_keymap_set = vim.keymap.set
local original_which_key = package.loaded["which-key"]
vim.keymap.set = function(mode, lhs, rhs, opts)
	table.insert(mappings, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
end
package.loaded["which-key"] = {
	setup = function() end,
	add = function(items)
		registrations = items
	end,
}

local ok, err = xpcall(function()
	spec.config(nil, vim.deepcopy(spec.opts))
end, debug.traceback)
vim.keymap.set = original_keymap_set
package.loaded["which-key"] = original_which_key
assert(ok, err)

local function registration(lhs)
	for _, item in ipairs(registrations or {}) do
		if item[1] == lhs then
			return item
		end
	end
end

eq(registration("<leader>a").group, "AI / OpenCode fast lane", "which-key labels the OpenCode fast lane")
eq(registration("<leader>ao").group, "Advanced OpenCode", "which-key labels the advanced OpenCode subgroup")

local guarded = {}
for _, mapping in ipairs(mappings) do
	if mapping.rhs == "<Nop>" then
		guarded[mapping.lhs] = mapping.mode
	end
end
local function has_mode(mode, target)
	return mode == target or type(mode) == "table" and vim.tbl_contains(mode, target)
end
for _, lhs in ipairs({ "<leader>a", "<leader>ao", "<leader>ap", "<leader>as" }) do
	assert(has_mode(guarded[lhs], "n") and has_mode(guarded[lhs], "x"), lhs .. " guards normal and visual modes")
end
for _, lhs in ipairs({ "<leader>q", "<leader>v", "<leader>t", "<leader>T", "<leader>x", "<leader>H", "<leader>R", "<leader>gL" }) do
	eq(guarded[lhs], "n", lhs .. " is protected from normal-mode prefix fallthrough")
end
assert(not guarded["<leader>w"], "<leader>w remains an actionable save mapping, not a Nop prefix")

print("PASS which-key registers reorganized groups and guards only real prefixes")

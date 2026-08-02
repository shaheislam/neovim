local function eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
  )
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
dofile("lua/config/keymaps.lua")

local mapping = vim.fn.maparg("<C-Space>", "t", false, true)

eq(mapping.rhs, [[<C-\><C-n><Space>]], "Ctrl-Space exits terminal mode and starts a leader sequence")
eq(mapping.noremap, 0, "the replayed Space is recursively resolved as the Normal-mode leader trigger")

print("PASS Ctrl-Space starts a leader sequence from terminal mode")

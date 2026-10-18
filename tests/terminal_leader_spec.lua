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

eq(mapping.rhs, [[<C-\><C-n><Cmd>lua require("which-key").show({ keys = vim.g.mapleader, mode = "n" })<CR>]], "Ctrl-Space exits terminal mode and opens the leader directly")
eq(mapping.noremap, 1, "Ctrl-Space does not replay Space through a temporarily detached leader trigger")

print("PASS Ctrl-Space starts a leader sequence from terminal mode")

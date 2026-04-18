vim.opt.rtp:prepend(vim.fn.getcwd())

local review = require("parley.review")

local function eq(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message or (vim.inspect(actual) .. " ~= " .. vim.inspect(expected)))
end

local entries = review.collect({
  "Intro ㊷[this paragraph is too vague] outro",
  "㊷[needs stronger evidence]  {do you mean product metrics?}",
  "㊷[first] and ㊷[second]{clarify the second point}",
})

eq(#entries, 4, "expected all review markers to be collected")
eq(entries[1].text, "this paragraph is too vague")
eq(entries[1].question, nil)
eq(entries[1].lnum, 0)
eq(entries[2].text, "needs stronger evidence")
eq(entries[2].question, "do you mean product metrics?")
eq(entries[3].text, "first")
eq(entries[4].question, "clarify the second point")

local diagnostics = review.to_diagnostics(entries)
eq(diagnostics[1].severity, vim.diagnostic.severity.HINT)
eq(diagnostics[2].severity, vim.diagnostic.severity.WARN)

review.setup()

local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(bufnr)
vim.bo[bufnr].filetype = "markdown"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
  "# Draft",
  "㊷[add an example here]{prefer a production incident}",
})
vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })

local commands = vim.api.nvim_buf_get_commands(bufnr, {})
assert(commands.ParleyReviewRefresh, "expected markdown buffer to expose ParleyReviewRefresh")
assert(commands.ParleyReviewQuickfix, "expected markdown buffer to expose ParleyReviewQuickfix")

local buffer_diagnostics = vim.diagnostic.get(bufnr)
eq(#buffer_diagnostics, 1, "expected one review diagnostic in markdown buffer")
eq(buffer_diagnostics[1].message, "add an example here | Question: prefer a production incident")

vim.cmd("ParleyReviewQuickfix")
local qflist = vim.fn.getqflist()
eq(#qflist, 1, "expected one quickfix item from review markers")
eq(qflist[1].text, "add an example here | Question: prefer a production incident")

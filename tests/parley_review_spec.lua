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

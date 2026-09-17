local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local spec = dofile("lua/plugins/codecompanion.lua")[1]
local interactions = spec.opts.interactions

eq(spec[1], "olimorris/codecompanion.nvim", "the pilot uses CodeCompanion")
eq(spec.version, false, "CodeCompanion follows the repository's latest-commit policy")
eq(spec.cmd, { "CodeCompanionCodeReview" }, "only the code-review command loads CodeCompanion")
eq(spec.keys, nil, "the pilot adds no keymaps")
eq(spec.event, nil, "the pilot adds no event trigger")
eq(spec.ft, nil, "the pilot adds no filetype trigger")
eq(spec.dependencies, { "nvim-lua/plenary.nvim" }, "the pilot reuses its only required dependency")
eq(interactions.opts.watcher.enabled, false, "CodeCompanion does not compete with the existing file watcher")
eq(interactions.code_review.enabled, true, "code review is enabled explicitly")
eq(interactions.code_review.display.diff.provider, "native", "the pilot keeps CodeCompanion's isolated diff provider")
eq(interactions.chat, nil, "the pilot does not configure chat")
eq(interactions.inline, nil, "the pilot does not configure inline edits")
eq(interactions.cli, nil, "the pilot does not configure a CLI agent")
eq(spec.opts.adapters, nil, "the pilot does not configure model adapters")

print("PASS CodeCompanion stays command-lazy and review-only")

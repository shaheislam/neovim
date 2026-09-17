local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local spec = dofile("lua/plugins/codecompanion.lua")[1]
local interactions = spec.opts.interactions
local review = interactions.code_review

local forwarded
local action
package.loaded["git.codecompanion_review"] = {
	provider = function(target)
		forwarded = target
	end,
	resync_after = function(name)
		action = name
	end,
	run = function(name)
		action = name
	end,
}

eq(spec[1], "olimorris/codecompanion.nvim", "the pilot uses CodeCompanion")
eq(spec.version, false, "CodeCompanion follows the repository's latest-commit policy")
eq(spec.cmd, { "CodeCompanionCodeReview" }, "only the code-review command loads CodeCompanion")
eq(spec.keys, nil, "the pilot adds no keymaps")
eq(spec.event, nil, "the pilot adds no event trigger")
eq(spec.ft, nil, "the pilot adds no filetype trigger")
eq(spec.dependencies, { "nvim-lua/plenary.nvim" }, "the pilot reuses its only required dependency")
eq(interactions.opts.watcher.enabled, false, "CodeCompanion does not compete with the existing file watcher")
eq(review.enabled, true, "code review is enabled explicitly")
eq(type(review.display.diff.provider), "function", "the pilot delegates review rendering")
local target = { root = "/repo", path = "file.lua", baseline_ref = "baseline", line = 7, id = 11 }
review.display.diff.provider(target)
eq(forwarded, target, "the review target is forwarded unchanged")
eq(review.keymaps.accept.modes, { n = "a" }, "accept keeps CodeCompanion's review key")
eq(review.keymaps.ignore.modes, { n = "x" }, "ignore keeps CodeCompanion's review key")
review.keymaps.accept.callback()
eq(action, "accept", "accept resynchronizes the review view")
review.keymaps.comment.callback()
eq(action, "comment", "comment keeps CodeCompanion's review action")
review.keymaps.diff.callback()
eq(action, "open_diff", "diff keeps CodeCompanion's review action")
review.keymaps.ignore.callback()
eq(action, "ignore", "ignore resynchronizes the review view")
eq(interactions.chat, nil, "the pilot does not configure chat")
eq(interactions.inline, nil, "the pilot does not configure inline edits")
eq(interactions.cli, nil, "the pilot does not configure a CLI agent")
eq(spec.opts.adapters, nil, "the pilot does not configure model adapters")

print("PASS CodeCompanion stays command-lazy and review-only")

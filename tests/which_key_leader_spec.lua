local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local spec = dofile("lua/plugins/which-key.lua")[1]

eq(spec.event, nil, "which-key loads eagerly so its leader trigger is ready")
eq(spec.opts.delay({ keys = "<Space>" }), 0, "the leader popup appears before held Space repeats")
eq(spec.opts.delay({ keys = "g" }), 300, "non-leader triggers keep the existing delay")

print("PASS which-key leader trigger loads eagerly with immediate feedback")

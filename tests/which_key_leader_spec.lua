local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local spec = dofile("lua/plugins/which-key.lua")[1]

eq(spec.event, nil, "which-key loads eagerly so its leader trigger is ready")
eq(spec.opts.delay, 300, "the leader popup waits past the first held-Space repeat")

print("PASS which-key leader trigger loads eagerly without flashing on held Space")

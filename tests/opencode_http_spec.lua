package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(vim.deep_equal(actual, expected), string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual)))
end

local http = require("config.opencode_http")
local original_get = http.get
local original_post = http.post
local original_notify = vim.notify
local request = {}

http.get = function(path, callback, opts)
	request.get = { path = path, opts = opts }
	callback(true, vim.json.encode({
		{ id = "ses_older", time = { updated = 10 } },
		{ id = "ses_current", time = { updated = 20 } },
	}))
end

http.post = function(path, body, callback, opts)
	request.post = { path = path, body = body, opts = opts }
	callback(true, "")
end

vim.notify = function(message)
	request.notification = message
end

http.send_with_model("review this", "openai", "gpt-5.6", {
	dir = "/tmp/review-root",
	success = "Prompt accepted",
})

http.get = original_get
http.post = original_post
vim.notify = original_notify

eq(request.get.path, "/session", "lists sessions in the current workspace")
eq(request.post.path, "/session/ses_current/prompt_async", "submits without waiting for the model response")
eq(request.post.body, {
	model = { providerID = "openai", modelID = "gpt-5.6" },
	parts = { { type = "text", text = "review this" } },
}, "preserves the requested model and prompt")
eq(request.post.opts, { dir = "/tmp/review-root" }, "routes the prompt to the requested workspace")
eq(request.notification, "Prompt accepted", "reports acceptance after the async endpoint returns")

print("PASS asynchronous OpenCode model submission")

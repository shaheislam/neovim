package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message or "values differ", vim.inspect(expected), vim.inspect(actual))
	)
end

local http = dofile("lua/config/opencode_http.lua")
local original_post = http.post
local post_calls = {}

http.post = function(path, body, callback, opts)
	table.insert(post_calls, {
		path = path,
		body = body,
		dir = opts and opts.dir,
	})
	if callback then
		callback(true, "")
	end
end

local callback_ok, callback_output
http.publish_command("session.timeline", function(ok, output)
	callback_ok = ok
	callback_output = output
end, { dir = "/tmp/opencode-http-spec" })

eq(callback_ok, true, "publish_command preserves callback success")
eq(callback_output, "", "publish_command preserves callback output")
eq(post_calls[1], {
	path = "/tui/publish",
	body = { type = "tui.command.execute", properties = { command = "session.timeline" } },
	dir = "/tmp/opencode-http-spec",
}, "publish_command forwards dir to the POST request")

http.publish_commands({ "dialog.select.home", "dialog.select.next" }, function(ok, output)
	callback_ok = ok
	callback_output = output
end, { dir = "/tmp/opencode-http-batch-spec" })

eq(callback_ok, true, "publish_commands preserves callback success")
eq(callback_output, nil, "publish_commands completes without error output")
eq(post_calls[2], {
	path = "/tui/publish",
	body = { type = "tui.command.execute", properties = { command = "dialog.select.home" } },
	dir = "/tmp/opencode-http-batch-spec",
}, "publish_commands forwards dir to the first POST request")
eq(post_calls[3], {
	path = "/tui/publish",
	body = { type = "tui.command.execute", properties = { command = "dialog.select.next" } },
	dir = "/tmp/opencode-http-batch-spec",
}, "publish_commands forwards dir to later POST requests")

post_calls = {}
http.publish_command("session.timeline", nil, { dir = "/tmp/opencode-http-no-callback" })
eq(post_calls[1].dir, "/tmp/opencode-http-no-callback", "publish_command keeps dir forwarding without a callback")

http.post = original_post

print("PASS publish_command forwards stable route options")
print("PASS publish_commands forwards stable route options")

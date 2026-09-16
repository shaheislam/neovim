package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function contains(args, value)
	for _, arg in ipairs(args) do
		if arg == value then
			return true
		end
	end
	return false
end

local original_system = vim.system
local original_jobstart = vim.fn.jobstart
local original_chansend = vim.fn.chansend
local original_chanclose = vim.fn.chanclose
local original_schedule = vim.schedule
local original_password = vim.env.OPENCODE_SERVER_PASSWORD
local original_username = vim.env.OPENCODE_SERVER_USERNAME

vim.env.OPENCODE_SERVER_PASSWORD = "http-spec-secret"
vim.env.OPENCODE_SERVER_USERNAME = "http-spec-user"
vim.schedule = function(callback)
	callback()
end

local system_call
vim.system = function(args, opts, callback)
	system_call = { args = args, opts = opts }
	callback({ code = 0, stdout = '{"ok":true}', stderr = "" })
end

package.loaded["config.opencode_http"] = nil
local http = require("config.opencode_http")
local callback_result
http.request("GET", "/skill", nil, function(ok, output)
	callback_result = { ok = ok, output = output }
end, { dir = "/tmp/http spec", timeout = 17 })

eq(callback_result, { ok = true, output = '{"ok":true}' }, "GET returns the scheduled system result")
assert(contains(system_call.args, "GET"), "GET request includes its method")
assert(contains(system_call.args, "17"), "GET request includes its custom timeout")
assert(contains(system_call.args, "x-opencode-directory: /tmp/http spec"), "GET request includes its directory header")
assert(contains(system_call.args, "http-spec-user:http-spec-secret"), "GET request includes basic auth")
assert(not contains(system_call.args, "--data-binary"), "GET without a body omits stdin transport")
eq(system_call.opts.stdin, nil, "GET without a body does not provide stdin")

http.request("POST", "/session", { title = "Transform" }, function() end, { timeout = 120 })
assert(contains(system_call.args, "POST"), "POST request includes its method")
assert(contains(system_call.args, "Content-Type: application/json"), "POST request includes JSON content type")
assert(contains(system_call.args, "--data-binary"), "POST request streams a JSON body")
eq(vim.json.decode(system_call.opts.stdin), { title = "Transform" }, "POST encodes its body on stdin")

http.request("DELETE", "/session/ses_test", nil, function() end)
assert(contains(system_call.args, "DELETE"), "DELETE request includes its method")
assert(not contains(system_call.args, "--data-binary"), "bodyless DELETE omits stdin transport")

local wrapper_calls = {}
local original_request = http.request
http.request = function(method, path, body, callback, opts)
	table.insert(wrapper_calls, { method = method, path = path, body = body, opts = opts })
	callback(true, "")
end
http.get("/skill", function() end, { dir = "/tmp/get" })
http.post("/session", { title = "x" }, function() end, { dir = "/tmp/post" })
http.patch("/session/ses_x", { title = "y" }, function() end, { dir = "/tmp/patch" })
http.delete("/session/ses_x", function() end, { dir = "/tmp/delete" })
eq(wrapper_calls[1].method, "GET", "get wrapper delegates to request")
eq(wrapper_calls[2].method, "POST", "post wrapper delegates to request")
eq(wrapper_calls[3].method, "PATCH", "patch wrapper delegates to request")
eq(wrapper_calls[4].method, "DELETE", "delete wrapper delegates to request")
http.request = original_request

local job_call
local sent
vim.system = nil
vim.fn.jobstart = function(args, opts)
	job_call = { args = args, opts = opts }
	return 42
end
vim.fn.chansend = function(job, text)
	sent = { job = job, text = text }
end
vim.fn.chanclose = function() end

callback_result = nil
http.request("POST", "/session", { title = "Fallback" }, function(ok, output)
	callback_result = { ok = ok, output = output }
end)
eq(vim.json.decode(sent.text), { title = "Fallback" }, "jobstart fallback sends the JSON body")
job_call.opts.on_stdout(nil, { '{"id":"ses_test"}', "" })
job_call.opts.on_stderr(nil, { "" })
job_call.opts.on_exit(nil, 0)
eq(callback_result, { ok = true, output = '{"id":"ses_test"}\n' }, "jobstart fallback schedules its response")

vim.system = original_system
vim.fn.jobstart = original_jobstart
vim.fn.chansend = original_chansend
vim.fn.chanclose = original_chanclose
vim.schedule = original_schedule
vim.env.OPENCODE_SERVER_PASSWORD = original_password
vim.env.OPENCODE_SERVER_USERNAME = original_username

print("PASS OpenCode HTTP requests share one method-aware transport")

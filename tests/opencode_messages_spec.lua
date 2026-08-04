package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local saved_system = vim.system
local saved_executable = vim.fn.executable
local saved_g_cwd = vim.fn.getcwd
local saved_env = vim.deepcopy(vim.env)
local saved_g = vim.deepcopy(vim.g)

local responses = {}
local calls = {}

local function reset_globals()
	vim.system = saved_system
	vim.fn.executable = saved_executable
	vim.fn.getcwd = saved_g_cwd
	for k in pairs(vim.env) do
		vim.env[k] = nil
	end
	for k, v in pairs(saved_env) do
		vim.env[k] = v
	end
	for k in pairs(vim.g) do
		vim.g[k] = nil
	end
	for k, v in pairs(saved_g) do
		vim.g[k] = v
	end
end

local function set_system(queue)
	responses = vim.deepcopy(queue)
	calls = {}
	vim.fn.executable = function(bin)
		if bin == "curl" or bin == "sqlite3" then
			return 1
		end
		return saved_executable(bin)
	end
	vim.fn.getcwd = function()
		return "/cwd/default"
	end
	vim.system = function(args, opts, callback)
		table.insert(calls, { args = vim.deepcopy(args), opts = vim.deepcopy(opts) })
		local response = table.remove(responses, 1)
		assert(response, "missing queued vim.system response")
		callback(vim.tbl_extend("keep", response, { code = 0, stdout = "", stderr = "" }))
	end
	vim.fn.filereadable = function(path)
		if path == "/tmp/opencode.db" then
			return 1
		end
		return 0
	end
	vim.env.OPENCODE_DB_PATH = "/tmp/opencode.db"
	vim.env.OPENCODE_SERVER_URL = nil
	vim.g.opencode_server_url = nil
end

local function load_module()
	package.loaded["config.opencode_messages"] = nil
	return dofile("lua/config/opencode_messages.lua")
end

local function await(invoke)
	local done, result, err, meta = false, nil, nil, nil
	invoke(function(...)
		result, err, meta = ...
		done = true
	end)
	assert(vim.wait(1000, function()
		return done
	end), "timed out waiting for callback")
	return result, err, meta
end

local function has_arg(args, expected)
	for _, arg in ipairs(args) do
		if arg == expected then
			return true
		end
	end
	return false
end

set_system({
	{ stdout = vim.json.encode({ { id = "local-1", time = { updated = 1 } } }) },
})
local messages = load_module()
local sessions = await(function(cb)
	messages.sessions(cb)
end)
eq(sessions, { { id = "local-1", time = { updated = 1 } } }, "default sessions keeps legacy /session path")
eq(calls[1].args[#calls[1].args], "http://127.0.0.1:4096/session", "default sessions uses /session")
assert(has_arg(calls[1].args, "x-opencode-directory: /cwd/default"), "default sessions uses cwd header")
print("PASS default sessions keeps legacy /session behavior")

set_system({
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: next value/+=\r\n\r\n"
			.. vim.json.encode({
				{ id = "b", time = { updated = 3 } },
				{ id = "c", time = { updated = 2 } },
			}),
	},
	{
		stdout = "HTTP/1.1 200 OK\r\n\r\n"
			.. vim.json.encode({
				{ id = "a", time = { updated = 3 } },
				{ id = "b", time = { updated = 3 } },
			}),
	},
})
messages = load_module()
sessions = await(function(cb)
	messages.sessions(cb, { catalog = "global", dir = "/project alpha" })
end)
eq(vim.tbl_map(function(session)
	return session.id
end, sessions), { "a", "b", "c" }, "global catalog paginates, dedupes, and sorts by updated desc then id")
eq(calls[1].args[#calls[1].args], "http://127.0.0.1:4096/experimental/session?limit=100", "global catalog uses experimental route")
eq(
	calls[2].args[#calls[2].args],
	"http://127.0.0.1:4096/experimental/session?limit=100&cursor=next%20value%2F%2B%3D",
	"global catalog URI encodes cursor values"
)
assert(has_arg(calls[1].args, "x-opencode-directory: /project alpha"), "global catalog forwards explicit dir")
print("PASS global catalog paginates with encoded cursors and deterministic ordering")

set_system({
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: page-2\r\n\r\n" .. vim.json.encode({ { id = "page-1" } }),
	},
	{ code = 22, stderr = "page 2 failed" },
	{ code = 1, stderr = "sqlite fallback failed" },
	{ stdout = vim.json.encode({ { id = "fresh" } }) },
})
messages = load_module()
local failed, err = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(failed, nil, "global catalog later-page failures fail the request")
assert(err:match("page 2 failed"), "later-page failure surfaces the transport error")
sessions = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(sessions, { { id = "fresh" } }, "later-page failures never cache partial pages")
eq(#calls, 4, "later-page failure causes a complete fallback attempt and full HTTP refetch on retry")
print("PASS global catalog does not cache partial pages after a later-page failure")

set_system({
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: cursor-2\r\n\r\n" .. vim.json.encode({ { id = "one" } }),
	},
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: cursor-2\r\n\r\n" .. vim.json.encode({ { id = "two" } }),
	},
	{ code = 1, stderr = "sqlite fallback failed" },
})
messages = load_module()
failed, err = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(failed, nil, "repeated cursors fail closed")
assert(err:match("cursor"), "repeated cursor failure mentions cursor safety")
print("PASS global catalog rejects repeated cursors")

set_system({
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: cursor-3\r\n\r\n" .. vim.json.encode({ { id = "one" } }),
	},
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: cursor-4\r\n\r\n" .. vim.json.encode({ { id = "two" } }),
	},
	{ stdout = "HTTP/1.1 200 OK\r\n\r\n" .. vim.json.encode({ { id = "three" } }) },
})
messages = load_module()
sessions = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(
	sessions,
	{ { id = "one" }, { id = "three" }, { id = "two" } },
	"distinct opaque cursors are not compared lexically"
)
print("PASS global catalog accepts distinct opaque cursors")

set_system({
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: 9\r\n\r\n" .. vim.json.encode({ { id = "one" } }),
	},
	{
		stdout = "HTTP/1.1 200 OK\r\nx-next-cursor: 10\r\n\r\n" .. vim.json.encode({ { id = "two" } }),
	},
	{ code = 1, stderr = "sqlite fallback failed" },
})
messages = load_module()
failed, err = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(failed, nil, "numeric cursors must decrease numerically")
assert(err:match("cursor"), "numeric cursor failure mentions cursor safety")
print("PASS global catalog compares numeric cursors numerically")

set_system({
	{ stdout = "HTTP/1.1 200 OK\r\n\r\n" .. vim.json.encode({ { id = "dir-a" } }) },
	{ stdout = "HTTP/1.1 200 OK\r\n\r\n" .. vim.json.encode({ { id = "dir-b" } }) },
	{ stdout = "HTTP/1.1 200 OK\r\n\r\n" .. vim.json.encode({ { id = "dir-a-refresh" } }) },
	{ stdout = vim.json.encode({ { id = "local-cache" } }) },
})
messages = load_module()
local dir_a = await(function(cb)
	messages.sessions(cb, { catalog = "global", dir = "/dir/a" })
end)
local dir_b = await(function(cb)
	messages.sessions(cb, { catalog = "global", dir = "/dir/b" })
end)
local dir_a_cached = await(function(cb)
	messages.sessions(cb, { catalog = "global", dir = "/dir/a" })
end)
local dir_a_refresh = await(function(cb)
	messages.sessions(cb, { catalog = "global", dir = "/dir/a", refresh = true })
end)
local local_cache = await(function(cb)
	messages.sessions(cb)
end)
eq(dir_a, { { id = "dir-a" } }, "initial global cache stores by dir context")
eq(dir_b, { { id = "dir-b" } }, "different dir gets a separate cache entry")
eq(dir_a_cached, { { id = "dir-a" } }, "same dir reuses cached global catalog")
eq(dir_a_refresh, { { id = "dir-a-refresh" } }, "refresh bypasses the scoped cache")
eq(local_cache, { { id = "local-cache" } }, "default catalog remains separately cached")
eq(#calls, 4, "cache keys isolate catalog and dir while refresh refetches")
print("PASS cache isolates catalog and route context and supports refresh")

set_system({
	{ code = 22, stderr = "local catalog unavailable" },
	{
		stdout = vim.json.encode({
			{ id = "db-1", directory = "~/alias/project", title = "DB Session", time_updated = 11, time_created = 7 },
		}),
	},
})
messages = load_module()
sessions = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(sessions[1].directory, "~/alias/project", "global DB fallback keeps raw directory aliases")
assert(calls[2].args[4]:match("where time_archived is null"), "global DB fallback queries all non-archived sessions")
assert(not calls[2].args[4]:lower():match("limit%s+50"), "global DB fallback removes the legacy session limit")
print("PASS global DB fallback is uncapped and preserves raw directories")

set_system({
	{ code = 22, stderr = "remote unavailable" },
	{ stdout = vim.json.encode({ { id = "db-should-not-leak" } }) },
})
vim.g.opencode_server_url = "https://remote.example.test"
messages = load_module()
failed, err = await(function(cb)
	messages.sessions(cb, { catalog = "global" })
end)
eq(failed, nil, "custom server global failures do not fall back to local DB")
eq(err, "OpenCode global catalog unavailable", "custom server mismatch returns catalog unavailable")
eq(#calls, 1, "custom server mismatch never queries sqlite")
print("PASS custom or remote global failures never leak local DB rows")

set_system({
	{ stdout = vim.json.encode({ { id = "m1" } }) },
})
vim.g.opencode_server_url = nil
messages = load_module()
local fetched = await(function(cb)
	messages.messages("session-1", cb, { dir = "/message/dir" })
end)
local cached = await(function(cb)
	messages.messages("session-1", cb, { dir = "/other/dir" })
end)
eq(fetched, { { id = "m1" } }, "message fetch succeeds")
eq(cached, { { id = "m1" } }, "message cache remains keyed by session id")
assert(has_arg(calls[1].args, "x-opencode-directory: /message/dir"), "message fetch forwards opts.dir to curl")
eq(#calls, 1, "message cache behavior is preserved after forwarding opts.dir")
print("PASS messages forward opts.dir without changing session-id cache behavior")

reset_globals()

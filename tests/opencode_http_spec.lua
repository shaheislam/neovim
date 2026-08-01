package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local sandbox = vim.fn.tempname()
assert(vim.fn.mkdir(sandbox .. "/visible-root/nested", "p") == 1, "failed to create temporary project")
local attach_cwd = assert(vim.uv.fs_realpath(sandbox .. "/visible-root"), "failed to canonicalize temporary project")
local equivalent_cwd = attach_cwd .. "/nested/.."
local visible_title = "Visible root"
local visible_pane_title = "OC | " .. visible_title
local target = { pane = "%2", cwd = attach_cwd, title = visible_pane_title }
local original_tmux_module = package.loaded["config.opencode_tmux"]
local resolve_results = {}
local resolve_calls = 0

package.loaded["config.opencode_tmux"] = {
	resolve_attach = function()
		resolve_calls = resolve_calls + 1
		local result = resolve_results[resolve_calls] or resolve_results[#resolve_results]
		return result and vim.deepcopy(result) or nil
	end,
}

local http = require("config.opencode_http")
local original_get = http.get
local original_post = http.post
local original_notify = vim.notify
local request = {}
local notifications = {}
local response
local get_ok
local post_ok

local function root_session(id, title, directory, extra)
	local session = {
		id = id,
		title = title,
		directory = directory or attach_cwd,
		parentID = vim.NIL,
		parent_id = vim.NIL,
		time = { updated = 10, archived = vim.NIL },
	}
	for key, value in pairs(extra or {}) do
		session[key] = value
	end
	return session
end

local function reset(opts)
	opts = opts or {}
	request = {}
	notifications = {}
	resolve_calls = 0
	resolve_results = opts.resolve_results or { target, target }
	response = opts.response
		or {
			root_session("ses_wrong_dir", visible_title, "/tmp/other-root"),
			root_session("ses_archived", visible_title, attach_cwd, {
				time = { updated = 30, archived = 20 },
			}),
			root_session("ses_visible", visible_title, equivalent_cwd),
			{
				id = "ses_hidden",
				title = visible_title,
				directory = attach_cwd,
				parentID = "ses_visible",
				parent_id = vim.NIL,
				time = { updated = 100, archived = vim.NIL },
			},
			{ id = 9, title = visible_title, directory = attach_cwd, time = {} },
		}
	get_ok = opts.get_ok ~= false
	post_ok = opts.post_ok ~= false
end

http.get = function(path, callback, opts)
	request.get = { path = path, opts = opts }
	if get_ok then
		callback(true, type(response) == "string" and response or vim.json.encode(response))
	else
		callback(false, "list failed")
	end
end

http.post = function(path, body, callback, opts)
	request.post = { path = path, body = body, opts = opts }
	callback(post_ok, post_ok and "" or "send failed")
end

vim.notify = function(message, level, opts)
	table.insert(notifications, { message = message, level = level, opts = opts })
end

local function send()
	http.send_with_model("review this", "openai", "gpt-5.6", {
		dir = "/tmp/neovim-root",
		success = "Prompt accepted",
	})
end

reset()
send()
eq(request.get, {
	path = "/session?roots=true&limit=1000",
	opts = { dir = attach_cwd },
}, "lists root sessions in the adjacent OpenCode workspace")
eq(request.post.path, "/session/ses_visible/prompt_async", "submits only to the visible root session")
eq(request.post.body, {
	model = { providerID = "openai", modelID = "gpt-5.6" },
	parts = { { type = "text", text = "review this" } },
}, "preserves the requested model and prompt")
eq(request.post.opts, { dir = attach_cwd }, "routes the prompt through the adjacent OpenCode workspace")
eq(notifications[#notifications].message, "Prompt accepted", "reports acceptance only after targeted submission")
eq(resolve_calls, 2, "revalidates the attachment immediately before submission")

local original_getcwd = vim.fn.getcwd
vim.fn.getcwd = function()
	return equivalent_cwd
end
reset({ resolve_results = {} })
send()
eq(request.get, {
	path = "/session?roots=true&limit=1000",
	opts = { dir = attach_cwd },
}, "falls back to the current directory when no tmux attach is registered")
eq(
	request.post.path,
	"/session/ses_visible/prompt_async",
	"submits to the sole root session for the current directory"
)
eq(
	notifications[#notifications].message,
	"Prompt accepted",
	"reports success via the no-attach directory fallback"
)
eq(resolve_calls, 1, "does not revalidate a pane that was never identified")
vim.fn.getcwd = original_getcwd

local function expect_rejected(label, opts)
	reset(opts)
	send()
	eq(request.post, nil, label .. " must not submit a prompt")
	assert(
		#notifications > 0 and notifications[#notifications].message ~= "Prompt accepted",
		label .. " must not report success"
	)
end

expect_rejected("missing same-window attachment", { resolve_results = {} })
expect_rejected("default OpenCode route", {
	resolve_results = {
		{ pane = "%2", cwd = attach_cwd, title = "OpenCode" },
	},
})
expect_rejected("non-ASCII route title", {
	resolve_results = {
		{ pane = "%2", cwd = attach_cwd, title = "OC | Caf" .. string.char(195, 169) },
	},
})
expect_rejected("no matching visible root", {
	response = { root_session("ses_other", "Another root") },
})

local shared_prefix = string.rep("a", 37)
expect_rejected("ambiguous truncated titles", {
	resolve_results = {
		{ pane = "%2", cwd = attach_cwd, title = "OC | " .. shared_prefix .. "..." },
	},
	response = {
		root_session("ses_one", shared_prefix .. "ONE!"),
		root_session("ses_two", shared_prefix .. "TWO!"),
	},
})
expect_rejected("malformed session response", { response = "{}" })

local saturated = {}
for index = 1, 1000 do
	table.insert(saturated, root_session("ses_" .. index, "Other " .. index))
end
expect_rejected("saturated session response", { response = saturated })
expect_rejected("empty parent metadata", {
	response = { root_session("ses_bad_parent", visible_title, attach_cwd, { parentID = "" }) },
})
expect_rejected("wrong-type parent metadata", {
	response = { root_session("ses_bad_parent", visible_title, attach_cwd, { parent_id = 7 }) },
})
expect_rejected("session changed before submit", {
	resolve_results = {
		target,
		{ pane = "%2", cwd = attach_cwd, title = "OC | Another root" },
	},
})
expect_rejected("session listing failure", { get_ok = false })

reset({ post_ok = false })
send()
assert(request.post, "targeted submission failure reaches only the selected endpoint")
assert(
	#notifications > 0 and notifications[#notifications].message ~= "Prompt accepted",
	"targeted submission failure must not report success"
)

local original_http_module = package.loaded["config.opencode_http"]
local original_nui_input = package.loaded["nui.input"]
local original_input = vim.ui.input
local mapping_calls = {}
package.loaded["config.opencode_http"] = {
	send_with_model = function(text, provider, model, opts)
		table.insert(mapping_calls, { text = text, provider = provider, model = model, opts = opts })
	end,
}
vim.ui.input = function()
	error("<leader>aoa must use the modal NUI prompt instead of vim.ui.input")
end
local modal_submit
package.loaded["nui.input"] = function(_, opts)
	modal_submit = opts.on_submit
	return {
		map = function() end,
		mount = function() end,
		unmount = function() end,
	}
end

local plugin_specs = dofile("lua/plugins/opencode.lua")
local ask
local ask_visual
for _, key in ipairs(plugin_specs[1].keys) do
	if key[1] == "<leader>aoa" and key.mode == "n" then
		ask = key[2]
	elseif key[1] == "<leader>aoa" and key.mode == "x" then
		ask_visual = key[2]
	end
end
assert(ask, "normal <leader>aoa mapping is present")
assert(ask_visual, "visual <leader>aoa mapping is present")

local original_buffer = vim.api.nvim_get_current_buf()
local ask_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(ask_buffer)
vim.api.nvim_buf_set_name(ask_buffer, "diffview://deadbeef:lua/example.lua")
ask()
assert(type(modal_submit) == "function", "normal <leader>aoa exposes the NUI prompt submit callback")
modal_submit("what does this do")

vim.api.nvim_buf_set_lines(ask_buffer, 0, -1, false, { "local answer = 42" })
vim.fn.setpos("'<", { 0, 1, 1, 0 })
vim.fn.setpos("'>", { 0, 1, 17, 0 })
ask_visual()
assert(type(modal_submit) == "function", "visual <leader>aoa exposes the NUI prompt submit callback")
modal_submit("why")

eq(mapping_calls, {
	{
		text = "[file: lua/example.lua]\nwhat does this do",
		provider = "anthropic",
		model = "claude-sonnet-5",
		opts = { title = "opencode", success = "Sent to OpenCode" },
	},
	{
		text = "[file: lua/example.lua, lines 1-1]\nlocal answer = 42\nwhy",
		provider = "anthropic",
		model = "claude-sonnet-5",
		opts = { title = "opencode", success = "Sent to OpenCode" },
	},
}, "normal and visual <leader>aoa prompts delegate their exact context to targeted model submission")

vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(ask_buffer, { force = true })
vim.ui.input = original_input
package.loaded["nui.input"] = original_nui_input
package.loaded["config.opencode_http"] = original_http_module
http.get = original_get
http.post = original_post
vim.notify = original_notify
package.loaded["config.opencode_tmux"] = original_tmux_module
assert(vim.fn.delete(sandbox, "rf") == 0, "failed to remove temporary project")

print("PASS visible same-window OpenCode model submission")
print("PASS OpenCode visible-session fail-closed routing")
print("PASS normal and visual <leader>aoa modal prompt transport wiring")

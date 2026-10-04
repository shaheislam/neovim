package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected)
	assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local forge = require("git.forge")
eq(forge.parse("git@bitbucket.org:altitudeadsdev/k8s-infra.git"), {
	type = "bitbucket", host = "bitbucket.org", path = "altitudeadsdev/k8s-infra",
})
eq(forge.parse("https://bitbucket.org/altitudeadsdev/k8s-infra"), {
	type = "bitbucket", host = "bitbucket.org", path = "altitudeadsdev/k8s-infra",
})
eq(forge.parse("ssh://git@bitbucket.org/altitudeadsdev/k8s-infra.git"), {
	type = "bitbucket", host = "bitbucket.org", path = "altitudeadsdev/k8s-infra",
})
eq(forge.parse("git@github.com-personal:owner/repo.git"), {
	type = "github", host = "github.com", path = "owner/repo",
})
assert(forge.parse("git@bitbucket.org.evil:owner/repo.git").type ~= "bitbucket")

local maps = {}
local original_map = vim.keymap.set
vim.keymap.set = function(_, lhs, rhs) maps[lhs] = rhs end
dofile("lua/config/keymaps.lua")
vim.keymap.set = original_map
assert(maps["<leader>gop"], "forge-aware PR shortcut exists")
for _, spec in ipairs(dofile("lua/plugins/octo.lua")[1].keys) do
	assert(spec[1] ~= "<leader>gop", "Octo must not load on Bitbucket PR shortcut")
end

local original_get = forge.get
local original_lazy = package.loaded.lazy
local original_bitbucket = package.loaded["git.bitbucket"]
local original_picker = _G.octo_pr_picker
local lazy_calls, bitbucket_calls, octo_calls = 0, 0, 0
package.loaded.lazy = { load = function() lazy_calls = lazy_calls + 1 end }
package.loaded["git.bitbucket"] = { open = function() bitbucket_calls = bitbucket_calls + 1 end }
_G.octo_pr_picker = function() octo_calls = octo_calls + 1 end
forge.get = function() return { type = "bitbucket" } end
maps["<leader>gop"]()
eq({ bitbucket_calls, lazy_calls, octo_calls }, { 1, 0, 0 })
forge.get = function() return { type = "github" } end
maps["<leader>gop"]()
eq({ bitbucket_calls, lazy_calls, octo_calls }, { 1, 1, 1 })
package.loaded.lazy, package.loaded["git.bitbucket"] = original_lazy, original_bitbucket
_G.octo_pr_picker = original_picker

local original_system = vim.system
local original_schedule = vim.schedule
local original_executable = vim.fn.executable
local original_notify = vim.notify
local original_input = vim.ui.input
local original_fzf = package.loaded["fzf-lua"]
local command = require("git.command")
local original_output = command.output
local calls, messages, picker, response = {}, {}, nil, nil
forge.get = function() return forge.parse("git@bitbucket.org:altitudeadsdev/k8s-infra.git") end
command.output = function() return true, "/tmp/k8s-infra" end
vim.fn.executable = function() return 1 end
vim.notify = function(message) table.insert(messages, message) end
vim.schedule = function(callback) callback() end
vim.system = function(argv, opts, callback)
	table.insert(calls, { argv = argv, opts = opts })
	callback(response or { code = 0, stdout = vim.json.encode({ pull_requests = {} }) })
end
package.loaded["fzf-lua"] = { fzf_exec = function(rows, opts) picker = { rows = rows, opts = opts } end }
local bitbucket = require("git.bitbucket")
bitbucket.open()
eq(picker.rows, { "+ Create pull request" })
eq(calls[1].argv, { "bkt", "pr", "list", "--state", "OPEN", "--json", "--workspace", "altitudeadsdev", "--repo", "k8s-infra" })
eq(calls[1].opts.cwd, "/tmp/k8s-infra")

vim.ui.input = function(_, callback) callback("A PR title") end
response = { code = 0, stdout = '{"id":42,"title":"A PR title","url":"https://bitbucket.org/example"}' }
picker.opts.actions["ctrl-o"]()
eq(calls[2].argv, { "bkt", "pr", "create", "--title", "A PR title", "--json", "--workspace", "altitudeadsdev", "--repo", "k8s-infra" })
eq(calls[3].argv, { "bkt", "pr", "view", "42", "--web", "--workspace", "altitudeadsdev", "--repo", "k8s-infra" })

response = { code = 0, stdout = vim.json.encode({ pull_requests = { { id = 7, title = "Existing PR" } } }) }
bitbucket.open()
eq(picker.rows, { "+ Create pull request", "#7 Existing PR" })
picker.opts.actions.default({ "#7 Existing PR" })
eq(calls[#calls].argv, { "bkt", "pr", "view", "7", "--web", "--workspace", "altitudeadsdev", "--repo", "k8s-infra" })

response = { code = 1, stderr = "no active context; run bkt auth login" }
local picker_before = picker
bitbucket.open()
eq(picker, picker_before)
assert(messages[#messages]:find("no active context", 1, true))
response = { code = 0, stdout = "invalid JSON" }
bitbucket.open()
assert(messages[#messages]:find("unexpected bkt JSON", 1, true))
vim.fn.executable = function() return 0 end
bitbucket.open()
assert(messages[#messages]:find("bkt is missing", 1, true))

forge.get = original_get
command.output = original_output
vim.system, vim.schedule, vim.fn.executable = original_system, original_schedule, original_executable
vim.notify, vim.ui.input, package.loaded["fzf-lua"] = original_notify, original_input, original_fzf
print("PASS Bitbucket PR routing and picker")

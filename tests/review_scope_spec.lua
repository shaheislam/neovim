package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local cwd = vim.fn.getcwd()
local root = vim.fn.tempname() .. " scope repo"
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local function git(...)
	local args = {
		"git",
		"-C",
		root,
		"-c",
		"user.name=Test",
		"-c",
		"user.email=test@example.test",
		"-c",
		"commit.gpgsign=false",
		"-c",
		"core.hooksPath=/dev/null",
	}
	vim.list_extend(args, { ... })
	local result = vim.system(args, { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
git("init", "-q")
vim.fn.writefile({ "base" }, root .. "/example.txt")
git("add", ".")
git("commit", "-qm", "base")
local base = git("rev-parse", "HEAD")
git("branch", "review-base")
vim.fn.writefile({ "next" }, root .. "/example.txt")
git("commit", "-qam", "next")
local head, branch = git("rev-parse", "HEAD"), git("branch", "--show-current")
local view = {
	adapter = { ctx = { toplevel = root } },
	left = { commit = base, type = 2 },
	right = { type = 1 },
	opencode_review = { provenance = { sessionID = "captured-agent" } },
}
package.loaded["diffview.lib"] = {
	get_current_view = function()
		return view
	end,
}
package.loaded["config.agent_session"] = {
	capture = function()
		return { sessionID = "live-agent" }
	end,
}
local started
package.loaded["config.opencode_review"] = {
	start = function(_, directory)
		started = directory
	end,
}
local commands, prompt, choice, input = {}, nil, 1, nil
local command = vim.cmd
vim.cmd = function(value)
	commands[#commands + 1] = value
end
vim.ui.select = function(items, opts, callback)
	prompt = opts.prompt
	callback(items[choice])
end
vim.ui.input = function(_, callback)
	callback(input)
end
vim.notify = function() end
local workflow = require("git.diffview_workflow")
workflow.scope()
assert(
	prompt:find(root, 1, true)
		and prompt:find(base, 1, true)
		and prompt:find("working tree", 1, true)
		and prompt:find("captured-agent", 1, true),
	"scope header names repo, revisions and captured agent"
)
local prefix = "DiffviewOpen -C" .. vim.fn.fnameescape(root)
assert(commands[1] == prefix, "uncommitted scope uses the selected review's repository")
choice = 2
workflow.scope()
assert(commands[2] == prefix .. " --staged", "staged scope preserves its existing comparison")
choice = 3
workflow.scope()
assert(
	commands[3] == "DiffviewOpen HEAD^! -C" .. vim.fn.fnameescape(root),
	"last commit uses the existing single-commit route"
)
choice, input = 4, "review-base"
workflow.scope()
assert(
	commands[4] == "DiffviewOpen " .. base .. "..HEAD -C" .. vim.fn.fnameescape(root),
	"branch scope uses the merge base without retargeting the active view"
)
assert(view.left.commit == base and view.right.type == 1, "scope leaves the pinned view unchanged")
input = "--help"
workflow.scope()
assert(#commands == 4, "invalid branch input cannot become an option or Ex command")
input = nil
workflow.scope()
choice = 99
workflow.scope()
assert(#commands == 4, "cancellation opens nothing")
choice = 5
workflow.scope()
assert(started == root, "agent scope reuses explicit pinned review")
assert(
	git("rev-parse", "HEAD") == head and git("branch", "--show-current") == branch,
	"scope selection never checks out another branch"
)
view = nil
vim.cmd = command
vim.cmd.cd(root)
vim.cmd = function(value)
	commands[#commands + 1] = value
end
choice = 1
workflow.scope()
assert(commands[5] == prefix, "scope also works from an ordinary repository buffer")
vim.cmd = command
vim.cmd.cd(cwd)
vim.fn.delete(root, "rf")
print("PASS additive review scopes, context header, cancellation and non-mutating branch comparison")

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

-- Minimal but behaviorally accurate fake ToggleTerm terminal: tracks window
-- open/closed state and counts calls so tests can assert exactly what the
-- module did (created vs. reused, opened vs. focused, toggled vs. left alone).
local function make_terminal(term)
	term.__window_open = false
	term.__open_calls = 0
	term.__focus_calls = 0
	term.__toggle_calls = 0

	function term:is_open()
		return self.__window_open == true
	end

	function term:open()
		self.__open_calls = self.__open_calls + 1
		self.__window_open = true
	end

	function term:focus()
		self.__focus_calls = self.__focus_calls + 1
	end

	function term:close()
		self.__window_open = false
	end

	function term:toggle()
		self.__toggle_calls = self.__toggle_calls + 1
		if self:is_open() then
			self:close()
		else
			self:open()
		end
	end

	return term
end

local created_terminals = {}
package.loaded["toggleterm.terminal"] = {
	Terminal = {
		new = function(_, term)
			local created = make_terminal(term)
			table.insert(created_terminals, created)
			return created
		end,
	},
}

package.loaded["oil"] = nil

local project_terminal = dofile("lua/config/project_terminal.lua")

local ORIGINAL_GETCWD = vim.fn.getcwd

local function reset(cwd, filetype)
	created_terminals = {}
	project_terminal.__reset()
	vim.fn.getcwd = function()
		return cwd or "/tmp/project-terminal-spec/project-a"
	end
	vim.bo.filetype = filetype or ""
end

-- ===== Section 1: open() creates and opens a fresh terminal =====

reset()
local term = project_terminal.open()
eq(#created_terminals, 1, "open() with no cached terminal creates exactly one terminal")
eq(term.__open_calls, 1, "open() on a freshly created terminal opens it once")
eq(term.__focus_calls, 0, "open() on a freshly created terminal does not focus (open() already made it current)")
eq(term:is_open(), true, "the terminal is open after open()")

print("PASS open() creates and opens a fresh terminal")

-- ===== Section 2: open() is idempotent - focuses instead of reopening =====

reset()
local first = project_terminal.open()
local second = project_terminal.open()
assert(first == second, "open() called twice for the same directory returns the same terminal")
eq(#created_terminals, 1, "open() twice does not create a second terminal")
eq(second.__open_calls, 1, "open() twice does not call term:open() a second time once already open")
eq(second.__focus_calls, 1, "open() on an already-open terminal focuses it instead of reopening")

print("PASS open() on an already-open terminal focuses rather than reopening")

-- ===== Section 3: open() reopens a terminal that was closed in between =====

reset()
local reopened = project_terminal.open()
reopened:close()
local reopened_again = project_terminal.open()
assert(reopened == reopened_again, "closing and reopening reuses the same cached terminal instance")
eq(reopened_again.__open_calls, 2, "open() reopens a terminal that is currently closed")
eq(reopened_again.__focus_calls, 0, "reopening a closed terminal does not also focus it")

print("PASS open() reopens a terminal that was closed")

-- ===== Section 4: toggle() preserves existing <leader>ft close/open behavior =====

reset()
local toggled = project_terminal.toggle()
eq(toggled.__toggle_calls, 1, "toggle() calls term:toggle() exactly once")
eq(toggled:is_open(), true, "toggle() opens a closed terminal")
project_terminal.toggle()
eq(toggled.__toggle_calls, 2, "toggle() again calls term:toggle() a second time")
eq(toggled:is_open(), false, "toggle() closes an open terminal")

print("PASS toggle() preserves toggle-open/toggle-close semantics")

-- ===== Section 5: directory change replaces the cached terminal =====

reset("/tmp/project-terminal-spec/project-a")
local term_a = project_terminal.toggle()
vim.fn.getcwd = function()
	return "/tmp/project-terminal-spec/project-b"
end
local term_b = project_terminal.toggle()
assert(term_a ~= term_b, "a directory change creates a new terminal instead of reusing the stale one")
eq(#created_terminals, 2, "a directory change results in exactly two created terminals")

print("PASS directory change creates a replacement terminal")

-- ===== Section 6: an explicit directory bypasses cwd/Oil resolution =====

reset("/tmp/project-terminal-spec/ignored-cwd")
local explicit_term = project_terminal.open("/tmp/project-terminal-spec/explicit-dir")
eq(explicit_term.dir, "/tmp/project-terminal-spec/explicit-dir", "an explicit dir argument is used verbatim")

print("PASS explicit dir argument bypasses cwd/Oil resolution")

-- ===== Section 7: Oil's current directory is preferred when in an Oil buffer =====

reset(nil, "oil")
package.loaded["oil"] = {
	get_current_dir = function()
		return "/tmp/project-terminal-spec/oil-dir"
	end,
}
local oil_term = project_terminal.toggle()
eq(oil_term.dir, "/tmp/project-terminal-spec/oil-dir", "toggle() in an Oil buffer uses Oil's current directory")
package.loaded["oil"] = nil

print("PASS Oil's current directory is preferred when resolving cwd")

vim.fn.getcwd = ORIGINAL_GETCWD

print("PASS project terminal lifecycle")

-- Same-Neovim OpenCode composer delivery.
--
-- config.opencode_http.append_prompt used to publish `tui.prompt.append` over
-- HTTP, which OpenCode's TUI broadcasts to every client attached to the same
-- project directory. With two tmux windows open on the same repo (each
-- running its own Neovim + nested OpenCode terminal), that meant a single
-- <leader>aoS/<leader>aos/picker append landed in both composers at once.
--
-- This module instead writes raw bytes directly into the OpenCode terminal
-- PTY owned by *this* Neovim process (registered via set_sink by
-- lua/plugins/opencode.lua), so delivery is scoped to one composer.

local M = {}

local sink

function M.set_sink(fn)
	sink = fn
end

local function notify(message, level, title)
	vim.notify(message, level or vim.log.levels.INFO, { title = title or "opencode" })
end

local function fail(text, opts, message)
	if opts.fallback_clipboard then
		vim.fn.setreg("+", text)
		if not opts.silent then
			notify((message or "Could not reach the OpenCode terminal") .. "; copied text instead", vim.log.levels.WARN, opts.title)
		end
		return
	end
	if not opts.silent then
		notify(message or "Could not reach the OpenCode terminal", vim.log.levels.ERROR, opts.title)
	end
end

-- opts.silent suppresses this module's own vim.notify/clipboard-fallback
-- side effects, for callers (e.g. the opencode.nvim Server patch below) that
-- already surface success/failure themselves through their own Promise
-- chains; without it they'd double-notify.
-- opts.notify_success = false suppresses only successful-delivery notices.
local function deliver(text, opts, submit, allow_empty)
	opts = opts or {}
	if type(text) ~= "string" or (text == "" and not allow_empty) then
		if not opts.silent then
			notify("No text to send", vim.log.levels.WARN, opts.title)
		end
		return
	end

	if not sink then
		fail(text, opts, "OpenCode terminal is not available")
		if opts.on_error then
			opts.on_error("OpenCode terminal is not available")
		end
		return
	end

	sink(text, {
		dir = opts.dir,
		submit = submit,
		on_success = function()
			if not opts.silent and opts.notify_success ~= false then
				notify(opts.success or "Sent text to OpenCode", vim.log.levels.INFO, opts.title)
			end
			if opts.on_success then
				opts.on_success()
			end
		end,
		on_failure = function(message)
			fail(text, opts, message)
			if opts.on_error then
				opts.on_error(message)
			end
		end,
	})
end

-- Appends text to the local composer without submitting it.
function M.append(text, opts)
	deliver(text, opts, false)
end

-- Appends text and submits it in a single write (one bracketed paste plus one \r).
function M.append_and_submit(text, opts)
	deliver(text, opts, true)
end

-- Submits whatever is already in the local composer (just Enter), with no
-- text of its own to append.
function M.submit(opts)
	deliver("", opts, true, true)
end

return M

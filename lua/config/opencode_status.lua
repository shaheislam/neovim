-- Event-driven bridge from opencode.nvim's shared-server SSE stream to tmux
-- window color, mirroring the color policy `scripts/opencode/tmux-open.sh`
-- and Claude's hooks already give direct OpenCode/Claude sessions in the
-- active dotfiles checkout.
--
-- Design constraints (see docs/opencode-nvim.md and dotfiles
-- .claude/rules/agent-window-status.md):
--   - The shared OpenCode server multiplexes events for every session, not
--     just this Neovim's embedded terminal, so every event is filtered
--     against config.opencode_handoff's exact bound sessions before it can
--     influence tmux. An event for an unrelated session/window must never
--     recolor this pane.
--   - Status is published per-*pane* (not per-window): this module writes
--     @opencode_owner/@opencode_status/@opencode_provider/@opencode_model/
--     @opencode_proof_pid/@opencode_updated_at directly via `tmux set-option
--     -p`, exactly like config.diffview_idle already does for its own pane
--     options. The actual window-color decision (aggregating every pane in
--     the window, respecting live Claude/Codex precedence) is centralized in
--     the dotfiles scripts/lib/agent-window.sh reconciler; this module never
--     duplicates that policy, it only reconciles its own window afterward on
--     a best-effort basis for snappy feedback (the dotfiles 10s heal loop is
--     the durable backstop if that shells out fails or the checkout is
--     missing).
--   - One Neovim process can have multiple bound projects sharing the same
--     tmux pane (opencode_terminal keeps one terminal per project). Their
--     statuses are aggregated locally: any exact busy/error wins; idle is
--     only published once every bound, live-proven project reports idle.
--     Anything unproven or unknown fails closed (clears rather than guesses).
--   - A session's status can arrive before its native bind completes; it is
--     cached by sessionID regardless, and reconsidered once
--     opencode_handoff signals a binding change.
--   - The shared server's connect/disconnect events are not session-specific
--     and never drive tmux color; disposal invalidates every cached status
--     so a reconnect cannot resurrect stale color before a fresh event.

local M = {}

local session_cache = {}
local seq_counter = 0
local server_connected = false

local function bump_seq()
	seq_counter = seq_counter + 1
	return seq_counter
end

local function normalize_status(status_type)
	if status_type == "idle" then
		return "idle"
	end
	if status_type == "error" then
		return "error"
	end
	if type(status_type) == "string" and status_type ~= "" then
		return "busy"
	end
	return nil
end

local function cache_status(session_id, status_type)
	if type(session_id) ~= "string" or session_id == "" then
		return
	end
	local normalized = normalize_status(status_type)
	if not normalized then
		return
	end
	local entry = session_cache[session_id] or {}
	entry.status = normalized
	entry.status_seq = bump_seq()
	session_cache[session_id] = entry
end

local function cache_model(session_id, provider_id, model_id)
	if type(session_id) ~= "string" or session_id == "" then
		return
	end
	local entry = session_cache[session_id] or {}
	entry.providerID = type(provider_id) == "string" and provider_id or entry.providerID
	entry.modelID = type(model_id) == "string" and model_id or entry.modelID
	session_cache[session_id] = entry
end

local function drop_session(session_id)
	if type(session_id) == "string" then
		session_cache[session_id] = nil
	end
end

local function tmux_pane()
	local pane = vim.env.TMUX_PANE
	if not pane or pane == "" or vim.fn.executable("tmux") ~= 1 then
		return nil
	end
	return pane
end

local function dotfiles_agent_window_helper()
	local root = vim.env.DOTFILES_ROOT
	if not root or root == "" then
		root = (vim.env.HOME or "") .. "/dotfiles"
	end
	local path = root .. "/scripts/lib/agent-window.sh"
	return vim.fn.filereadable(path) == 1 and path or nil
end

-- Best-effort, fire-and-forget: the durable backstop is the dotfiles 10s
-- heal loop, which reconciles every window from the same pane facts
-- regardless of whether this immediate reconcile ran or the checkout that
-- provides it is even present in this environment.
local function reconcile_window_async()
	local pane = tmux_pane()
	local helper = pane and dotfiles_agent_window_helper()
	if not helper then
		return
	end
	local window = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", pane, "#{window_id}" }))
	if window == "" then
		return
	end
	vim.fn.jobstart({
		"bash",
		"-c",
		". " .. vim.fn.shellescape(helper) .. "; agent_window_reconcile_opencode " .. vim.fn.shellescape(window),
	}, { detach = true })
end

local function owner_token()
	return "nvim:" .. tostring(vim.fn.getpid())
end

-- Every field is a separate `tmux set-option` chained with a literal `;`
-- token (tmux's own multi-command syntax) so the whole publish is one
-- process/message; @opencode_updated_at is set last as the commit marker,
-- matching agent_window_publish_pane_fact's ordering guarantee on the
-- dotfiles side.
local function publish_pane_fact_async(owner, status, provider, model, proof_pid, on_done)
	local pane = tmux_pane()
	if not pane then
		if on_done then
			on_done()
		end
		return
	end
	local updated_at = tostring(os.time() * 1000)
	vim.fn.jobstart({
		"tmux",
		"set-option",
		"-p",
		"-t",
		pane,
		"@opencode_owner",
		owner,
		";",
		"set-option",
		"-p",
		"-t",
		pane,
		"@opencode_status",
		status,
		";",
		"set-option",
		"-p",
		"-t",
		pane,
		"@opencode_provider",
		provider or "",
		";",
		"set-option",
		"-p",
		"-t",
		pane,
		"@opencode_model",
		model or "",
		";",
		"set-option",
		"-p",
		"-t",
		pane,
		"@opencode_proof_pid",
		tostring(proof_pid or ""),
		";",
		"set-option",
		"-p",
		"-t",
		pane,
		"@opencode_updated_at",
		updated_at,
	}, {
		detach = true,
		on_exit = function()
			reconcile_window_async()
			if on_done then
				on_done()
			end
		end,
	})
end

local function clear_pane_fact_async(on_done)
	local pane = tmux_pane()
	if not pane then
		if on_done then
			on_done()
		end
		return
	end
	vim.fn.jobstart({
		"tmux",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_owner",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_status",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_provider",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_model",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_proof_pid",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_updated_at",
	}, {
		detach = true,
		on_exit = function()
			reconcile_window_async()
			if on_done then
				on_done()
			end
		end,
	})
end

-- Synchronous: a detached VimLeavePre job is not guaranteed to run before
-- the process exits (same rationale as config.diffview_idle's
-- unregister_server), so the final clear on exit must block.
local function clear_pane_fact_sync()
	local pane = tmux_pane()
	if not pane then
		return
	end
	vim.fn.system({
		"tmux",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_owner",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_status",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_provider",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_model",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_proof_pid",
		";",
		"set-option",
		"-p",
		"-u",
		"-t",
		pane,
		"@opencode_updated_at",
	})
end

-- Aggregates every exact bound session in this Neovim process into a single
-- decision. Returns nil when nothing should be published (no bound project,
-- or at least one bound project's status/liveness could not be proven and
-- none is busy) so the caller clears instead of guessing.
function M._compute()
	local handoff_ok, handoff = pcall(require, "config.opencode_handoff")
	local terminal_ok, terminal = pcall(require, "config.opencode_terminal")
	if not handoff_ok or not terminal_ok then
		return nil
	end

	local bindings = handoff.active_bindings()
	local any_bound = false
	local all_idle = true
	local best_status = "none"
	local best_idle_seq = -1
	local best_provider, best_model, best_proof_pid

	for project, binding in pairs(bindings) do
		any_bound = true
		local cached = session_cache[binding.sessionID]
		local proof_pid = terminal.job_pid_for(project, binding.generation)

		if not cached or not cached.status or not proof_pid then
			all_idle = false
		elseif cached.status == "busy" or cached.status == "error" then
			best_status = "busy"
			all_idle = false
			best_proof_pid = best_proof_pid or proof_pid
		elseif cached.status == "idle" then
			if best_status ~= "busy" and (cached.status_seq or 0) > best_idle_seq then
				best_idle_seq = cached.status_seq or 0
				best_provider = cached.providerID
				best_model = cached.modelID
				best_proof_pid = proof_pid
			end
		end
	end

	if not any_bound then
		return nil
	end
	if best_status == "busy" then
		return { status = "busy", provider = best_provider, model = best_model, proof_pid = best_proof_pid }
	end
	if all_idle then
		return { status = "idle", provider = best_provider, model = best_model, proof_pid = best_proof_pid }
	end
	return nil
end

local function update_lualine(computed)
	if computed then
		vim.g.opencode_status = computed.status
	elseif server_connected then
		vim.g.opencode_status = "connected"
	else
		vim.g.opencode_status = nil
	end
end

-- Coalesces overlapping recompute requests into a single in-flight publish
-- job: a burst of SSE events (status then model, say) triggers only one
-- tmux round trip, and any request that arrives mid-publish is re-run once
-- the current one completes rather than racing it.
function M._recompute()
	if M._disabled then
		return
	end
	if M._recompute_inflight then
		M._recompute_pending = true
		return
	end
	M._recompute_inflight = true

	local computed = M._compute()
	update_lualine(computed)

	local function finish()
		M._recompute_inflight = false
		if M._recompute_pending then
			M._recompute_pending = false
			M._recompute()
		end
	end

	if computed then
		publish_pane_fact_async(owner_token(), computed.status, computed.provider, computed.model, computed.proof_pid, finish)
	else
		clear_pane_fact_async(finish)
	end
end

function M.refresh()
	M._recompute()
end

-- Disables the bridge and clears any published state — for
-- OPENCODE_TMUX_STATE_DISABLE=1 rollback without reverting the plugin wiring.
function M.disable()
	M._disabled = true
	session_cache = {}
	clear_pane_fact_sync()
	vim.g.opencode_status = nil
end

local function event_properties(event)
	local data = event.data
	local inner = type(data) == "table" and data.event or nil
	return type(inner) == "table" and inner.properties or nil
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	if vim.env.OPENCODE_TMUX_STATE_DISABLE == "1" then
		M._disabled = true
	end

	local group = vim.api.nvim_create_augroup("opencode_status_bridge", { clear = true })

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:session.status",
		desc = "Cache exact-session OpenCode status for tmux/lualine",
		callback = function(event)
			local props = event_properties(event)
			if type(props) ~= "table" then
				return
			end
			cache_status(props.sessionID, props.status and props.status.type)
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:message.updated",
		desc = "Cache exact-session OpenCode provider/model for tmux color",
		callback = function(event)
			local props = event_properties(event)
			local info = type(props) == "table" and props.info or nil
			if type(info) ~= "table" then
				return
			end
			cache_model(info.sessionID, info.providerID, info.modelID)
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:session.deleted",
		desc = "Drop cached status for a deleted OpenCode session",
		callback = function(event)
			local props = event_properties(event)
			local info = type(props) == "table" and props.info or nil
			if type(info) == "table" then
				drop_session(info.id)
			end
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:server.connected",
		desc = "Track shared OpenCode server connectivity (never colors tmux by itself)",
		callback = function()
			server_connected = true
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeEvent:server.instance.disposed",
		desc = "Invalidate cached status on disposal so a reconnect cannot resurrect stale color",
		callback = function()
			server_connected = false
			session_cache = {}
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "OpencodeHandoffEvent:binding_changed",
		desc = "Re-evaluate the published aggregate when a project's native binding changes",
		callback = function()
			M._recompute()
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Drain any in-flight publish, then synchronously clear this pane's OpenCode fact",
		callback = function()
			M._disabled = true
			vim.wait(200, function()
				return not M._recompute_inflight
			end, 10)
			clear_pane_fact_sync()
		end,
	})
end

-- Test-only: resets all cached/module state and the augroup between specs.
function M.__reset()
	session_cache = {}
	seq_counter = 0
	server_connected = false
	M._did_setup = nil
	M._disabled = nil
	M._recompute_inflight = nil
	M._recompute_pending = nil
	vim.g.opencode_status = nil
	pcall(vim.api.nvim_del_augroup_by_name, "opencode_status_bridge")
end

return M

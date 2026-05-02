-- sidekick.nvim - Copilot NES integration
-- OpenCode remains the canonical agent/runtime for context routing and chat.

local function sidekick_copilot_client()
  local ok, config = pcall(require, "sidekick.config")
  if not ok then
    return nil
  end
  return config.get_client(0)
end

local function open_nes_debug_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "lua"
  vim.bo[buf].swapfile = false

  vim.api.nvim_buf_set_name(buf, "Sidekick NES Debug " .. buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.cmd("botright 18split")
  vim.api.nvim_win_set_buf(0, buf)
end

local function debug_nes_raw_response()
  local bufnr = vim.api.nvim_get_current_buf()
  local client = sidekick_copilot_client()
  if not client then
    vim.notify("Sidekick NES debug: no Copilot LSP attached to this buffer", vim.log.levels.WARN)
    return
  end

  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.textDocument.version = vim.lsp.util.buf_versions[bufnr]
  params.context = { triggerKind = 2 }

  local requested_at = os.date("%Y-%m-%d %H:%M:%S")
  local ok, request_id = client:request("textDocument/copilotInlineEdit", params, function(err, res, ctx)
    vim.schedule(function()
      local edit_count = res and res.edits and #res.edits or 0
      local lines = {
        "-- Sidekick NES raw Copilot debug",
        "-- Requested at: " .. requested_at,
        "-- Completed at: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- Client: " .. client.name .. " (id " .. client.id .. ")",
        "-- Buffer: " .. vim.api.nvim_buf_get_name(bufnr),
        "-- Buffer version: " .. tostring(vim.lsp.util.buf_versions[bufnr]),
        "-- Cursor params:",
        vim.inspect(params.position),
        "",
        "-- Request context:",
        vim.inspect(ctx),
        "",
        "-- Error:",
        vim.inspect(err),
        "",
        "-- Raw edit count: " .. edit_count,
        "-- Raw response:",
        vim.inspect(res),
      }

      open_nes_debug_buffer(lines)
      vim.notify("Sidekick NES debug: raw edit count = " .. edit_count, vim.log.levels.INFO)
    end)
  end, bufnr)

  if not ok then
    vim.notify("Sidekick NES debug: request failed to start", vim.log.levels.ERROR)
    return
  end

  vim.notify("Sidekick NES debug request sent" .. (request_id and " (#" .. request_id .. ")" or ""), vim.log.levels.INFO)
end

local function request_nes()
  local client = sidekick_copilot_client()
  if not client then
    vim.notify("Sidekick NES: no Copilot LSP attached to this buffer", vim.log.levels.WARN)
    return
  end

  local nes = require("sidekick.nes")
  if nes.enabled then
    nes.update()
  else
    nes.enable(true)
  end
  vim.notify("Sidekick NES requested via " .. client.name, vim.log.levels.INFO)

  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(0) then
      return
    end

    if nes.have() then
      return
    end

    if nes._requests and nes._requests[client.id] then
      vim.notify("Sidekick NES: still waiting for Copilot response", vim.log.levels.INFO)
      return
    end

    vim.notify("Sidekick NES: Copilot returned no edit for this context", vim.log.levels.INFO)
  end, 4000)
end

local function jump_or_apply_nes()
  local nes = require("sidekick.nes")
  if require("sidekick").nes_jump_or_apply() then
    return
  end

  local client = sidekick_copilot_client()
  if not client then
    vim.notify("Sidekick NES: no Copilot LSP attached to this buffer", vim.log.levels.WARN)
  elseif nes._requests and nes._requests[client.id] then
    vim.notify("Sidekick NES: still waiting for Copilot response", vim.log.levels.INFO)
  else
    vim.notify("Sidekick NES: no active suggestion to jump/apply", vim.log.levels.INFO)
  end
end

local function clear_nes()
  local nes = require("sidekick.nes")
  local had_suggestion = nes.have()
  nes.clear()
  vim.notify(
    had_suggestion and "Sidekick NES suggestion cleared" or "Sidekick NES: no active suggestion to clear",
    vim.log.levels.INFO
  )
end

return {
  {
    "folke/sidekick.nvim",
    keys = {
      {
        "<leader>asj",
        jump_or_apply_nes,
        mode = { "n", "i" },
        desc = "Jump/Apply Next Edit Suggestion",
      },
      {
        "<leader>asu",
        request_nes,
        mode = "n",
        desc = "Update Next Edit Suggestion",
      },
      {
        "<leader>asd",
        debug_nes_raw_response,
        mode = "n",
        desc = "Debug NES Raw Response",
      },
      {
        "<leader>asx",
        clear_nes,
        mode = "n",
        desc = "Clear Next Edit Suggestion",
      },
    },
    init = function()
      vim.api.nvim_create_user_command("SidekickNesDebug", debug_nes_raw_response, {
        desc = "Request and display raw Copilot NES response",
      })
    end,
    opts = {
      nes = {
        enabled = true,
        trigger = {
          events = { "ModeChanged i:n", "TextChanged", "User SidekickNesDone" },
        },
        clear = {
          events = { "TextChangedI", "InsertEnter" },
          esc = true,
        },
      },
    },
  },
}

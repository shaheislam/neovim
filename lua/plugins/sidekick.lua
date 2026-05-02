-- sidekick.nvim - Copilot NES and in-editor AI CLI launcher
-- OpenCode remains the canonical agent runtime; Sidekick is for learning-oriented suggestions.

local function cli_send(msg)
  return function()
    require("sidekick.cli").send({ msg = msg })
  end
end

local function sidekick_copilot_client()
  local ok, config = pcall(require, "sidekick.config")
  if not ok then
    return nil
  end
  return config.get_client(0)
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

local function accept_ai_edit()
  if require("sidekick").nes_jump_or_apply() then
    return
  end

  if vim.lsp.inline_completion and vim.lsp.inline_completion.get() then
    return
  end

  vim.notify("No Sidekick NES or inline completion available", vim.log.levels.INFO)
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
        "<leader>asc",
        function() require("sidekick.cli").toggle({ name = "opencode", focus = true }) end,
        mode = { "n", "t" },
        desc = "Toggle Sidekick OpenCode",
      },
      {
        "<leader>ass",
        function() require("sidekick.cli").select() end,
        mode = { "n", "t" },
        desc = "Select Sidekick CLI",
      },
      {
        "<leader>asp",
        function() require("sidekick.cli").prompt() end,
        mode = { "n", "x" },
        desc = "Sidekick Prompt",
      },
      {
        "<leader>ast",
        cli_send("{this}"),
        mode = { "n", "x" },
        desc = "Send This to Sidekick",
      },
      {
        "<leader>asf",
        cli_send("{file}"),
        mode = "n",
        desc = "Send File to Sidekick",
      },
      {
        "<leader>asv",
        cli_send("{selection}"),
        mode = "x",
        desc = "Send Selection to Sidekick",
      },
      {
        "<leader>asj",
        jump_or_apply_nes,
        mode = { "n", "i" },
        desc = "Jump/Apply Next Edit Suggestion",
      },
      {
        "<M-e>",
        accept_ai_edit,
        mode = { "n", "i" },
        desc = "Accept AI Edit",
      },
      {
        "<leader>asu",
        request_nes,
        mode = "n",
        desc = "Update Next Edit Suggestion",
      },
      {
        "<leader>asx",
        clear_nes,
        mode = "n",
        desc = "Clear Next Edit Suggestion",
      },
    },
    opts = {
      nes = {
        enabled = false,
        trigger = {
          events = {},
        },
      },
      cli = {
        watch = true,
        tools = {
          opencode = {},
          claude = {},
          codex = {},
          gemini = {},
        },
        prompts = {
          explain = "Explain {this} like a mentor. Focus on intent, control flow, and what I should learn.",
          diagnostics = "Explain these diagnostics and teach me the underlying mistake:\n{diagnostics}",
          review = "Review {this} for correctness and readability. Do not edit files.",
          tests = "Suggest tests for {this}. Explain why each test matters before writing code.",
        },
      },
    },
  },
}

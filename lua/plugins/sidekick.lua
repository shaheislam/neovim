-- sidekick.nvim - Copilot NES and in-editor AI CLI launcher
-- OpenCode remains the canonical agent runtime; Sidekick is for learning-oriented suggestions.

local function cli_send(msg)
  return function()
    require("sidekick.cli").send({ msg = msg })
  end
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
        function() require("sidekick").nes_jump_or_apply() end,
        mode = { "n", "i" },
        desc = "Jump/Apply Next Edit Suggestion",
      },
      {
        "<leader>asu",
        function() require("sidekick.nes").update() end,
        mode = "n",
        desc = "Update Next Edit Suggestion",
      },
      {
        "<leader>asx",
        function() require("sidekick.nes").clear() end,
        mode = "n",
        desc = "Clear Next Edit Suggestion",
      },
    },
    opts = {
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

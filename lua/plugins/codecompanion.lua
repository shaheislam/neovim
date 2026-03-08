-- CodeCompanion.nvim - AI coding assistant
-- Multi-adapter: Ollama (fast/local), Anthropic (capable), Claude Code ACP (agentic)
-- Rules auto-load CLAUDE.md into every chat via the default preset

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
    keys = {
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Action Palette" },
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "Toggle Chat" },
      { "<leader>ai", "<cmd>CodeCompanion<cr>", mode = { "n", "v" }, desc = "Inline Assist" },
      { "<leader>ae", "<cmd>CodeCompanion /explain<cr>", mode = "v", desc = "Explain Selection" },
      { "<leader>af", "<cmd>CodeCompanion /fix<cr>", mode = "v", desc = "Fix Selection" },
      { "<leader>at", "<cmd>CodeCompanion /tests<cr>", mode = "v", desc = "Generate Tests" },
      { "<leader>ar", "<cmd>CodeCompanion /refactor<cr>", mode = "v", desc = "Refactor Selection" },
      { "<leader>ad", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "Add to Chat" },
      { "<leader>aA", "<cmd>CodeCompanionChat adapter=anthropic<cr>", mode = { "n", "v" }, desc = "Chat (Anthropic)" },
      { "<leader>aC", "<cmd>CodeCompanionChat adapter=claude_code<cr>", mode = { "n", "v" }, desc = "Chat (Claude Sub 1)" },
      { "<leader>aD", "<cmd>CodeCompanionChat adapter=claude_code_2<cr>", mode = { "n", "v" }, desc = "Chat (Claude Sub 2)" },
      { "<leader>aX", "<cmd>CodeCompanionChat adapter=codex<cr>", mode = { "n", "v" }, desc = "Chat (Codex)" },
      { "<leader>ag", "<cmd>CodeCompanion /commit<cr>", mode = "n", desc = "Generate Commit Msg" },
      { "<leader>al", "<cmd>CodeCompanion /lsp<cr>", mode = "n", desc = "Explain LSP Errors" },
    },
    opts = {
      adapters = {
        http = {
          ollama = function()
            return require("codecompanion.adapters").extend("ollama", {
              schema = {
                model = {
                  default = "qwen2.5-coder:7b",
                },
              },
            })
          end,
          anthropic = function()
            return require("codecompanion.adapters").extend("anthropic", {
              schema = {
                model = { default = "claude-sonnet-4-6" },
                extended_thinking = { default = false },
              },
            })
          end,
        },
        acp = {
          claude_code = function()
            return require("codecompanion.adapters").extend("claude_code", {
              env = {
                CLAUDE_CODE_OAUTH_TOKEN = "cmd:op read 'op://Private/CLAUDE_CODE_OAUTH_TOKEN/credential' --no-newline",
              },
            })
          end,
          claude_code_2 = function()
            return require("codecompanion.adapters").extend("claude_code", {
              env = {
                CLAUDE_CODE_OAUTH_TOKEN = "cmd:op read 'op://Private/CLAUDE_CODE_OAUTH_TOKEN_2/credential' --no-newline",
              },
            })
          end,
          codex = function()
            local adapter = require("codecompanion.adapters").extend("codex", {
              defaults = {
                auth_method = "chatgpt",
              },
            })
            adapter.env = {}
            return adapter
          end,
        },
      },
      interactions = {
        chat = { adapter = "ollama" },
        inline = { adapter = "ollama" },
        cmd = { adapter = "ollama" },
        background = { adapter = "ollama" },
      },
      prompt_library = {
        ["Refactor"] = {
          interaction = "chat",
          description = "Refactor the selected code for clarity and maintainability",
          opts = { alias = "refactor", is_slash_cmd = true, modes = { "v" } },
          prompts = {
            {
              role = "system",
              content = "You are an expert code refactoring assistant. Refactor the code to improve readability, reduce complexity, and follow best practices. Keep the same behavior.",
            },
            {
              role = "user",
              content = "Refactor this code for clarity and maintainability:\n\n#{selection}",
            },
          },
        },
      },
      display = {
        chat = {
          window = {
            layout = "vertical",
            width = 0.4,
          },
          show_settings = false,
          show_token_count = true,
          start_in_insert_mode = true,
        },
        diff = {
          enabled = true,
        },
      },
      opts = {
        log_level = "ERROR",
      },
    },
  },
}

-- CodeCompanion.nvim - AI coding assistant
-- Multi-adapter: Codex teacher chat, Ollama for cheap inline work, ACP agents for delivery
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
      { "<leader>aca", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Action Palette" },
      { "<leader>acc", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "Toggle Chat" },
      { "<leader>aci", "<cmd>CodeCompanion<cr>", mode = { "n", "v" }, desc = "Inline Assist" },
      { "<leader>acT", "<cmd>CodeCompanionChat adapter=codex model=gpt-5.4<cr>", mode = { "n", "v" }, desc = "Teacher Chat" },
      { "<leader>ace", "<cmd>CodeCompanion /explain<cr>", mode = "v", desc = "Explain Selection" },
      { "<leader>acS", "<cmd>CodeCompanion /simplify<cr>", mode = "v", desc = "Simplify Selection" },
      { "<leader>acL", "<cmd>CodeCompanion /linewise<cr>", mode = "v", desc = "Explain Line by Line" },
      { "<leader>acQ", "<cmd>CodeCompanion /quiz<cr>", mode = "v", desc = "Quiz Me on Selection" },
      { "<leader>acH", "<cmd>CodeCompanion /hints<cr>", mode = "v", desc = "Give Hints Only" },
      { "<leader>acf", "<cmd>CodeCompanion /fix<cr>", mode = "v", desc = "Fix Selection" },
      { "<leader>act", "<cmd>CodeCompanion /tests<cr>", mode = "v", desc = "Generate Tests" },
      { "<leader>acr", "<cmd>CodeCompanion /refactor<cr>", mode = "v", desc = "Refactor Selection" },
      { "<leader>acd", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "Add to Chat" },
      { "<leader>acA", "<cmd>CodeCompanionChat adapter=anthropic<cr>", mode = { "n", "v" }, desc = "Chat (Anthropic)" },
      { "<leader>acC", "<cmd>CodeCompanionChat adapter=claude_code<cr>", mode = { "n", "v" }, desc = "Chat (Claude Sub 1)" },
      { "<leader>acD", "<cmd>CodeCompanionChat adapter=claude_code_2<cr>", mode = { "n", "v" }, desc = "Chat (Claude Sub 2)" },
      { "<leader>acX", "<cmd>CodeCompanionChat adapter=codex<cr>", mode = { "n", "v" }, desc = "Chat (Codex)" },
      { "<leader>acg", "<cmd>CodeCompanion /commit<cr>", mode = "n", desc = "Generate Commit Msg" },
      { "<leader>acl", "<cmd>CodeCompanion /lsp<cr>", mode = "n", desc = "Explain LSP Errors" },
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
        chat = {
          adapter = {
            name = "codex",
            model = "gpt-5.4",
          },
        },
        inline = { adapter = "ollama" },
        cmd = { adapter = "ollama" },
        background = { adapter = "ollama" },
      },
      prompt_library = {
        ["Teach"] = {
          interaction = "chat",
          description = "Explain selected code like a patient teacher",
          opts = { alias = "teach", is_slash_cmd = true, modes = { "v" } },
          prompts = {
            {
              role = "system",
              content = "You are a senior engineer teaching another engineer. Prioritize understanding over speed. Explain intent, data flow, assumptions, and tradeoffs in clear language. Avoid rewriting code unless it helps the explanation.",
            },
            {
              role = "user",
              content = "Teach me this code. Start with a high-level explanation, then call out the tricky parts and assumptions. End with two follow-up questions I should ask next.\n\n#{selection}",
            },
          },
        },
        ["Simplify"] = {
          interaction = "chat",
          description = "Rewrite the explanation at a simpler level",
          opts = { alias = "simplify", is_slash_cmd = true, modes = { "v" } },
          prompts = {
            {
              role = "system",
              content = "You are a pragmatic programming tutor. Explain code in plain language and reduce jargon. Keep the explanation precise, but make it easy to follow.",
            },
            {
              role = "user",
              content = "Explain this code in simpler terms. Use short sections: what it does, how it works, why it was written this way, and one common mistake to avoid when editing it.\n\n#{selection}",
            },
          },
        },
        ["Linewise"] = {
          interaction = "chat",
          description = "Walk through the selected code line by line",
          opts = { alias = "linewise", is_slash_cmd = true, modes = { "v" } },
          prompts = {
            {
              role = "system",
              content = "You are a code reading coach. Walk through code in order, mapping each line or small block to its purpose. Keep the explanation anchored to the exact code instead of drifting into generic advice.",
            },
            {
              role = "user",
              content = "Walk through this selection line by line or block by block. For each part, explain what it is doing and how it connects to the surrounding logic.\n\n#{selection}",
            },
          },
        },
        ["Quiz Me"] = {
          interaction = "chat",
          description = "Turn the selection into a short teaching quiz",
          opts = { alias = "quiz", is_slash_cmd = true, modes = { "v" } },
          prompts = {
            {
              role = "system",
              content = "You are a programming tutor running an active recall exercise. Ask questions first. Do not reveal the answers until the learner asks for them. Make the questions specific to the code.",
            },
            {
              role = "user",
              content = "Quiz me on this code. Ask 3-5 short questions that test whether I really understand the control flow, assumptions, and failure modes. Do not give the answers yet.\n\n#{selection}",
            },
          },
        },
        ["Hints Only"] = {
          interaction = "chat",
          description = "Guide me without giving the full answer away",
          opts = { alias = "hints", is_slash_cmd = true, modes = { "v" } },
          prompts = {
            {
              role = "system",
              content = "You are a Socratic programming tutor. Give small hints, leading questions, and checkpoints. Do not provide the final answer or full rewrite unless the learner explicitly asks for it.",
            },
            {
              role = "user",
              content = "Help me understand or improve this code using hints only. Point me toward the next thing I should inspect, what invariant to verify, and what tradeoff I should think about.\n\n#{selection}",
            },
          },
        },
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

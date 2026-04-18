-- CodeCompanion.nvim - AI coding assistant
-- Multi-adapter: Codex teacher/router chat, Ollama for cheap inline work, ACP agents for delivery
-- Rules auto-load CLAUDE.md into every chat via the default preset

local function run_prompt(alias)
  return function()
    require("codecompanion").prompt(alias)
  end
end

local function routing_context(context)
  local scope = context.is_visual and "visual selection" or "current buffer"

  return string.format(
    [[Route this task using the current Neovim context.

Scope: %s
Filetype: %s
Lines: %d-%d

```%s
%s
```]],
    scope,
    context.filetype,
    context.start_line,
    context.end_line,
    context.filetype,
    context.code
  )
end

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
    keys = {
      { "<leader>aca", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Open Action Palette" },
      { "<leader>acc", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "Toggle Chat Buffer" },
      { "<leader>aci", "<cmd>CodeCompanion<cr>", mode = { "n", "v" }, desc = "Inline Assist" },
      { "<leader>acT", "<cmd>CodeCompanionChat adapter=codex model=gpt-5.4<cr>", mode = { "n", "v" }, desc = "Open Teacher Chat" },
      { "<leader>acP", run_prompt("plan_route"), mode = { "n", "v" }, desc = "Build Routing Brief" },
      { "<leader>acO", run_prompt("route_opencode"), mode = { "n", "v" }, desc = "Build Opencode Brief" },
      { "<leader>acR", run_prompt("route_claude"), mode = { "n", "v" }, desc = "Build Claude Brief" },
      { "<leader>ace", "<cmd>CodeCompanion /explain<cr>", mode = "v", desc = "Explain Selection" },
      { "<leader>acS", "<cmd>CodeCompanion /simplify<cr>", mode = "v", desc = "Simplify Explanation" },
      { "<leader>acL", "<cmd>CodeCompanion /linewise<cr>", mode = "v", desc = "Explain Line by Line" },
      { "<leader>acQ", "<cmd>CodeCompanion /quiz<cr>", mode = "v", desc = "Quiz Me on Code" },
      { "<leader>acH", "<cmd>CodeCompanion /hints<cr>", mode = "v", desc = "Hints Only" },
      { "<leader>acf", "<cmd>CodeCompanion /fix<cr>", mode = "v", desc = "Fix Selection" },
      { "<leader>act", "<cmd>CodeCompanion /tests<cr>", mode = "v", desc = "Generate Tests" },
      { "<leader>acr", "<cmd>CodeCompanion /refactor<cr>", mode = "v", desc = "Refactor Selection" },
      { "<leader>acd", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "Add to Chat" },
      { "<leader>acA", "<cmd>CodeCompanionChat adapter=anthropic<cr>", mode = { "n", "v" }, desc = "Open Anthropic Chat" },
      { "<leader>acC", "<cmd>CodeCompanionChat adapter=claude_code<cr>", mode = { "n", "v" }, desc = "Open Claude Chat 1" },
      { "<leader>acD", "<cmd>CodeCompanionChat adapter=claude_code_2<cr>", mode = { "n", "v" }, desc = "Open Claude Chat 2" },
      { "<leader>acX", "<cmd>CodeCompanionChat adapter=codex<cr>", mode = { "n", "v" }, desc = "Open Codex Chat" },
      { "<leader>acg", "<cmd>CodeCompanion /commit<cr>", mode = "n", desc = "Draft Commit Message" },
      { "<leader>acl", "<cmd>CodeCompanion /lsp<cr>", mode = "n", desc = "Explain LSP Diagnostics" },
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
        ["Plan and Route"] = {
          interaction = "chat",
          description = "Decide the right mode, tool, and next step for the current task",
          opts = {
            alias = "plan_route",
            is_slash_cmd = true,
            is_workflow = true,
            modes = { "n", "v" },
            stop_context_insertion = true,
          },
          prompts = {
            {
              {
                role = "system",
                content = "You are an AI workflow router inside Neovim. Your job is to decide whether the current task belongs in learning, investigation, bounded execution, or a larger delivery loop. Prefer the smallest effective tool and keep the handoff concrete.",
              },
              {
                role = "user",
                content = routing_context,
              },
            },
            {
              {
                role = "user",
                opts = { auto_submit = true },
                content = "Now produce a final routing brief with exactly these sections: Mode, Primary Tool, Why, Scope Boundary, Recommended Context, Validation, First Step. Recommend one of: CodeCompanion, agentic.nvim, opencode.nvim, claude-code.nvim.",
              },
            },
          },
        },
        ["Route to Opencode"] = {
          interaction = "chat",
          description = "Turn the current code context into a bounded opencode execution brief",
          opts = {
            alias = "route_opencode",
            is_slash_cmd = true,
            is_workflow = true,
            modes = { "n", "v" },
            stop_context_insertion = true,
          },
          prompts = {
            {
              {
                role = "system",
                content = "You are preparing a bounded execution handoff for opencode.nvim. Keep scope tight, prefer explicit editor-native context packs, and avoid broad autonomous plans.",
              },
              {
                role = "user",
                content = routing_context,
              },
            },
            {
              {
                role = "user",
                opts = { auto_submit = true },
                content = "Convert that into an opencode handoff brief with exactly these sections: Goal, Why Now, File Scope, Best Context Pack, Suggested Prompt, Constraints, Validation. In Best Context Pack, recommend from @this, @buffer, @visible, @quickfix, @diff, @diagnostics. In Suggested Prompt, write a short opencode-ready prompt.",
              },
            },
          },
        },
        ["Route to Claude Code"] = {
          interaction = "chat",
          description = "Turn the current code context into a larger claude-code delivery brief",
          opts = {
            alias = "route_claude",
            is_slash_cmd = true,
            is_workflow = true,
            modes = { "n", "v" },
            stop_context_insertion = true,
          },
          prompts = {
            {
              {
                role = "system",
                content = "You are preparing a delivery brief for claude-code.nvim. Assume the task may span multiple files and needs a stronger plan, but keep the handoff grounded in the current code context and acceptance criteria.",
              },
              {
                role = "user",
                content = routing_context,
              },
            },
            {
              {
                role = "user",
                opts = { auto_submit = true },
                content = "Convert that into a claude-code delivery brief with exactly these sections: Goal, Likely Scope, Risks, Required Context, Acceptance Criteria, Validation, Suggested Handoff Prompt. The handoff prompt should be concise and execution-ready.",
              },
            },
          },
        },
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

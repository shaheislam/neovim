-- nvim-lint configuration
-- Integrates external linters (helm lint, actionlint, kube-linter, tfsec)
-- alongside LSP diagnostics

return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    -- Configure linters by filetype
    lint.linters_by_ft = {
      -- DevOps linters (on-save)
      helm = { "helm" },
      ["yaml.github"] = { "actionlint" },
      terraform = { "tfsec" },

      -- Semgrep for code security (disabled - nvim-lint has no built-in semgrep support)
      -- Run semgrep manually via CLI: semgrep --config auto .
      -- python = { "semgrep" },
      -- javascript = { "semgrep" },
      -- typescript = { "semgrep" },
      -- javascriptreact = { "semgrep" },
      -- typescriptreact = { "semgrep" },
      -- go = { "semgrep" },
      -- ruby = { "semgrep" },
      -- java = { "semgrep" },
      -- c = { "semgrep" },
      -- cpp = { "semgrep" },
      -- rust = { "semgrep" },

      -- Kubernetes best practices (manual trigger recommended - overlaps with yamlls)
      -- kubernetes = { "kube_linter" },
    }

    -- Lint on save
    vim.api.nvim_create_autocmd({ "BufWritePost" }, {
      group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
      callback = function()
        lint.try_lint()
      end,
    })

    -- Keybindings for fast linters
    vim.keymap.set("n", "<leader>cL", function()
      lint.try_lint()
    end, { desc = "Trigger linting" })

    -- Manual kube-linter trigger (since it overlaps with yamlls schema validation)
    vim.keymap.set("n", "<leader>ck", function()
      lint.try_lint({ "kube_linter" })
    end, { desc = "Run kube-linter" })

    -- Keybindings for directory/project scanners (manual only)
    vim.keymap.set("n", "<leader>cT", function()
      vim.cmd("!trivy config " .. vim.fn.expand("%:p:h"))
    end, { desc = "Run Trivy on directory" })

    vim.keymap.set("n", "<leader>cP", function()
      vim.cmd("!conftest test " .. vim.fn.expand("%"))
    end, { desc = "Run Conftest on file" })
  end,
}

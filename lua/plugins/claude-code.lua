return {
  {
    "greggh/claude-code.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    cmd = {
      "ClaudeCode",
      "ClaudeCodeContinue",
      "ClaudeCodeResume",
      "ClaudeCodeVerbose",
    },
    keys = {
      { "<leader>aCc", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
      { "<leader>aCC", "<cmd>ClaudeCodeContinue<cr>", desc = "Continue Claude Code" },
      { "<leader>aCR", "<cmd>ClaudeCodeResume<cr>", desc = "Resume Claude Code" },
      { "<leader>aCV", "<cmd>ClaudeCodeVerbose<cr>", desc = "Verbose Claude Code" },
    },
    opts = {
      window = {
        position = "float",
        enter_insert = true,
        float = {
          width = "90%",
          height = "85%",
          row = "center",
          col = "center",
          relative = "editor",
          border = "rounded",
        },
      },
      refresh = {
        enable = false,
      },
      git = {
        use_git_root = true,
      },
      command = "claude",
      keymaps = {
        toggle = {
          normal = false,
          terminal = false,
          variants = {
            continue = false,
            verbose = false,
          },
        },
        window_navigation = true,
        scrolling = true,
      },
    },
    config = function(_, opts)
      require("claude-code").setup(opts)
    end,
  },
}

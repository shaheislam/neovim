return {
  {
    "chipsenkbeil/distant.nvim",
    branch = "v0.3",  -- v0.3 branch is compatible with distant 0.20.x
    lazy = false,     -- Load immediately for proper initialization
    config = function()
      -- Setup with proper configuration for distant 0.20.x
      local ok, distant = pcall(require, "distant")
      if not ok then
        vim.notify("Failed to load distant.nvim", vim.log.levels.ERROR)
        return
      end

      -- Configure with settings for v0.20 compatibility
      distant:setup({
        -- Use the binary we have installed
        bin = vim.fn.expand("~/.local/share/nvim/distant/distant.bin"),
      })
    end,
    cmd = {
      "DistantInstall",
      "DistantConnect",
      "DistantOpen",
      "DistantShell",
      "DistantSearch",
      "DistantSessionInfo",
      "DistantLaunch",
      "DistantCopy",
      "DistantRename",
      "DistantRemove",
      "DistantMkdir",
    },
    -- Key mappings
    keys = {
      { "<leader>dc", "<cmd>DistantConnect<cr>", desc = "Connect to remote server" },
      { "<leader>do", "<cmd>DistantOpen<cr>", desc = "Open remote file/directory" },
      { "<leader>ds", "<cmd>DistantShell<cr>", desc = "Open remote shell" },
      { "<leader>dS", "<cmd>DistantSearch<cr>", desc = "Search remote files" },
      { "<leader>di", "<cmd>DistantSessionInfo<cr>", desc = "Show session info" },
    },
  },
}

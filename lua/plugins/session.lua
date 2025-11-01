-- Session management with nvim-possession
-- Provides seamless session save/restore with fzf-lua integration
return {
  {
    "gennaro-tedesco/nvim-possession",
    dependencies = { "ibhagwan/fzf-lua" },
    cmd = { "PossessionList", "PossessionNew", "PossessionUpdate", "PossessionDelete" },

    opts = {
      sessions = {
        sessions_path = vim.fn.stdpath("data") .. "/sessions/",
        sessions_icon = "📌 ",
        sessions_prompt = "Sessions> ",
      },

      -- Enable autosave but disable autoload for explicit control
      autoload = false,  -- Don't auto-load on startup (can be changed to true)
      autosave = true,   -- Save session before quitting

      autoswitch = {
        enable = true,   -- Clean up previous session buffers when switching
        exclude_ft = {   -- Don't close these buffer types
          "oil",
          "toggleterm",
          "qf",
          "help",
        },
      },

      -- Save hook to exclude unwanted buffers from sessions
      save_hook = function()
        -- Close floating windows and popups before saving
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local config = vim.api.nvim_win_get_config(win)
          if config.relative ~= "" then  -- Floating window
            vim.api.nvim_win_close(win, false)
          end
        end

        -- Close Oil buffers (file manager) - they'll reopen on demand
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(buf) then
            local ft = vim.api.nvim_buf_get_option(buf, "filetype")
            if ft == "oil" then
              vim.api.nvim_buf_delete(buf, { force = true })
            end
          end
        end
      end,

      -- Post-load hook for custom restoration logic
      post_hook = nil,

      -- FZF window customization to match your existing setup
      fzf_winopts = {
        height = 0.5,
        width = 0.7,
        border = "rounded",
      },
    },

    config = function(_, opts)
      require("nvim-possession").setup(opts)

      -- Ensure sessionoptions includes current directory
      vim.opt.sessionoptions:append("curdir")

      -- Optional: Create sessions directory if it doesn't exist
      local sessions_dir = opts.sessions.sessions_path
      if vim.fn.isdirectory(sessions_dir) == 0 then
        vim.fn.mkdir(sessions_dir, "p")
      end
    end,

    keys = {
      -- Session management under <leader>s
      {
        "<leader>sl",
        function() require("nvim-possession").list() end,
        desc = "List Sessions"
      },
      {
        "<leader>sn",
        function() require("nvim-possession").new() end,
        desc = "New Session"
      },
      {
        "<leader>su",
        function() require("nvim-possession").update() end,
        desc = "Update Session"
      },
      {
        "<leader>sd",
        function() require("nvim-possession").delete() end,
        desc = "Delete Session"
      },
    },
  },
}
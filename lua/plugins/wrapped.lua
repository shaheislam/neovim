-- wrapped.nvim - Neovim configuration analytics dashboard
-- Displays contribution heatmaps, plugin stats, and file metrics for this config

return {
  {
    "aikhe/wrapped.nvim",
    cmd = "WrappedNvim",
    dependencies = { "nvzone/volt" },
    keys = {
      {
        "<leader>aw",
        function()
          vim.cmd("WrappedNvim")
        end,
        desc = "Open Wrapped dashboard",
      },
    },
    config = function()
      local width = math.floor(vim.o.columns * 0.75)
      local height = math.floor(vim.o.lines * 0.75)
      require("wrapped").setup({
        path = vim.env.NVIM_WRAPPED_PATH or vim.fn.stdpath("config"),
        border = "rounded",
        size = {
          width = math.max(90, width),
          height = math.max(30, height),
        },
        exclude_filetype = {
          ".gitmodules",
          "lazy-lock.json",
        },
        cap = {
          commits = 2000,
          plugins = 200,
          plugins_ever = 400,
          lines = 40000,
        },
        keys = {
          close = "q",
          refresh = "r",
          prev_year = "<",
          next_year = ">",
        },
      })
    end,
  },
}

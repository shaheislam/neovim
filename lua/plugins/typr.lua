-- Typr - Typing practice game for Neovim
-- Interactive typing speed practice within the editor

return {
  {
    "nvzone/typr",
    dependencies = "nvzone/volt",  -- Required UI framework dependency
    cmd = { "Typr", "TyprStats" },
    keys = {
      { "<leader>ty", "<cmd>Typr<cr>", desc = "Open Typr (typing practice)" },
      { "<leader>tY", "<cmd>TyprStats<cr>", desc = "Typr Statistics" },
    },
    opts = {},
    config = function(_, opts)
      -- Ensure typr buffer is properly deleted when window closes
      -- This prevents orphaned buffers from accumulating
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "typr",
        callback = function(event)
          -- Create a buffer-specific autocmd that fires when the window closes
          vim.api.nvim_create_autocmd("WinClosed", {
            buffer = event.buf,
            once = true,  -- Only fire once per buffer
            callback = function()
              -- Schedule deletion to avoid conflicts with window closing
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(event.buf) then
                  vim.api.nvim_buf_delete(event.buf, { force = true })
                end
              end)
            end,
            desc = "Delete typr buffer when window closes",
          })
        end,
        desc = "Setup typr buffer cleanup on window close",
      })
    end,
  },
}

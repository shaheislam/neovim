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
    opts = {
      on_attach = function(buf)
        -- Workaround for volt plugin bug where state is cleared before WinClosed autocmd
        -- This causes the dim window to not close on first Esc
        vim.keymap.set("n", "<Esc>", function()
          -- Get all current windows before any are closed
          local wins = vim.api.nvim_list_wins()

          -- Trigger normal typr close (press 'q')
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "n", false)

          -- After a brief delay, force close any remaining floating windows
          vim.schedule(function()
            for _, win in ipairs(wins) do
              if vim.api.nvim_win_is_valid(win) then
                local config = vim.api.nvim_win_get_config(win)
                if config.relative ~= "" then  -- Is a floating window
                  pcall(vim.api.nvim_win_close, win, true)
                end
              end
            end
          end)
        end, { buffer = buf, desc = "Close Typr and cleanup floating windows" })
      end,
    },
  },
}

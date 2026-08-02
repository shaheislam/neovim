-- vim-tmux-navigator: seamless navigation between vim splits and tmux panes
-- Use Ctrl-h/j/k/l to navigate in both Neovim and tmux without prefix
return {
  "christoomey/vim-tmux-navigator",
  lazy = false,
  -- The plugin's own bundled default mappings use a Vim-only <C-w> terminal
  -- escape that Neovim doesn't special-case in terminal-job mode, so <C-h>
  -- leaks raw keystrokes (including the literal ":TmuxNavigateLeft" text)
  -- into whatever job is running in the terminal. Disable them and rely
  -- solely on the Neovim-native mappings below.
  init = function()
    vim.g.tmux_navigator_no_mappings = 1

    local group = vim.api.nvim_create_augroup("nvim_mini_terminal_navigation", { clear = true })
    vim.api.nvim_create_autocmd("WinLeave", {
      group = group,
      desc = "Remember terminal-job mode before window navigation",
      callback = function(event)
        if vim.api.nvim_get_current_buf() ~= event.buf then
          return
        end

        if vim.bo[event.buf].buftype == "terminal" and vim.fn.mode() == "t" then
          vim.w.nvim_mini_terminal_navigation_buf = event.buf
        else
          vim.w.nvim_mini_terminal_navigation_buf = nil
        end
      end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
      group = group,
      desc = "Resume terminal-job mode after window navigation",
      callback = function(event)
        local resume_buf = vim.w.nvim_mini_terminal_navigation_buf
        if resume_buf == nil then
          return
        end

        vim.w.nvim_mini_terminal_navigation_buf = nil
        if
          resume_buf == event.buf
          and vim.api.nvim_get_current_buf() == event.buf
          and vim.bo[event.buf].buftype == "terminal"
        then
          vim.cmd("startinsert")
        end
      end,
    })
  end,
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    -- Normal mode
    { "<c-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate left (vim/tmux)" },
    { "<c-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate down (vim/tmux)" },
    { "<c-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate up (vim/tmux)" },
    { "<c-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (vim/tmux)" },
    { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Navigate to previous (vim/tmux)" },
    -- <Cmd> executes without sending command text to the terminal job.
    { "<c-h>", "<cmd>TmuxNavigateLeft<cr>", mode = "t", desc = "Navigate left (vim/tmux)" },
    { "<c-j>", "<cmd>TmuxNavigateDown<cr>", mode = "t", desc = "Navigate down (vim/tmux)" },
    { "<c-k>", "<cmd>TmuxNavigateUp<cr>", mode = "t", desc = "Navigate up (vim/tmux)" },
    { "<c-l>", "<cmd>TmuxNavigateRight<cr>", mode = "t", desc = "Navigate right (vim/tmux)" },
    { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", mode = "t", desc = "Navigate to previous (vim/tmux)" },
  },
}

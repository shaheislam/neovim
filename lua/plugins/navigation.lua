-- vim-tmux-navigator: seamless navigation between vim splits and tmux panes
-- Use Ctrl-h/j/k/l to navigate in both Neovim and tmux without prefix
return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<c-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate left (vim/tmux)" },
    { "<c-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate down (vim/tmux)" },
    { "<c-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate up (vim/tmux)" },
    { "<c-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (vim/tmux)" },
    { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Navigate to previous (vim/tmux)" },
  },
}

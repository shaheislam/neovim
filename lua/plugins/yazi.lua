-- Yazi file manager integration
-- https://github.com/mikavilpas/yazi.nvim
return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>-",
      "<cmd>Yazi<cr>",
      desc = "Open yazi at file",
    },
    {
      "<leader>cw",
      "<cmd>Yazi cwd<cr>",
      desc = "Open yazi in cwd",
    },
    {
      "<leader>cr",
      "<cmd>Yazi toggle<cr>",
      desc = "Resume last yazi session",
    },
  },
  opts = {
    -- Open yazi instead of netrw for directories
    open_for_directories = true,

    -- Keymaps in yazi (when hovering over files)
    keymaps = {
      show_help = "<f1>",
      open_file_in_vertical_split = "<c-v>",
      open_file_in_horizontal_split = "<c-x>",
      open_file_in_tab = "<c-t>",
      grep_in_directory = "<c-s>",
      replace_in_directory = "<c-g>",
      cycle_open_buffers = "<tab>",
      copy_relative_path_to_selected_files = "<c-y>",
      send_to_quickfix_list = "<c-q>",
    },
  },
}

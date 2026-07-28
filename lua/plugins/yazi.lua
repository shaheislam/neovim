-- Yazi file manager integration
-- https://github.com/mikavilpas/yazi.nvim
return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  -- Upstream vendors yazi-rs/plugins as the yazi-plugin/yazi-plugins submodule,
  -- used only by its own yazi-side plugin tests. Recursing into it makes
  -- `git checkout --recurse-submodules` abort ("could not reset submodule
  -- index"), which updates the worktree but leaves HEAD pinned, so every update
  -- reports ~34 phantom local changes. Nothing under lua/ references it.
  submodules = false,
  init = function()
    -- Suppress "Invalid buffer id" errors from yazi's netrw hijacking race condition
    local original_buf_delete = vim.api.nvim_buf_delete
    vim.api.nvim_buf_delete = function(buf, opts)
      if vim.api.nvim_buf_is_valid(buf) then
        return original_buf_delete(buf, opts)
      end
    end
  end,
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

-- img-clip.nvim - Paste images from clipboard
-- Saves images and inserts markdown links

return {
  "HakonHarnes/img-clip.nvim",
  event = "VeryLazy",
  opts = {
    -- Default options
    default = {
      -- Directory to save images (relative to file)
      dir_path = "assets/imgs",

      -- File naming
      file_name = "%Y-%m-%d-%H-%M-%S",

      -- Insert as markdown image link
      use_absolute_path = false,
      relative_to_current_file = true,

      -- Prompt for filename
      prompt_for_file_name = true,
      show_dir_path_in_prompt = true,

      -- Drag and drop support
      drag_and_drop = {
        enabled = true,
        insert_mode = true,
      },
    },

    -- Filetype-specific options
    filetypes = {
      markdown = {
        -- Use Obsidian-compatible format
        template = "![$CURSOR]($FILE_PATH)",
      },
    },
  },

  keys = {
    { "<leader>op", "<cmd>PasteImage<cr>", desc = "Paste image" },
  },
}

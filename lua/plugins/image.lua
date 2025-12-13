-- image.nvim - Display images inline in terminal
-- WezTerm supports the kitty graphics protocol

return {
  "3rd/image.nvim",
  ft = { "markdown" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    backend = "kitty", -- WezTerm supports kitty protocol

    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = true,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        filetypes = { "markdown" },
      },
    },

    -- Max dimensions
    max_width = nil, -- Auto based on window
    max_height = nil, -- Auto based on window
    max_width_window_percentage = 50,
    max_height_window_percentage = 50,

    -- Window margin
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },

    -- Editor options
    editor_only_render_when_focused = false,
    tmux_show_only_in_active_window = true,

    -- Hijack file associations
    hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
  },

  keys = {
    {
      "<leader>mi",
      function()
        require("image").clear_all()
      end,
      desc = "Clear images",
    },
  },
}

-- image.nvim - Display images inline in terminal
-- WezTerm supports the kitty graphics protocol (though not fully compliant)

return {
  "3rd/image.nvim",
  ft = { "markdown" },
  -- Kitty graphics replies can leak through tmux/WezTerm as shell input
  -- (for example: Gi=31337;OKl), so keep inline images outside tmux only.
  enabled = function()
    return vim.env.TMUX == nil
  end,
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    backend = "kitty", -- WezTerm supports kitty protocol
    processor = "magick_cli", -- Uses ImageMagick CLI (convert command)

    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = true,
        download_remote_images = false,
        only_render_image_at_cursor = true,
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

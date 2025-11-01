-- Markdown Preview
-- Live preview markdown files in browser
return {
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && yarn install",
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview" },
    },
    config = function()
      -- Configuration options
      vim.g.mkdp_auto_start = 0  -- Don't auto-start preview
      vim.g.mkdp_auto_close = 1  -- Auto-close preview when leaving markdown buffer
      vim.g.mkdp_refresh_slow = 0 -- Refresh on save or leaving insert mode
      vim.g.mkdp_theme = 'dark'   -- Match neovim-mini theme preference

      -- Browser settings (optional - uses system default if not set)
      -- vim.g.mkdp_browser = ''

      -- Preview options
      vim.g.mkdp_preview_options = {
        mkit = {},
        katex = {},
        uml = {},
        maid = {},
        disable_sync_scroll = 0,
        sync_scroll_type = 'middle',
        hide_yaml_meta = 1,
        sequence_diagrams = {},
        flowchart_diagrams = {},
        content_editable = false,
        disable_filename = 0,
        toc = {}
      }
    end,
  },
}
-- Tree-sitter for better syntax highlighting
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false, -- Load immediately so highlight groups exist for styling autocmd
    opts = {
      ensure_installed = {
        "lua", "vim", "vimdoc", "query",
        "bash", "fish",
        "python", "javascript", "typescript",
        "json", "yaml", "toml",
        "markdown", "markdown_inline",
      },
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      indent = {
        enable = true,
      },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}

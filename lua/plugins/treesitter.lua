-- Tree-sitter for better syntax highlighting

-- In devcontainers, use a local directory for parser installation
-- to avoid permission issues with bind-mounted volumes (utime errors)
local parser_install_dir = nil
if vim.env.DEVCONTAINER then
  parser_install_dir = "/tmp/nvim-treesitter-parsers"
  vim.fn.mkdir(parser_install_dir .. "/parser", "p")
  vim.opt.runtimepath:append(parser_install_dir)
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua", "vim", "vimdoc", "query",
          "bash", "fish",
          "python", "javascript", "typescript",
          "json", "yaml", "toml",
          "markdown", "markdown_inline",
          "typst",
        },
        highlight = { enable = true },
        indent = { enable = true },
        parser_install_dir = parser_install_dir,
      })
    end,
  },
}

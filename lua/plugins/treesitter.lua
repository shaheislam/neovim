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
      -- New nvim-treesitter API: config.setup() only accepts install_dir
      -- Highlighting and indentation are now built into Neovim
      if parser_install_dir then
        require("nvim-treesitter.config").setup({
          install_dir = parser_install_dir,
        })
      end

      -- ensure_installed is now handled via install API
      local parsers = {
        "lua", "vim", "vimdoc", "query",
        "bash", "fish",
        "python", "javascript", "typescript",
        "json", "yaml", "toml",
        "markdown", "markdown_inline",
        "typst",
      }

      -- Install missing parsers (non-blocking)
      local installed = require("nvim-treesitter.config").get_installed()
      local installed_set = {}
      for _, p in ipairs(installed) do
        installed_set[p] = true
      end
      local missing = vim.tbl_filter(function(p)
        return not installed_set[p]
      end, parsers)
      if #missing > 0 then
        require("nvim-treesitter.install").install(missing)
      end
    end,
  },
}

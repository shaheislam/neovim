-- Tree-sitter for better syntax highlighting
-- nvim-treesitter 1.0 API - highlighting/indent are now Neovim core features

-- In devcontainers, use a local directory for parser installation
-- to avoid permission issues with bind-mounted volumes (utime errors)
local install_dir = nil
if vim.env.DEVCONTAINER then
  install_dir = "/tmp/nvim-treesitter-parsers"
  vim.fn.mkdir(install_dir .. "/parser", "p")
  vim.opt.runtimepath:append(install_dir)
end

-- Parsers to auto-install on first load
local ensure_parsers = {
  "lua", "vim", "vimdoc", "query",
  "bash", "fish",
  "python", "javascript", "typescript",
  "json", "yaml", "toml",
  "markdown", "markdown_inline",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      -- Configure install directory (only option in 1.0 API)
      require("nvim-treesitter").setup({
        install_dir = install_dir,
      })

      -- Auto-install missing parsers
      local installed = require("nvim-treesitter.config").get_installed()
      local to_install = vim.tbl_filter(function(parser)
        return not vim.tbl_contains(installed, parser)
      end, ensure_parsers)

      if #to_install > 0 then
        vim.cmd("TSInstall " .. table.concat(to_install, " "))
      end
    end,
  },
}

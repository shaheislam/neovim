-- Typst support for Neovim
-- Modern typesetting system (LaTeX alternative)
-- Usage: Edit .typ files, :TypstWatch for live preview

return {
  "kaarmu/typst.vim",
  ft = "typst",
  config = function()
    -- Use macOS 'open' command to view PDFs
    vim.g.typst_pdf_viewer = "open"

    -- Enable conceal for prettier editing (optional)
    vim.g.typst_conceal = 1

    -- Auto-compile on save (optional - can use :TypstWatch instead)
    vim.g.typst_auto_compile = 0
  end,
  keys = {
    { "<leader>tw", "<cmd>TypstWatch<cr>", desc = "Typst: Watch & Preview", ft = "typst" },
    { "<leader>tc", function()
      -- Find the root directory (parent of 2025/, 2026/, etc.)
      local file = vim.fn.expand("%:p")
      local root = vim.fn.fnamemodify(file, ":h:h")
      vim.cmd("!typst compile --root " .. root .. " " .. file)
    end, desc = "Typst: Compile", ft = "typst" },
    { "<leader>to", function()
      local pdf = vim.fn.expand("%:r") .. ".pdf"
      vim.fn.system({ "open", pdf })
    end, desc = "Typst: Open PDF", ft = "typst" },
  },
}

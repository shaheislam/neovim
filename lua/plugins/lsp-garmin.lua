-- Garmin Connect IQ Filetype Detection
-- Lets the official SDK Monkey C language server attach to Connect IQ projects.

return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.filetype.add({
        extension = {
          mc = "monkeyc",
          mcgen = "monkeyc",
          jungle = "jungle",
          mss = "mss",
        },
      })
    end,
  },
}

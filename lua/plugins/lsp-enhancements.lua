-- LSP Enhancements
-- nvim-ufo for better code folding

return {
  -- nvim-ufo: Better folding with LSP/Treesitter support
  {
    "kevinhwang91/nvim-ufo",
    dependencies = "kevinhwang91/promise-async",
    event = "BufReadPost",
    opts = {
      provider_selector = function(bufnr, filetype, buftype)
        return { "treesitter", "indent" }
      end,
      fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
        local newVirtText = {}
        local suffix = ("  %d "):format(endLnum - lnum)
        local sufWidth = vim.fn.strdisplaywidth(suffix)
        local targetWidth = width - sufWidth
        local curWidth = 0
        for _, chunk in ipairs(virtText) do
          local chunkText = chunk[1]
          local chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
          else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            local hlGroup = chunk[2]
            table.insert(newVirtText, { chunkText, hlGroup })
            chunkWidth = vim.fn.strdisplaywidth(chunkText)
            if curWidth + chunkWidth < targetWidth then
              suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
            end
            break
          end
          curWidth = curWidth + chunkWidth
        end
        table.insert(newVirtText, { suffix, "MoreMsg" })
        return newVirtText
      end,
    },
    config = function(_, opts)
      require("ufo").setup(opts)

      -- Fold settings
      vim.o.foldcolumn = "1"
      vim.o.foldlevel = 99
      vim.o.foldlevelstart = 99
      vim.o.foldenable = true

      -- View persistence (saves folds, cursor position)
      local view_group = vim.api.nvim_create_augroup("auto_view", { clear = true })

      vim.api.nvim_create_autocmd({ "BufWinLeave", "BufWritePost", "WinLeave" }, {
        desc = "Save view with mkview for real files",
        group = view_group,
        callback = function(args)
          if vim.b[args.buf].view_activated then
            vim.cmd.mkview { mods = { emsg_silent = true } }
          end
        end,
      })

      vim.api.nvim_create_autocmd("BufWinEnter", {
        desc = "Try to load file view if available and enable view saving for real files",
        group = view_group,
        callback = function(args)
          if not vim.b[args.buf].view_activated then
            local filetype = vim.api.nvim_get_option_value("filetype", { buf = args.buf })
            local buftype = vim.api.nvim_get_option_value("buftype", { buf = args.buf })
            local ignore_filetypes = { "gitcommit", "gitrebase", "svg", "hgcommit" }
            if buftype == "" and filetype and filetype ~= "" and not vim.tbl_contains(ignore_filetypes, filetype) then
              vim.b[args.buf].view_activated = true
              vim.cmd.loadview { mods = { emsg_silent = true } }
            end
          end
        end,
      })

      -- Override K keymap to integrate fold preview
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("ufo_lsp_attach", { clear = true }),
        callback = function(event)
          vim.keymap.set("n", "K", function()
            local winid = require("ufo").peekFoldedLinesUnderCursor()
            if not winid then
              vim.lsp.buf.hover({ border = "rounded" })
            end
          end, { buf = event.buf, desc = "Hover Documentation / Peek Fold" })
        end,
      })
    end,
  },
}

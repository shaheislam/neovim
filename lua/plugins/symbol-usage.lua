-- Virtual text for references/implementations count
return {
  "Wansmer/symbol-usage.nvim",
  event = "LspAttach",
  config = function()
    local hl = vim.api.nvim_set_hl

    -- Tokyo Night compatible colors
    hl(0, "SymbolUsageRounding", { fg = "#2a2a37", italic = true })
    hl(0, "SymbolUsageContent", { bg = "#2a2a37", fg = "#898b9a", italic = true })
    hl(0, "SymbolUsageRef", { fg = "#70a5eb", bg = "#2a2a37", italic = true })
    hl(0, "SymbolUsageDef", { fg = "#eba070", bg = "#2a2a37", italic = true })
    hl(0, "SymbolUsageImpl", { fg = "#eb7097", bg = "#2a2a37", italic = true })

    local function text_format(symbol)
      local res = {}

      -- Rounded corners
      table.insert(res, { "⟪", "SymbolUsageRounding" })

      -- References
      if symbol.references then
        table.insert(res, { "󰌹 " .. tostring(symbol.references), "SymbolUsageRef" })
      end

      -- Definition
      if symbol.definition then
        if #res > 1 then
          table.insert(res, { " ", "SymbolUsageContent" })
        end
        table.insert(res, { "󰳽 " .. tostring(symbol.definition), "SymbolUsageDef" })
      end

      -- Implementation
      if symbol.implementation then
        if #res > 1 then
          table.insert(res, { " ", "SymbolUsageContent" })
        end
        table.insert(res, { "󰡱 " .. tostring(symbol.implementation), "SymbolUsageImpl" })
      end

      -- Closing
      table.insert(res, { "⟫", "SymbolUsageRounding" })

      return res
    end

    require("symbol-usage").setup({
      text_format = text_format,
      vt_position = "end_of_line",
      disable = { lsp = { "pylsp", "pyright" } }, -- Disabled for some LSPs that don't support it well
      filetypes = { -- Enable only for specific filetypes
        "rust",
        "go",
        "typescript",
        "javascript",
        "typescriptreact",
        "javascriptreact",
        "lua",
        "c",
        "cpp",
        "java",
        "python",
      },
    })
  end,
}

-- ~/.config/nvim/lua/plugins/incline.lua
-- Floating statusline for Neovim with diagnostics and git status

return {
  "b0o/incline.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    window = {
      padding = 1,
      margin = { horizontal = 1, vertical = 1 },
      placement = {
        horizontal = "right",
        vertical = "top",
      },
      width = "fit",
      winhighlight = {
        Normal = "Normal",
      },
    },
    hide = {
      focused_win = false,
      only_win = false,
    },
    render = function(props)
      local devicons = require("nvim-web-devicons")
      local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")

      -- Handle empty filename
      if filename == "" then
        filename = "[No Name]"
      end

      -- Get file icon and color
      local ft_icon, ft_color = devicons.get_icon_color(filename)

      -- Get diagnostics
      local diagnostics = vim.diagnostic.get(props.buf)
      local diagnostic_counts = { 0, 0, 0, 0 }
      for _, diagnostic in ipairs(diagnostics) do
        diagnostic_counts[diagnostic.severity] = diagnostic_counts[diagnostic.severity] + 1
      end

      local diagnostic_labels = {}
      local severity_colors = {
        "#db4b4b", -- Error (Tokyo Night red)
        "#e0af68", -- Warning (Tokyo Night yellow)
        "#9ece6a", -- Info (Tokyo Night green)
        "#7aa2f7", -- Hint (Tokyo Night blue)
      }
      local severity_icons = { " ", " ", " ", " " }

      for severity, count in ipairs(diagnostic_counts) do
        if count > 0 then
          table.insert(diagnostic_labels, {
            severity_icons[severity] .. count,
            guifg = severity_colors[severity],
          })
          table.insert(diagnostic_labels, " ")
        end
      end

      -- Modified indicator
      local modified = vim.bo[props.buf].modified

      -- Build the statusline
      local components = {}

      -- Add file icon
      if ft_icon then
        table.insert(components, { ft_icon, guifg = ft_color })
        table.insert(components, " ")
      end

      -- Add filename with modified indicator
      table.insert(components, {
        filename .. (modified and " ●" or ""),
        gui = modified and "bold,italic" or "bold",
        guifg = modified and "#f7768e" or "#c0caf5", -- Tokyo Night colors
      })

      -- Add diagnostics if present
      if #diagnostic_labels > 0 then
        table.insert(components, " │ ")
        for _, label in ipairs(diagnostic_labels) do
          table.insert(components, label)
        end
      end

      -- Add padding
      table.insert(components, " ")

      return components
    end,
  },
  config = function(_, opts)
    require("incline").setup(opts)

    -- Optional: hide incline in specific filetypes
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "neo-tree", "dashboard", "lazy", "mason", "TelescopePrompt" },
      callback = function()
        local incline = require("incline")
        incline.disable()
      end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function()
        local ft = vim.bo.filetype
        local excluded = { "neo-tree", "dashboard", "lazy", "mason", "TelescopePrompt" }
        if not vim.tbl_contains(excluded, ft) then
          require("incline").enable()
        end
      end,
    })
  end,
}

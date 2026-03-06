-- ~/.config/nvim/lua/plugins/incline.lua
-- Floating statusline for Neovim with diagnostics and git status

-- Cache diagnostic counts per buffer, updated only on DiagnosticChanged (not every render).
-- incline's render() fires on every redraw (every scroll frame), and vim.diagnostic.get()
-- + iteration was the main source of scroll jank.
local diag_cache = {}

local severity_colors = {
  "#db4b4b", -- Error (Tokyo Night red)
  "#e0af68", -- Warning (Tokyo Night yellow)
  "#9ece6a", -- Info (Tokyo Night green)
  "#7aa2f7", -- Hint (Tokyo Night blue)
}
local severity_icons = { " ", " ", " ", " " }

local function refresh_diag_cache(bufnr)
  local counts = { 0, 0, 0, 0 }
  for _, d in ipairs(vim.diagnostic.get(bufnr)) do
    counts[d.severity] = counts[d.severity] + 1
  end
  local labels = {}
  for sev, count in ipairs(counts) do
    if count > 0 then
      labels[#labels + 1] = { severity_icons[sev] .. count, guifg = severity_colors[sev] }
      labels[#labels + 1] = " "
    end
  end
  diag_cache[bufnr] = labels
end

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

      if filename == "" then
        filename = "[No Name]"
      end

      local ft_icon, ft_color = devicons.get_icon_color(filename)

      -- Read cached diagnostics (populated by DiagnosticChanged autocmd, not here)
      local diagnostic_labels = diag_cache[props.buf] or {}

      local modified = vim.bo[props.buf].modified

      local components = {}

      if ft_icon then
        components[#components + 1] = { ft_icon, guifg = ft_color }
        components[#components + 1] = " "
      end

      components[#components + 1] = {
        filename .. (modified and " ●" or ""),
        gui = modified and "bold,italic" or "bold",
        guifg = modified and "#f7768e" or "#c0caf5",
      }

      if #diagnostic_labels > 0 then
        components[#components + 1] = " │ "
        for _, label in ipairs(diagnostic_labels) do
          components[#components + 1] = label
        end
      end

      components[#components + 1] = " "
      return components
    end,
  },
  config = function(_, opts)
    require("incline").setup(opts)

    -- Update diagnostic cache only when diagnostics actually change
    vim.api.nvim_create_autocmd("DiagnosticChanged", {
      callback = function(args)
        refresh_diag_cache(args.buf)
      end,
    })

    -- Hide incline in specific filetypes (including diffview for scroll perf)
    local excluded_fts = {
      "neo-tree", "dashboard", "lazy", "mason", "TelescopePrompt",
      "DiffviewFiles", "DiffviewFileHistory",
    }
    vim.api.nvim_create_autocmd("FileType", {
      pattern = excluded_fts,
      callback = function()
        require("incline").disable()
      end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function()
        local ft = vim.bo.filetype
        if vim.tbl_contains(excluded_fts, ft) then
          return
        end
        -- Don't re-enable while DiffView is open (view_opened disables for scroll perf;
        -- diff panes have the original file's filetype, not DiffviewFiles, so the
        -- filetype check above misses them).
        local dv_ok, dv_lib = pcall(require, "diffview.lib")
        if dv_ok and dv_lib.get_current_view() then
          return
        end
        require("incline").enable()
      end,
    })
  end,
}

-- Styling Autocmds - Consistent visual styling across all colorschemes
-- This module ensures italics, bold, and other styling is consistent regardless of theme

local M = {}

local function augroup(name)
  return vim.api.nvim_create_augroup("styling_" .. name, { clear = true })
end

-- Helper function to merge styles with existing colors
local function merge_style(group, new_style)
  -- Get existing highlight group (includes colors from theme)
  local existing = vim.api.nvim_get_hl(0, { name = group, link = false })

  -- Merge new styles (italic/bold) with existing colors (fg/bg/sp)
  -- This preserves theme colors while applying consistent styling
  local merged = vim.tbl_extend("force", existing, new_style)

  -- Apply the merged highlight
  vim.api.nvim_set_hl(0, group, merged)
end

-- Standardized highlight overrides for consistent styling
local function apply_consistent_styles()
  -- Tree-sitter highlight groups (modern, preferred method)
  local ts_highlights = {
    -- Comments
    ["@comment"] = { italic = true },
    ["@comment.documentation"] = { italic = true },

    -- Keywords
    ["@keyword"] = { bold = true, italic = true },
    ["@keyword.function"] = { bold = true, italic = true },
    ["@keyword.operator"] = { bold = true, italic = true },
    ["@keyword.return"] = { bold = true, italic = true },
    ["@keyword.conditional"] = { italic = true },
    ["@keyword.repeat"] = { italic = true },

    -- Functions
    ["@function"] = { italic = true },
    ["@function.builtin"] = { italic = true },
    ["@function.method"] = { italic = true },
    ["@function.call"] = { italic = true },

    -- Types
    ["@type"] = { bold = true, italic = true },
    ["@type.builtin"] = { bold = true, italic = true },
    ["@type.definition"] = { bold = true, italic = true },

    -- Conditionals and Loops
    ["@conditional"] = { italic = true },
    ["@repeat"] = { italic = true },

    -- Booleans (bold, no italic)
    ["@boolean"] = { bold = true },
    ["@constant.builtin"] = { bold = true },
  }

  -- Legacy vim highlight groups (fallback for non-tree-sitter)
  local vim_highlights = {
    Comment = { italic = true },
    Keyword = { bold = true, italic = true },
    Function = { italic = true },
    Type = { bold = true, italic = true },
    Conditional = { italic = true },
    Repeat = { italic = true },
    Boolean = { bold = true },
  }

  -- Inccommand preview highlights (for :substitute preview in split)
  local inccommand_highlights = {
    Substitute = { bold = true, reverse = true },  -- Bold + reverse video for replacement text
    Search = { bold = true },                       -- Bold for matched text
  }

  -- Apply tree-sitter highlights with color preservation
  for group, style in pairs(ts_highlights) do
    merge_style(group, style)
  end

  -- Apply legacy highlights with color preservation
  for group, style in pairs(vim_highlights) do
    merge_style(group, style)
  end

  -- Apply inccommand highlights with color preservation
  for group, style in pairs(inccommand_highlights) do
    merge_style(group, style)
  end

  -- Blink Plugins - Dynamic theme-aware colors via highlight linking
  local blink_highlights = {
    -- Blink Indent: Link to operator colors (cyan/teal in most themes)
    BlinkIndentScope = { link = "@operator" },

    -- Blink Pairs: Rainbow bracket colors from semantic groups
    BlinkPairsOrange = { link = "@number" },           -- Orange from numbers
    BlinkPairsPurple = { link = "Identifier" },        -- Purple from identifiers
    BlinkPairsBlue = { link = "@function" },           -- Blue from functions
    BlinkPairsUnmatched = { link = "DiagnosticError" }, -- Red from errors
  }

  -- Apply blink highlights with theme-aware links
  for group, highlight in pairs(blink_highlights) do
    vim.api.nvim_set_hl(0, group, highlight)
  end

  -- Match paren: Link to type colors, then add bold styling
  vim.api.nvim_set_hl(0, "BlinkPairsMatchParen", { link = "@type" })
  merge_style("BlinkPairsMatchParen", { bold = true })
end

function M.setup()
  -- Apply consistent styles after any colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup("consistent_highlights"),
    callback = apply_consistent_styles,
    desc = "Apply consistent italic/bold styling across all themes",
  })

  -- Also apply on startup after colorscheme is loaded
  vim.api.nvim_create_autocmd("VimEnter", {
    group = augroup("consistent_highlights_init"),
    callback = function()
      -- Small delay to ensure theme is fully loaded
      vim.defer_fn(apply_consistent_styles, 100)
    end,
    desc = "Apply consistent styling on startup",
  })
end

return M

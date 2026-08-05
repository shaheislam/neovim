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

-- Atlas.nvim (pilot, see lua/plugins/atlas.lua) ships opaque status chips.
-- Promoting the chip's background color to its foreground keeps the text
-- readable while dropping the background block, matching this config's
-- transparent-UI requirement without hard-coding Atlas's default palette.
local function promote_bg_to_fg(group)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  if not hl.bg then
    return
  end
  vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", hl, { fg = hl.bg, bg = "NONE" }))
end

-- Groups that already have a readable fg on their dark default bg (header
-- bars, not chips) — clear the bg only, keep the existing fg untouched.
local atlas_header_groups = {
  "AtlasPanelHeaderBg",
  "AtlasFooterBackground",
  "AtlasTabInactive",
  "AtlasGitHubTheme",
  "AtlasGHIssuesTheme",
}

-- Chip groups with predictable names (dark fg on a bright bg — GitHub-only,
-- matching the pilot's enabled providers in lua/plugins/atlas.lua). Verified
-- against the installed plugin source (atlas/{pulls,issues,ui/shared}/**
-- highlights.lua), not just the README, since group names and fg/bg pairing
-- there don't perfectly match public docs.
local atlas_chip_groups = {
  "AtlasChipActive",
  "AtlasDynBgColor01",
  "AtlasDynBgColor02",
  "AtlasDynBgColor03",
  "AtlasDynBgColor04",
  "AtlasDynBgColor05",
  "AtlasDynBgColor06",
  "AtlasDynBgColor07",
  "AtlasDynBgColor08",
  "AtlasDynBgColor09",
  "AtlasDynBgColor10",
  "AtlasDynBgColor11",
  "AtlasPROpenChip",
  "AtlasPRMergedChip",
  "AtlasPRDeclinedChip",
  "AtlasPRDraftChip",
  "AtlasGitHubPROpen",
  "AtlasGitHubPRMerged",
  "AtlasGitHubPRClosed",
  "AtlasGitHubPRDraft",
  "AtlasGHIssueOpenChip",
  "AtlasGHIssueClosedChip",
  "AtlasGHIssueChipRepo",
}

-- Provider-generated label/type chips use hex-suffixed names (e.g.
-- AtlasGHLabel_ff0000) that can't be listed up front, so they're swept by
-- pattern instead.
local atlas_dynamic_patterns = {
  "^AtlasGHLabel_",
  "^AtlasGHIssueLabel_",
  "^AtlasGHIssueType_",
}

-- Re-applies transparent styling to Atlas.nvim's highlight groups. Atlas is
-- cmd-lazy loaded and (re)defines these groups on setup and on render, so
-- callers must re-invoke this after opening Atlas UI, not just on
-- ColorScheme (see lua/plugins/atlas.lua for the deferred re-apply calls).
function M.apply_atlas_transparency()
  for _, group in ipairs(atlas_header_groups) do
    merge_style(group, { bg = "NONE" })
  end

  for _, group in ipairs(atlas_chip_groups) do
    promote_bg_to_fg(group)
  end

  for name in pairs(vim.api.nvim_get_hl(0, {})) do
    for _, pattern in ipairs(atlas_dynamic_patterns) do
      if name:match(pattern) then
        promote_bg_to_fg(name)
        break
      end
    end
  end
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
    -- Blink Indent: Rose Pine rainbow palette
    BlinkIndent = { fg = "#6e6a86" },              -- Rose Pine muted (subtle static guides)
    BlinkIndentOrange = { fg = "#ebbcba" },        -- Rose Pine "rose" color
    BlinkIndentViolet = { fg = "#c4a7e7" },        -- Rose Pine "iris" (purple)
    BlinkIndentBlue = { fg = "#31748f" },          -- Rose Pine "pine" (blue/teal)
    BlinkIndentScope = { fg = "#9ccfd8" },         -- Rose Pine "foam" (cyan) fallback

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

  -- LSP Inlay Hints: boost visibility across all themes
  -- Default theme colors (#545C7E on #262640) are nearly invisible on dark terminals
  vim.api.nvim_set_hl(0, "LspInlayHint", { fg = "#7A88A8", italic = true })

  -- Diffview: keep the gutter/inline diff cues without painting full-line blocks.
  local transparent_diff = {
    DiffAdd = { bg = "NONE" },
    DiffDelete = { bg = "NONE" },
    DiffChange = { bg = "NONE" },
    DiffText = { bg = "NONE" },
    DiffviewDiffAdd = { bg = "NONE" },
    DiffviewDiffDelete = { bg = "NONE" },
    DiffviewDiffChange = { bg = "NONE" },
    DiffviewDiffText = { bg = "NONE" },
    DiffviewDiffAddAsDelete = { bg = "NONE" },
  }

  for group, style in pairs(transparent_diff) do
    merge_style(group, style)
  end

  vim.api.nvim_set_hl(0, "DiffviewDiffAddInline", { fg = "#e0af68", bg = "#3a3220", bold = true })
  vim.api.nvim_set_hl(0, "DiffviewDiffDeleteInline", { fg = "#f7768e", bg = "#3a2228", bold = true, strikethrough = true })
  vim.api.nvim_set_hl(0, "DiffviewWordChange", { fg = "#e0af68", bg = "#3a3220", bold = true })
  vim.api.nvim_set_hl(0, "DiffviewWordDelete", { fg = "#f7768e", bg = "#3a2228", bold = true, strikethrough = true })
  vim.api.nvim_set_hl(0, "DiffviewGutterAdd", { fg = "#4f7d43", bg = "NONE" })
  vim.api.nvim_set_hl(0, "DiffviewGutterDelete", { fg = "#f7768e", bg = "NONE" })
  vim.api.nvim_set_hl(0, "DiffviewGutterChange", { fg = "#e0af68", bg = "NONE" })

  M.apply_atlas_transparency()
end

M.apply_consistent_styles = apply_consistent_styles

function M.setup()
  -- Apply consistent styles after any colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup("consistent_highlights"),
    callback = apply_consistent_styles,
    desc = "Apply consistent italic/bold styling across all themes",
  })

  vim.api.nvim_create_autocmd("User", {
    group = augroup("consistent_highlights_matugen"),
    pattern = "MatugenReloaded",
    callback = function()
      vim.defer_fn(apply_consistent_styles, 20)
    end,
    desc = "Reapply consistent styling after matugen reloads",
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

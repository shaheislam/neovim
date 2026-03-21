-- Tree-sitter: syntax highlighting, textobjects, injections

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
      require("nvim-treesitter.configs").setup({
        parser_install_dir = parser_install_dir,
        ensure_installed = {
          -- Core
          "lua", "vim", "vimdoc", "query",
          -- Shell
          "bash", "fish",
          -- Languages
          "go", "gomod", "gowork",
          "rust",
          "python",
          "javascript", "typescript",
          "c",
          -- Data/config
          "json", "yaml", "toml",
          -- Markup
          "markdown", "markdown_inline",
          "html",
          "typst",
          -- Injection support (enables highlighting inside host language strings)
          "sql", "regex",
          "comment",
          -- Infrastructure
          "dockerfile", "hcl",
          "proto",
        },
      })
    end,
  },

  -- Treesitter textobjects: af/if (function), ac/ic (class), ]f/[f (navigate)
  -- Also provides textobjects.scm query files used by mini.ai
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      select = { lookahead = true },
      move = { set_jumps = true },
    },
    config = function(_, opts)
      require("nvim-treesitter-textobjects").setup(opts)
      local select = require("nvim-treesitter-textobjects.select")
      local move = require("nvim-treesitter-textobjects.move")

      local function set_keymaps(modes, fn, mappings)
        for keys, query in pairs(mappings) do
          local desc = query:sub(2):gsub("(%a+)%.(%a+)", "%2 %1")
          vim.keymap.set(modes, keys, function()
            fn(query, "textobjects")
          end, { desc = desc })
        end
      end

      -- Selection textobjects (operator-pending + visual)
      -- daf = delete around function, vif = visual select inner function
      set_keymaps({ "o", "x" }, select.select_textobject, {
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
        ["ab"] = "@block.outer",
        ["ib"] = "@block.inner",
        ["al"] = "@loop.outer",
        ["il"] = "@loop.inner",
        ["aa"] = "@parameter.outer",
        ["ia"] = "@parameter.inner",
        ["is"] = "@statement.outer",
      })

      -- Navigate to next/previous function/class/block/loop
      set_keymaps({ "n", "x", "o" }, move.goto_next_start, {
        ["]f"] = "@function.outer",
        ["]c"] = "@class.outer",
        ["]b"] = "@block.outer",
        ["]l"] = "@loop.outer",
      })
      set_keymaps({ "n", "x", "o" }, move.goto_previous_start, {
        ["[f"] = "@function.outer",
        ["[c"] = "@class.outer",
        ["[b"] = "@block.outer",
        ["[l"] = "@loop.outer",
      })
    end,
  },
}

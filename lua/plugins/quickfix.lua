-- Enhanced Quickfix Management
-- quicker.nvim: Better quickfix/location list management
-- nvim-pqf: Pretty quickfix formatting
-- nvim-bqf: Quickfix enhancements with filtering

return {
  -- Better quickfix and location list management
  {
    "stevearc/quicker.nvim",
    event = "VeryLazy",
    init = function()
      -- Suppress quicker.nvim display errors (conflicts with nvim-pqf formatting)
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        if type(msg) == "string" and msg:match("quicker.nvim/lua/quicker/display.lua") then
          return -- Silence quicker display errors
        end
        original_notify(msg, level, opts)
      end
    end,
    opts = {
      opts = {
        buflisted = false,
        number = false,
        relativenumber = false,
        signcolumn = "auto",
        winfixheight = true,
        wrap = false,
      },
      keys = {
        {
          ">",
          function()
            require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
          end,
          desc = "Expand quickfix context",
        },
        {
          "<",
          function()
            require("quicker").collapse()
          end,
          desc = "Collapse quickfix context",
        },
      },
      on_qf = function(bufnr)
        -- Keep quickfix at bottom with fixed height
        vim.cmd("wincmd J")
        vim.cmd("resize 10")

        -- Helper function to jump to quickfix item location
        local function jump_to_qf_item()
          local qf_idx = vim.fn.line('.')
          local qf_list = vim.fn.getqflist()
          local item = qf_list[qf_idx]

          if item and item.bufnr > 0 then
            vim.cmd("wincmd k")
            vim.cmd(qf_idx .. "cc")
            vim.cmd("normal! zz")

            -- Ensure syntax highlighting is properly enabled
            local current_buf = vim.api.nvim_get_current_buf()

            -- Explicitly detect filetype if not already set
            if vim.bo[current_buf].filetype == "" then
              vim.cmd("filetype detect")
            end

            -- Enable syntax highlighting
            if vim.bo[current_buf].syntax == "" then
              vim.bo[current_buf].syntax = vim.bo[current_buf].filetype
            end

            -- Ensure treesitter is attached if available
            local ok, ts_highlighter = pcall(require, "vim.treesitter.highlighter")
            if ok and ts_highlighter then
              pcall(ts_highlighter.active, current_buf)
            end

            vim.cmd("wincmd j")
          end
        end

        -- Auto-preview when navigating
        vim.api.nvim_create_autocmd("CursorMoved", {
          buffer = bufnr,
          callback = function()
            pcall(jump_to_qf_item)
          end,
        })

        -- Custom keymaps for quickfix buffer
        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
        end

        map("n", "r", function() require("quicker").refresh() end, "Refresh quickfix")
        map("n", "q", function() require("quicker").close() end, "Close quickfix")
        map("n", "<Tab>", function() vim.cmd("wincmd k") end, "Switch to buffer")
        map("n", "<CR>", function()
          local qf_idx = vim.fn.line('.')
          vim.cmd("wincmd k")
          vim.cmd(qf_idx .. "cc")
          vim.cmd("normal! zz")
        end, "Open entry")
        map("n", "j", function()
          vim.cmd("normal! j")
          jump_to_qf_item()
        end, "Next item")
        map("n", "k", function()
          vim.cmd("normal! k")
          jump_to_qf_item()
        end, "Previous item")
      end,
      max_height = 10,
    },
    keys = {
      {
        "<leader>qq",
        function() require("quicker").toggle() end,
        desc = "Toggle quickfix",
      },
      {
        "<leader>ql",
        function() require("quicker").toggle({ loclist = true }) end,
        desc = "Toggle loclist",
      },
      {
        "<Tab>",
        function()
          local current_win = vim.fn.getwininfo(vim.fn.win_getid())[1]
          if current_win.quickfix == 1 then
            return
          end

          if vim.bo.modified and not vim.bo.readonly and vim.fn.expand("%") ~= "" then
            vim.cmd("silent! write")
          end

          for _, win in ipairs(vim.fn.getwininfo()) do
            if win.quickfix == 1 then
              vim.fn.win_gotoid(win.winid)
              return
            end
          end
        end,
        desc = "Jump to quickfix",
      },
    },
  },

  -- Pretty quickfix formatting
  {
    "yorickpeterse/nvim-pqf",
    ft = "qf",
    config = function()
      require("pqf").setup({
        signs = {
          error = "E",
          warning = "W",
          info = "I",
          hint = "H",
        },
        max_filename_length = 0,
        show_line_numbers = true,
      })
    end,
  },

  -- Enhanced quickfix with filtering
  {
    "kevinhwang91/nvim-bqf",
    ft = "qf",
    dependencies = {
      "junegunn/fzf",
      "nvim-treesitter/nvim-treesitter", -- Enable syntax highlighting in quickfix
    },
    opts = {
      auto_enable = true,
      auto_resize_height = false,
      preview = {
        auto_preview = false,
        should_preview_cb = function() return false end,
      },
      filter = {
        fzf = {
          action_for = { ["ctrl-s"] = "split", ["ctrl-t"] = "tab drop" },
          extra_opts = { "--bind", "ctrl-o:toggle-all", "--prompt", "> " },
        },
      },
    },
  },
}

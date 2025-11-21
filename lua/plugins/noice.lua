-- Noice.nvim configuration to ensure text fits in message window
return {
  "folke/noice.nvim",
  enabled = true, -- Using split view for message history (no popups)
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
  cmd = { "Noice" },
  -- LazyVim already defines keys under <leader>sn prefix
  -- We'll add our custom shortcuts that don't conflict
  keys = {
    -- Ctrl-C to dismiss messages in any mode
    { "<C-c>", function() require("noice").cmd("dismiss") end, desc = "Dismiss Messages", mode = {"n", "i", "v"} },
    -- Quick access to history (in addition to LazyVim's <leader>snh)
    { "<leader>mh", function() require("noice").cmd("history") end, desc = "Message History" },
    { "<leader>ml", function() vim.cmd("Noice last split") end, desc = "Last Message" },
    { "<leader>md", function() require("noice").cmd("dismiss") end, desc = "Dismiss Messages" },
    -- Toggle persistent messages
    { "<leader>mp", function()
      vim.g.noice_persistent_messages = not vim.g.noice_persistent_messages

      -- Update Noice configuration directly
      local config = require("noice.config")

      -- Calculate new timeout
      local new_timeout = vim.g.noice_persistent_messages and 30000 or 3000

      -- Update the views config
      if config.options.views.mini then
        config.options.views.mini.timeout = new_timeout
      end

      -- Update smart_move
      config.options.smart_move.enabled = not vim.g.noice_persistent_messages

      -- Update all routes that use mini view to have the new timeout
      for _, route in ipairs(config.options.routes) do
        if route.view == "mini" then
          route.opts = route.opts or {}
          route.opts.timeout = new_timeout
        end
      end

      -- Force update of any existing mini views
      for _, view in pairs(require("noice.view")._views or {}) do
        if view._opts and view._opts.timeout then
          view._opts.timeout = new_timeout
        end
        if view.opts and view.opts.timeout then
          view.opts.timeout = new_timeout
        end
      end

      -- Show status
      local status = vim.g.noice_persistent_messages and "ON (30s)" or "OFF (3s)"
      vim.notify("Persistent messages: " .. status, vim.log.levels.INFO)
    end, desc = "Toggle Persistent Messages" },
  },
  config = function(_, opts)
    -- Initialize persistent messages as disabled by default
    vim.g.noice_persistent_messages = false

    -- Override views for better auto-dismiss behavior
    opts.views = opts.views or {}

    -- Use notify view (corner notifications) instead of mini (centered popups)
    -- notify view is less intrusive and works better with smart_move
    opts.views.notify = vim.tbl_deep_extend("force", opts.views.notify or {}, {
      backend = "notify",
      fallback = "mini",
      timeout = 2000,  -- Shorter timeout for notify view
    })

    -- Configure nvim-notify for instant notifications (no animations)
    require("notify").setup({
      stages = "static",  -- Disable animations for instant appearance/dismissal
      timeout = 2000,     -- Match noice timeout
    })
    -- Schedule redraw to avoid blocking
    vim.schedule(function() vim.cmd("redraw") end)

    opts.views.mini = vim.tbl_deep_extend("force", opts.views.mini or {}, {
      backend = "mini",
      relative = "editor",
      align = "center",
      timeout = false,  -- Disable timeout - rely only on smart_move for dismissal
      position = {
        row = "50%",
        col = "50%",
      },
      size = "auto",
      border = {
        style = "double",
        padding = { 0, 2 },
      },
      win_options = {
        winblend = 0,
        winhighlight = "Normal:Normal,FloatBorder:DiagnosticInfo",
      },
    })

    -- Add a hook to the split view to scroll to bottom on open
    local original_split = opts.views.split or {}
    opts.views.split = vim.tbl_deep_extend("force", original_split, {
      enter = true,
      -- Override the update function to scroll to bottom on open
      opts = {
        on_open = function(win)
          vim.api.nvim_win_set_option(win, "wrap", true)
          vim.api.nvim_win_set_option(win, "linebreak", true)
          -- Scroll to bottom on initial open
          vim.defer_fn(function()
            if vim.api.nvim_win_is_valid(win) then
              local buf = vim.api.nvim_win_get_buf(win)
              local line_count = vim.api.nvim_buf_line_count(buf)
              vim.api.nvim_win_set_cursor(win, { line_count, 0 })
              vim.cmd("normal! zb")
            end
          end, 1)
        end,
      },
    })

    require("noice").setup(opts)

    -- Monkey-patch the mini backend to use dynamic timeouts
    -- Immediate execution (no defer) to prevent race conditions with early notifications
    local ok, Mini = pcall(require, "noice.view.backend.mini")
    if ok and Mini then
      local original_show = Mini.show

      Mini.show = function(self)
        -- Override timeout before showing
        if self._opts then
          self._opts.timeout = vim.g.noice_persistent_messages and 30000 or 3000
        end
        -- Call original show and schedule redraw
        local result = original_show(self)
        vim.schedule(function() vim.cmd("redraw") end)
        return result
      end
    end

    -- Monkey-patch the notify backend for synchronous rendering
    local ok_notify, Notify = pcall(require, "noice.view.backend.notify")
    if ok_notify and Notify then
      local original_show_notify = Notify.show

      Notify.show = function(self)
        -- Call original show
        local result = original_show_notify(self)
        -- Schedule redraw to avoid blocking
        vim.schedule(function() vim.cmd("redraw") end)
        return result
      end
    end

    -- Store the original notify function
    local notify = require("notify")

    -- Override vim.notify to use dynamic timeout
    local original_notify = vim.notify
    vim.notify = function(msg, level, opts)
      opts = opts or {}
      -- Set timeout based on persistent mode
      if vim.g.noice_persistent_messages then
        opts.timeout = 30000  -- 30 seconds in persistent mode
        opts.animate = false  -- No animation in persistent mode
      else
        opts.timeout = opts.timeout or 3000  -- 3 seconds by default
        opts.animate = true
      end
      return notify(msg, level, opts)
    end

    
    -- Track manual scrolling to avoid interfering
    local noice_manually_scrolled = {}
    
    -- Function to scroll to bottom only if not manually scrolled
    local function scroll_to_bottom(force)
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        local bufname = vim.api.nvim_buf_get_name(buf)
        if ft == "noice" or ft == "NoiceHistory" or ft == "NoiceSplit" or 
           bufname:match("Noice") or bufname:match("noice") then
          
          -- Skip if manually scrolled (unless forced)
          if not force and noice_manually_scrolled[win] then
            -- Check if we're already at the bottom
            local cursor = vim.api.nvim_win_get_cursor(win)
            local line_count = vim.api.nvim_buf_line_count(buf)
            if cursor[1] >= line_count - 1 then
              -- We're near the bottom, clear the manual scroll flag
              noice_manually_scrolled[win] = nil
            else
              -- Still manually scrolled, don't auto-scroll
              return
            end
          end
          
          local line_count = vim.api.nvim_buf_line_count(buf)
          -- Save current window to restore later
          local current_win = vim.api.nvim_get_current_win()
          -- Move to last line
          vim.api.nvim_win_set_cursor(win, { line_count, 0 })
          -- Only switch windows if needed for scrolling
          if current_win == win then
            vim.cmd("normal! Gzb")
          end
        end
      end
    end
    
    -- Detect manual scrolling
    vim.api.nvim_create_autocmd({ "WinScrolled" }, {
      callback = function()
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        if ft == "noice" or ft == "NoiceHistory" or ft == "NoiceSplit" then
          local cursor = vim.api.nvim_win_get_cursor(win)
          local line_count = vim.api.nvim_buf_line_count(buf)
          -- If we're not at the bottom, mark as manually scrolled
          if cursor[1] < line_count - 2 then
            noice_manually_scrolled[win] = true
          else
            noice_manually_scrolled[win] = nil
          end
        end
      end,
    })
    
    -- Initial scroll to bottom when opening
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
      pattern = { "noice", "NoiceHistory", "NoiceSplit" },
      callback = function()
        vim.defer_fn(function() scroll_to_bottom(true) end, 1)
      end,
    })
    
    -- Scroll to bottom only when new messages are added
    vim.api.nvim_create_autocmd("User", {
      pattern = { "NoiceMessageAdded" },
      callback = function()
        vim.defer_fn(function() scroll_to_bottom(false) end, 1)
      end,
    })
    
    -- Reset manual scroll flag when window is closed
    vim.api.nvim_create_autocmd({ "WinClosed" }, {
      callback = function()
        local win = tonumber(vim.fn.expand("<afile>"))
        if win then
          noice_manually_scrolled[win] = nil
        end
      end,
    })

    -- Auto-dismiss disabled: messages persist in split view
    -- vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    --   callback = function()
    --     if not vim.g.noice_persistent_messages then
    --       require("noice").cmd("dismiss")
    --     end
    --   end,
    -- })

    -- Map Esc to dismiss messages in normal mode
    -- Using defer to ensure it runs after LazyVim keymaps are loaded
    vim.defer_fn(function()
      vim.keymap.set("n", "<Esc>", function()
        -- First do normal Esc behavior
        vim.cmd("nohlsearch")
        -- Then dismiss noice messages
        pcall(function()
          require("noice").cmd("dismiss")
        end)
      end, { desc = "Clear Highlight and Dismiss Noice Messages", silent = true })
    end, 100)

    -- Auto-detect and apply syntax highlighting to noice buffers
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "noice",
      callback = function(args)
        vim.defer_fn(function()
          if not vim.api.nvim_buf_is_valid(args.buf) then return end

          -- Get buffer content
          local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 20, false)
          local content = table.concat(lines, "\n"):lower()

          -- Detect content type and set filetype
          if content:match("on branch") or content:match("changes not staged") or
             content:match("modified:") or content:match("untracked files") then
            vim.bo[args.buf].filetype = "git"
            vim.bo[args.buf].syntax = "git"
          end
        end, 50)
      end,
      group = vim.api.nvim_create_augroup("NoiceSyntaxHighlight", { clear = true }),
    })
  end,
  opts = {
    -- Cmdline configuration
    cmdline = {
      enabled = true,
      view = "cmdline", -- Use traditional bottom cmdline (like /)
    },
    -- Views configuration - use split buffer for messages
    views = {
      cmdline_popup = {
        position = {
          row = "90%", -- Position near bottom of screen
          col = "50%", -- Center horizontally
        },
        size = {
          width = "auto",
          height = "auto",
          min_width = 40, -- Minimum width
          max_width = 90, -- Maximum width to prevent overflow
        },
        win_options = {
          wrap = true, -- Enable text wrapping
          linebreak = true, -- Break at word boundaries
        },
      },
      messages = {
        view = "split",  -- Use split buffer instead of floating window
      },
      split = {
        backend = "split",
        relative = "editor",
        position = "bottom",
        size = "20%",
        close = {
          keys = { "q", "<Esc>" },
        },
        win_options = {
          wrap = true,
          linebreak = true,
          winhighlight = "Normal:Normal,FloatBorder:Normal",
          scrolloff = 0,  -- Allow cursor at very bottom
          cursorline = false,  -- Don't highlight cursor line
        },
        -- Keep cursor at the last line
        enter = true,
        -- Force scroll to bottom on open
        focus = true,
      },
      notify = {
        replace = true,
        merge = true,
        win_options = {
          wrap = true,
          linebreak = true,
        },
        size = {
          max_width = math.floor(vim.o.columns * 0.75),
          max_height = math.floor(vim.o.lines * 0.5),
        },
      },
      popup = {
        backend = "popup",
        relative = "editor",
        focusable = false,
        enter = false,
        border = {
          style = "rounded",
          padding = { 0, 1 },
        },
        position = {
          row = "30%",
          col = "50%",
        },
        size = {
          width = "80%",
          height = "auto",
        },
        win_options = {
          wrap = true,
          linebreak = true,
          winblend = 0,
        },
      },
    },
    -- LSP configuration
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
        ["cmp.entry.get_documentation"] = true,
      },
      hover = {
        enabled = true,
        view = nil, -- Use default
        opts = {}, -- Use default
      },
      signature = {
        enabled = true,
        auto_open = {
          enabled = true,
          trigger = true,
          luasnip = true,
          throttle = 50,
        },
      },
      message = {
        enabled = true,
        view = "cmdline", -- Use cmdline for inline LSP messages
      },
    },
    -- Notification configuration
    notify = {
      enabled = false, -- Disabled: using split view instead of popups
    },
    -- Smart move - disabled to keep messages persistent
    smart_move = {
      enabled = false, -- Disabled: keep messages visible
    },
    -- Message configuration
    messages = {
      enabled = true,
      view = "split",  -- Use split view at bottom for all messages
      view_error = "split",  -- Errors in split
      view_warn = "split",  -- Warnings in split
      view_history = "split",  -- History in split
      view_search = "virtualtext",
    },
    -- Presets
    presets = {
      bottom_search = true, -- Use bottom search position
      command_palette = true, -- Position cmdline and popupmenu together
      long_message_to_split = true, -- Long messages will be sent to a split
      inc_rename = false, -- Disable inc-rename preset
      lsp_doc_border = true, -- Add border to hover docs and signature help
    },
    -- Routes to handle specific message types
    routes = {
      -- Skip LSP loading messages and deprecation warnings
      {
        filter = {
          any = {
            { find = "Using Nix%-provided" },
            { find = "Using system Nix" },
            { find = "LSP .* not available from Nix" },
            { find = "LSPs not available from Nix" },
            { find = "vim%.lsp%.buf_get_clients.*deprecated" },
            { find = "Run \":checkhealth vim%.deprecated\"" },
            { find = "%-%-  ?More  ?%-%-" },  -- Skip "-- More --" pagination messages
            { find = "Press ENTER or type command to continue" },  -- Skip press enter messages
          },
        },
        opts = { skip = true },
      },
      -- Skip presence.nvim notifications (all events)
      {
        filter = {
          any = {
            { event = "notify", find = "%[presence%.nvim%]" },
            { event = "msg_show", find = "%[presence%.nvim%]" },
            { find = "presence%.nvim" },
            { find = "Activity already set" },
          },
        },
        opts = { skip = true },
      },
      -- Hide common messages that aren't important (MUST come before general msg_show route)
      {
        filter = {
          event = "msg_show",
          any = {
            { find = "^%d+L, %d+B" },  -- File write messages
            { find = "; after #%d+" },  -- Undo messages
            { find = "; before #%d+" }, -- Redo messages
            { find = "^%d+ changes?;" }, -- More undo/redo messages
            { find = "^%d+ fewer lines" }, -- Line deletion messages
            { find = "^%d+ more lines" }, -- Line addition messages
            { find = "Already at oldest change" }, -- Undo limit reached
            { find = "Already at newest change" }, -- Redo limit reached
          },
        },
        opts = { skip = true },
      },
      -- Hide search count messages
      {
        filter = {
          event = "msg_show",
          kind = "search_count",
        },
        opts = { skip = true },
      },
      -- Skip quickfix navigation messages
      {
        filter = {
          event = "msg_show",
          any = {
            { find = "^%[Quickfix List%]" },
            { find = "%(location list%)" },
            { find = "^%d+ of %d+" }, -- "1 of 10" type messages
          },
        },
        opts = { skip = true },
      },
      -- Handle confirmation prompts explicitly (MUST come before empty message filter)
      {
        filter = {
          event = "msg_show",
          any = {
            { find = "Save changes" },
            { find = "%[Y%]es" },
            { find = "%[N%]o" },
            { find = "%[C%]ancel" },
          },
        },
        view = "mini",  -- Use mini view for confirmations
        opts = {
          timeout = false,  -- No auto-dismiss for confirmations
          replace = false,  -- Don't replace previous notifications
        },
      },
      -- TEMPORARILY DISABLED FOR DEBUGGING - Testing if this blocks confirmation prompts
      -- Skip empty or whitespace-only messages (fixes blank notifications from auto-save)
      -- {
      --   filter = {
      --     event = "msg_show",
      --     any = {
      --       { find = "^%s*$" }, -- Empty or whitespace-only
      --       { find = "^\".*\" %d+L, %d+B written$" }, -- Explicit write messages
      --     },
      --   },
      --   opts = { skip = true },
      -- },
      -- Show messages in split view (bottom messages)
      {
        filter = {
          event = "msg_show",
        },
        view = "split",  -- Use split view at bottom for all messages
      },
      -- Route LSP progress to notify (less intrusive)
      {
        filter = {
          event = "lsp",
          kind = "progress",
        },
        opts = { skip = true },  -- Skip LSP progress messages entirely
      },
      -- Also skip LSP progress messages that come through msg_show (basedpyright and others)
      {
        filter = {
          event = "msg_show",
          any = {
            { find = "Finding references" },
            { find = "Indexing" },
            { find = "Loading" },
            { find = "Checking" },
            { find = "Analyzing" },
            { find = "Searching" },
            { find = "references for" },
            { find = "pyright" },
            { find = "basedpyright" },
          },
        },
        opts = { skip = true },
      },
      -- Skip LSP progress notifications (separate from msg_show)
      {
        filter = {
          event = "notify",
          any = {
            { find = "Finding references" },
            { find = "Indexing" },
            { find = "Loading" },
            { find = "Checking" },
            { find = "Analyzing" },
            { find = "Searching" },
            { find = "references for" },
            { find = "pyright" },
            { find = "basedpyright" },
          },
        },
        opts = { skip = true },
      },
    },
  },
}
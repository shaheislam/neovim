-- Consolidated fzf-lua configuration
-- Replaces telescope.nvim with feature parity for all custom workflows

-- State management for scope toggle and directory history
local original_bufnr = nil
local dir_history = {}
local history_index = 0
local current_scope = "Local"  -- Track current scope for header display

-- ===== Helper functions for directory-specific history =====

-- Get history file path for current directory and picker type
local function get_history_path(picker_type, cwd)
  -- Create history directory if it doesn't exist
  local history_dir = vim.fn.stdpath("data") .. "/fzf-lua-history"
  -- Use vim.loop (uv) for more reliable directory creation
  local ok = vim.loop.fs_mkdir(history_dir, 493) -- 493 = 0755 in octal
  if not ok and vim.fn.isdirectory(history_dir) == 0 then
    -- If single mkdir failed and dir doesn't exist, try creating parent dirs
    vim.fn.system("mkdir -p " .. vim.fn.shellescape(history_dir))
  end

  -- Use provided cwd parameter or fall back to current directory
  cwd = cwd or vim.fn.getcwd()
  -- Replace path separators with double underscores for readability
  local safe_cwd = cwd:gsub("/", "__"):gsub("^__", ""):gsub(":", "")

  -- Optional: Include picker type in filename for separate histories
  local filename = picker_type and (safe_cwd .. "___" .. picker_type) or safe_cwd

  -- Limit filename length to avoid filesystem issues
  if #filename > 200 then
    -- Use hash for very long paths
    local hash = vim.fn.sha256(cwd)
    filename = hash:sub(1, 16) .. (picker_type and ("___" .. picker_type) or "")
  end

  return history_dir .. "/" .. filename
end

-- Extract search term from history entry (removes CWD prefix if present)
local function extract_search_from_entry(entry)
  -- Check if entry has CWD prefix
  local _, search = entry:match("^([^|]+)|(.+)$")
  if search then
    return search
  end
  -- Backward compatibility: return entry as-is if no prefix
  return entry
end

-- Extract CWD from history entry
local function extract_cwd_from_entry(entry)
  local cwd = entry:match("^([^|]+)|")
  return cwd
end

-- Post-process history file to add CWD prefixes
local function process_history_file(history_file, cwd)
  if vim.fn.filereadable(history_file) == 0 then
    return
  end

  -- Normalize CWD: remove trailing slashes for consistent comparison
  local normalized_cwd = cwd:gsub("/+$", "")

  local lines = {}
  local modified = false

  -- Read existing history
  for line in io.lines(history_file) do
    if line and #line > 0 then
      -- Check if line already has CWD prefix
      if not line:match("^/[^|]+|") then
        -- Add normalized CWD prefix
        table.insert(lines, normalized_cwd .. "|" .. line)
        modified = true
      else
        -- Normalize existing prefixed entries too
        local entry_cwd, search = line:match("^([^|]+)|(.+)$")
        if entry_cwd and search then
          local normalized_entry_cwd = entry_cwd:gsub("/+$", "")
          table.insert(lines, normalized_entry_cwd .. "|" .. search)
          if normalized_entry_cwd ~= entry_cwd then
            modified = true
          end
        else
          table.insert(lines, line)
        end
      end
    end
  end

  -- Write back if modified
  if modified then
    local file = io.open(history_file, "w")
    if file then
      for _, line in ipairs(lines) do
        file:write(line .. "\n")
      end
      file:close()
    end
  end
end

-- Ensure history file has CWD prefixes (called before reading for local scope)
-- This ensures unprefixed entries written by fzf during picker session get prefixed immediately
local function ensure_history_prefixed(history_file, cwd)
  if vim.fn.filereadable(history_file) == 0 then
    return
  end

  -- Normalize CWD: remove trailing slashes for consistent comparison
  local normalized_cwd = cwd:gsub("/+$", "")

  local lines = {}
  local modified = false

  -- Read existing history
  for line in io.lines(history_file) do
    if line and #line > 0 then
      -- Check if line already has CWD prefix
      if not line:match("^/[^|]+|") then
        -- Add normalized CWD prefix (unprefixed entries are from current session in this directory)
        table.insert(lines, normalized_cwd .. "|" .. line)
        modified = true
      else
        -- Keep prefixed entries as-is (already normalized by process_history_file)
        table.insert(lines, line)
      end
    end
  end

  -- Write back if modified
  if modified then
    local file = io.open(history_file, "w")
    if file then
      for _, line in ipairs(lines) do
        file:write(line .. "\n")
      end
      file:close()
    end
  end
end

return {
  -- fzf-lua main plugin
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "FzfLua",

    opts = function()
      local actions = require("fzf-lua.actions")

      -- ===== Custom action wrapper to handle cwd properly =====
      local function file_edit_with_cwd(selected, opts)
        if not selected or #selected == 0 then return end

        -- Get the cwd from opts
        local cwd = opts.cwd or vim.fn.getcwd()

        -- Process each selected file
        for _, entry in ipairs(selected) do
          -- Parse the entry to get the file path
          local path = require("fzf-lua.path")
          local file = path.entry_to_file(entry, opts)

          if file and file.path then
            -- Resolve the file path properly
            local filepath = file.path

            -- If path is relative, make it absolute using the picker's cwd
            if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
              filepath = cwd .. "/" .. filepath
            end

            -- Normalize the path (resolve .., ., etc.)
            filepath = vim.fn.fnamemodify(filepath, ":p")

            -- Open the file using safer API calls instead of string concatenation
            local success, err = pcall(function()
              -- Open the file using vim.cmd.edit for proper path handling
              vim.cmd.edit(filepath)

              -- Position cursor if line/col specified
              if file.line and file.line > 0 then
                local line = file.line
                local col = (file.col and file.col > 0) and (file.col - 1) or 0
                -- Use API to set cursor position (col is 0-indexed)
                vim.api.nvim_win_set_cursor(0, {line, col})
              end
            end)

            if not success then
              vim.notify(
                "Failed to open file: " .. vim.fn.fnamemodify(filepath, ":t") .. "\n" ..
                "Error: " .. tostring(err),
                vim.log.levels.WARN
              )
            end
          end
        end
      end

      -- ===== Helper Functions for Scope Toggle =====

      local function get_service_repo_dir()
        if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
          local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
          if ft == "oil" then
            local oil_dir = require("oil").get_current_dir(original_bufnr)
            if oil_dir then
              local git_root = vim.fs.find(".git", { path = oil_dir, upward = true })[1]
              if git_root then
                return vim.fn.fnamemodify(git_root, ":h")
              end
            end
          end
        end
        -- Find git root from current working directory (LazyVim-free approach)
        local git_root = vim.fs.find(".git", { path = vim.fn.getcwd(), upward = true })[1]
        if git_root then
          return vim.fn.fnamemodify(git_root, ":h")
        end
        return vim.fn.getcwd()  -- Fallback to current working directory if no git root found
      end

      local function get_local_dir()
        if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
          local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
          if ft == "oil" then
            local oil_dir = require("oil").get_current_dir(original_bufnr)
            if oil_dir then
              return oil_dir
            end
          end
        end
        return vim.fn.getcwd()
      end

      local function get_buffer_dir()
        if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
          local bufname = vim.api.nvim_buf_get_name(original_bufnr)
          if bufname and bufname ~= "" then
            local dir = vim.fn.fnamemodify(bufname, ":h")
            if dir and dir ~= "" then
              return dir
            end
          end
        end
        return vim.fn.getcwd()
      end

      local function get_parent_dir(cwd)
        -- Normalize path first - :p gives full path, :h removes trailing component
        local normalized = vim.fn.fnamemodify(cwd or vim.fn.getcwd(), ":p:h")
        -- Get parent of normalized path
        local parent = vim.fn.fnamemodify(normalized, ":h")
        if parent == normalized or parent == "" or parent == "." then
          vim.notify("Already at filesystem root", vim.log.levels.WARN)
          return nil
        end
        return parent
      end

      local function add_to_history(cwd, scope_name)
        if history_index > 0 and dir_history[history_index] then
          if dir_history[history_index].cwd == cwd then
            return
          end
        end

        for i = history_index + 1, #dir_history do
          dir_history[i] = nil
        end

        table.insert(dir_history, { cwd = cwd, scope_name = scope_name })
        history_index = #dir_history
      end

      -- ===== Scope Change Actions =====

      local function create_scope_action(new_cwd_fn, scope_name)
        return function(_, opts)
          local new_cwd = new_cwd_fn(opts)
          if not new_cwd then return end

          -- Initialize history on first scope change
          if #dir_history == 0 then
            local current_cwd = opts.cwd or vim.fn.getcwd()
            add_to_history(current_cwd, "Initial")
          end

          add_to_history(new_cwd, scope_name)
          current_scope = scope_name  -- Update current scope for header display

          -- Determine picker type from prompt
          local prompt = opts.prompt or ""
          local query = opts.__call_opts and opts.__call_opts.query or ""

          -- Relaunch appropriate picker with new scope
          vim.schedule(function()
            if prompt:match("Buffers") then
              require("fzf-lua").buffers({
                query = query,
                prompt = "Buffers (" .. scope_name .. ")> "
              })
            elseif prompt:match("Oldfiles") or prompt:match("Recent") then
              require("fzf-lua").oldfiles({
                cwd = new_cwd,
                query = query,
                prompt = "Recent Files (" .. scope_name .. ")> "
              })
            elseif prompt:match("Grep") or prompt:match("RG") then
              local cwd_full = vim.fn.fnamemodify(new_cwd, ":~")
              require("fzf-lua").live_grep({
                cwd = new_cwd,
                query = query,
                prompt = "Live Grep (" .. scope_name .. ")> ",
                winopts = {
                  title = " " .. cwd_full .. " ",
                },
                fzf_opts = {
                  ["--history"] = get_history_path("grep", new_cwd),
                }
              })
            else
              require("fzf-lua").files({
                cwd = new_cwd,
                query = query,
                prompt = "Find Files (" .. scope_name .. ")> "
              })
            end
          end)
        end
      end

      -- History navigation actions
      local function navigate_history(direction)
        return function(_, opts)
          if #dir_history == 0 then
            vim.notify("No directory history", vim.log.levels.WARN)
            return
          end

          local new_index = history_index + direction
          if new_index < 1 or new_index > #dir_history then
            vim.notify("At " .. (direction < 0 and "oldest" or "newest") .. " directory in history", vim.log.levels.WARN)
            return
          end

          history_index = new_index
          local entry = dir_history[history_index]
          current_scope = entry.scope_name  -- Update current scope for header display

          -- Relaunch picker without adding to history
          local prompt = opts.prompt or ""
          local query = opts.__call_opts and opts.__call_opts.query or ""

          vim.schedule(function()
            if prompt:match("Buffers") then
              require("fzf-lua").buffers({
                query = query,
                prompt = "Buffers (" .. entry.scope_name .. ")> "
              })
            elseif prompt:match("Oldfiles") or prompt:match("Recent") then
              require("fzf-lua").oldfiles({
                cwd = entry.cwd,
                query = query,
                prompt = "Recent Files (" .. entry.scope_name .. ")> "
              })
            elseif prompt:match("Grep") or prompt:match("RG") then
              local cwd_full = vim.fn.fnamemodify(entry.cwd, ":~")
              require("fzf-lua").live_grep({
                cwd = entry.cwd,
                query = query,
                prompt = "Live Grep (" .. entry.scope_name .. ")> ",
                winopts = {
                  title = " " .. cwd_full .. " ",
                },
                fzf_opts = {
                  ["--history"] = get_history_path("grep", entry.cwd),
                }
              })
            else
              require("fzf-lua").files({
                cwd = entry.cwd,
                query = query,
                prompt = "Find Files (" .. entry.scope_name .. ")> "
              })
            end
          end)
        end
      end

      -- Recursive folder browser using official fzf_exec pattern
      local function browse_folders(cwd, original_prompt, original_query, initial_call)
        local fzf_lua = require("fzf-lua")

        -- Initialize history on first call
        if initial_call and #dir_history == 0 then
          add_to_history(cwd, "Initial")
        end

        -- Build fd command with exclusions
        local fd_cmd = "fd --type d --exclude .git/objects --exclude .git/refs --exclude node_modules"

        -- Show current directory in prompt
        local cwd_full = vim.fn.fnamemodify(cwd, ":~")

        fzf_lua.fzf_exec(fd_cmd, {
          prompt = cwd_full .. " > ",
          cwd = cwd,
          actions = {
            ["default"] = function(selected)
              -- Enter: Navigate into selected folder (recursive)
              if not selected or #selected == 0 then return end
              -- selected[1] is clean path relative to cwd
              local selected_dir = selected[1]
              -- Properly join paths - fnamemodify with :p on cwd already adds trailing slash
              local abs_dir = vim.fn.fnamemodify(cwd, ":p") .. selected_dir

              -- Add to history when navigating into a directory
              add_to_history(abs_dir, "Browse")

              vim.schedule(function()
                browse_folders(abs_dir, original_prompt, original_query)
              end)
            end,
            ["ctrl-x"] = function(selected)
              -- Ctrl-x: Exit folder browser and open files/grep in selected directory
              if not selected or #selected == 0 then return end
              local selected_dir = selected[1]
              -- Properly join paths - fnamemodify with :p on cwd already adds trailing slash
              local abs_dir = vim.fn.fnamemodify(cwd, ":p") .. selected_dir

              vim.schedule(function()
                local cwd_full = vim.fn.fnamemodify(abs_dir, ":~")
                if original_prompt:match("Grep") or original_prompt:match("RG") then
                  fzf_lua.live_grep({
                    cwd = abs_dir,
                    query = original_query,
                    prompt = "Live Grep> ",
                    winopts = {
                      title = " " .. cwd_full .. " ",
                    },
                    fzf_opts = {
                      ["--history"] = get_history_path("grep", abs_dir),
                    }
                  })
                else
                  fzf_lua.files({
                    cwd = abs_dir,
                    query = original_query,
                    prompt = "Find Files> ",
                    fzf_opts = { ["--header"] = cwd_full }
                  })
                end
              end)
            end,
            ["alt-b"] = function()
              -- Navigate back in history
              if #dir_history == 0 then
                vim.notify("No directory history", vim.log.levels.WARN)
                return
              end

              if history_index > 1 then
                history_index = history_index - 1
                local entry = dir_history[history_index]

                vim.schedule(function()
                  browse_folders(entry.cwd, original_prompt, original_query)
                end)
              else
                vim.notify("At oldest directory in history", vim.log.levels.WARN)
              end
            end,
            ["alt-f"] = function()
              -- Navigate forward in history
              if #dir_history == 0 then
                vim.notify("No directory history", vim.log.levels.WARN)
                return
              end

              if history_index < #dir_history then
                history_index = history_index + 1
                local entry = dir_history[history_index]

                vim.schedule(function()
                  browse_folders(entry.cwd, original_prompt, original_query)
                end)
              else
                vim.notify("At newest directory in history", vim.log.levels.WARN)
              end
            end,
            ["alt-p"] = function()
              -- Navigate to parent directory
              local parent = get_parent_dir(cwd)
              if not parent then
                return
              end

              -- Add parent to history
              add_to_history(parent, "Parent")

              vim.schedule(function()
                browse_folders(parent, original_prompt, original_query)
              end)
            end
          }
        })
      end

      -- Directory selector action (now <M-o>)
      local function select_directory()
        return function(_, opts)
          local query = opts.__call_opts and opts.__call_opts.query or ""
          local current_picker_prompt = opts.prompt or ""
          local current_cwd = opts.cwd or vim.fn.getcwd()

          browse_folders(current_cwd, current_picker_prompt, query, true)
        end
      end

      -- ===== Search History Action =====

      -- Helper function to find all history files in the data directory
      local function get_all_history_files(picker_type)
        local history_dir = vim.fn.stdpath("data") .. "/fzf-lua-history"
        if vim.fn.isdirectory(history_dir) == 0 then
          return {}
        end

        local files = {}
        -- Use vim.loop (uv) to read directory
        local handle = vim.loop.fs_scandir(history_dir)
        if handle then
          while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then break end
            if type == "file" then
              -- Filter by picker type if specified
              if picker_type and name:match("___" .. picker_type .. "$") then
                table.insert(files, history_dir .. "/" .. name)
              elseif not picker_type or picker_type == "" then
                -- Include all files that don't have a picker type suffix
                if not name:match("___") then
                  table.insert(files, history_dir .. "/" .. name)
                end
              end
            end
          end
        end
        return files
      end

      -- Helper function to find history files within git repository
      local function get_git_repo_history_files(picker_type)
        local git_root = vim.fs.find(".git", { path = vim.fn.getcwd(), upward = true })[1]
        if not git_root then
          return {}
        end
        git_root = vim.fn.fnamemodify(git_root, ":h")

        local history_dir = vim.fn.stdpath("data") .. "/fzf-lua-history"
        if vim.fn.isdirectory(history_dir) == 0 then
          return {}
        end

        local files = {}
        -- Convert git root to safe filename pattern
        local safe_git_root = git_root:gsub("/", "__"):gsub("^__", ""):gsub(":", "")

        local handle = vim.loop.fs_scandir(history_dir)
        if handle then
          while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then break end
            if type == "file" then
              -- Check if this file belongs to a directory within the git repo
              if name:find(safe_git_root, 1, true) then
                if picker_type and name:match("___" .. picker_type .. "$") then
                  table.insert(files, history_dir .. "/" .. name)
                elseif not picker_type or picker_type == "" then
                  if not name:match("___") then
                    table.insert(files, history_dir .. "/" .. name)
                  end
                end
              end
            end
          end
        end
        return files
      end

      -- Helper function to aggregate history from multiple files
      local function aggregate_history_from_files(files)
        local all_history = {}
        local seen = {}

        -- Read all files and collect unique entries
        for _, file_path in ipairs(files) do
          if vim.fn.filereadable(file_path) == 1 then
            for line in io.lines(file_path) do
              if line and #line > 2 and not seen[line] then
                seen[line] = true
                table.insert(all_history, line)
              end
            end
          end
        end

        -- Sort by most recently used (this is a simple approach, could be enhanced)
        -- In practice, newer entries tend to be at the end of files
        local reversed = {}
        for i = #all_history, 1, -1 do
          table.insert(reversed, all_history[i])
        end

        return reversed
      end

      -- Store the last used opts for scope switching
      local last_history_opts = {}

      -- Function to search through picker history dynamically with fzf and scope support
      local function search_history_action(initial_scope)
        return function(_, opts)
          local prompt = opts.prompt or ""
          local current_cwd = opts.cwd or vim.fn.getcwd()

          -- Determine the actual local directory (could be Oil directory)
          local local_cwd = get_local_dir()  -- This respects Oil context

          -- Determine picker type from multiple sources
          local picker_type = "default"

          -- First, try to detect from the command if available
          if opts.cmd then
            local cmd = tostring(opts.cmd)
            if cmd:match("fd") or cmd:match("find") then
              picker_type = "files"
            elseif cmd:match("rg") or cmd:match("grep") then
              picker_type = "grep"
            end
          end

          -- Then try prompt detection with case-insensitive matching
          local prompt_lower = prompt:lower()
          if prompt_lower:match("find") or prompt_lower:match("files") then
            picker_type = "files"
          elseif prompt_lower:match("grep") or prompt_lower:match("rg") or prompt_lower:match("search") then
            picker_type = "grep"
          elseif prompt_lower:match("buffer") then
            picker_type = "buffers"
          elseif prompt_lower:match("recent") or prompt_lower:match("oldfile") or prompt_lower:match("history") then
            picker_type = "oldfiles"
          elseif prompt_lower:match("git") then
            if prompt_lower:match("file") then
              picker_type = "git_files"
            elseif prompt_lower:match("buffer") and prompt_lower:match("commit") then
              picker_type = "git_bcommits"
            elseif prompt_lower:match("commit") then
              picker_type = "git_commits"
            elseif prompt_lower:match("branch") then
              picker_type = "git_branches"
            elseif prompt_lower:match("stash") then
              picker_type = "git_stash"
            end
          elseif prompt_lower:match("lsp") then
            if prompt_lower:match("reference") then
              picker_type = "lsp_references"
            elseif prompt_lower:match("definition") then
              picker_type = "lsp_definitions"
            elseif prompt_lower:match("implementation") then
              picker_type = "lsp_implementations"
            elseif prompt_lower:match("document") and prompt_lower:match("symbol") then
              picker_type = "lsp_doc_symbols"
            elseif prompt_lower:match("workspace") and prompt_lower:match("symbol") then
              picker_type = "lsp_workspace_symbols"
            else
              picker_type = "lsp_symbols"
            end
          end

          -- Additional detection from opts fields
          if picker_type == "default" then
            -- Check for specific options that identify the picker
            if opts.fd_opts or opts.find_opts then
              picker_type = "files"
            elseif opts.rg_opts or opts.grep_opts then
              picker_type = "grep"
            elseif opts.show_all_buffers ~= nil then
              picker_type = "buffers"
            elseif opts.include_current_session ~= nil then
              picker_type = "oldfiles"
            end
          end

          -- Start with provided scope or default to local
          local current_scope = initial_scope or "local"
          -- Debug: Show what scope we're starting with (uncomment for debugging)
          -- vim.notify("Starting history search with scope: " .. current_scope, vim.log.levels.INFO)

          -- Ensure local history file is prefixed before reading (critical for local scope)
          -- This handles unprefixed entries written by fzf during the current picker session
          if picker_type and picker_type ~= "default" then
            local local_history_file = get_history_path(picker_type, local_cwd)
            ensure_history_prefixed(local_history_file, local_cwd)
          end

          -- Function to get history based on scope
          local function get_history_for_scope(scope, cwd)
            -- Use provided cwd parameter instead of calling getcwd()
            local git_root = vim.fs.find(".git", { path = cwd, upward = true })[1]
            if git_root then
              git_root = vim.fn.fnamemodify(git_root, ":h")
            end

            if scope == "local" then
              -- Normalize CWD first - remove trailing slashes before getting history path
              local normalized_cwd = cwd:gsub("/+$", "")

              -- Current directory only - read ONLY the history file for this exact directory
              local history_file = get_history_path(picker_type, normalized_cwd)

              -- Debug: Uncomment to see what file is being checked
              -- vim.notify("Local scope checking file: " .. history_file, vim.log.levels.INFO)
              -- vim.notify("For CWD: " .. normalized_cwd, vim.log.levels.INFO)

              if vim.fn.filereadable(history_file) == 0 then
                return {}
              end

              local all_history = {}
              local seen = {}

              -- Read ONLY the local history file for this directory
              for line in io.lines(history_file) do
                if line and #line > 2 then
                  local entry_cwd = extract_cwd_from_entry(line)
                  if entry_cwd then
                    -- Normalize entry CWD and compare
                    local normalized_entry_cwd = entry_cwd:gsub("/+$", "")
                    if normalized_entry_cwd == normalized_cwd then
                      -- Extract just the search term for display
                      local search_term = extract_search_from_entry(line)
                      if not seen[search_term] then
                        seen[search_term] = true
                        table.insert(all_history, search_term)
                      end
                    end
                    -- Skip entries from other directories (shouldn't be in this file, but be safe)
                  else
                    -- Defensive fallback: unprefixed entry found despite ensure_history_prefixed
                    -- Treat as belonging to current directory (this file should be for current dir)
                    if not seen[line] then
                      seen[line] = true
                      table.insert(all_history, line)
                    end
                  end
                end
              end

              -- Reverse to show most recent first
              local reversed = {}
              for i = #all_history, 1, -1 do
                table.insert(reversed, all_history[i])
              end
              return reversed

            elseif scope == "service" then
              -- All directories in git repository
              local files = get_git_repo_history_files(picker_type)
              if #files == 0 then
                return {}
              end

              local all_history = {}
              local seen = {}

              -- Read all files and filter to entries within the git repo
              for _, file_path in ipairs(files) do
                if vim.fn.filereadable(file_path) == 1 then
                  for line in io.lines(file_path) do
                    if line and #line > 2 then
                      local entry_cwd = extract_cwd_from_entry(line)
                      if entry_cwd and git_root then
                        -- Check if entry is from within the current git repository
                        if entry_cwd:find(git_root, 1, true) == 1 then
                          local search_term = extract_search_from_entry(line)
                          if not seen[search_term] then
                            seen[search_term] = true
                            table.insert(all_history, search_term)
                          end
                        end
                      elseif not entry_cwd then
                        -- Backward compatibility: unprefixed entries
                        -- History files are already filtered to git repo, so unprefixed entries belong here
                        if not seen[line] then
                          seen[line] = true
                          table.insert(all_history, line)
                        end
                      end
                    end
                  end
                end
              end

              -- Reverse to show most recent first
              local reversed = {}
              for i = #all_history, 1, -1 do
                table.insert(reversed, all_history[i])
              end
              return reversed

            elseif scope == "global" then
              -- All history files - extract search terms without CWD prefix
              local files = get_all_history_files(picker_type)
              if #files == 0 then
                return {}
              end

              local all_history = {}
              local seen = {}

              -- Read all files and extract search terms
              for _, file_path in ipairs(files) do
                if vim.fn.filereadable(file_path) == 1 then
                  for line in io.lines(file_path) do
                    if line and #line > 2 then
                      local search_term = extract_search_from_entry(line)
                      if not seen[search_term] then
                        seen[search_term] = true
                        table.insert(all_history, search_term)
                      end
                    end
                  end
                end
              end

              -- Reverse to show most recent first
              local reversed = {}
              for i = #all_history, 1, -1 do
                table.insert(reversed, all_history[i])
              end
              return reversed
            end

            return {}
          end

          -- Function to refresh history display
          local function refresh_history_display(scope, cwd)
            current_scope = scope

            -- Get history for current scope
            local history_lines = get_history_for_scope(scope, cwd)

            -- Remove duplicates while preserving order (most recent occurrence)
            local seen = {}
            local unique_history = {}
            for _, line in ipairs(history_lines) do
              if not seen[line] and line and #line > 2 then
                seen[line] = true
                table.insert(unique_history, line)
              end
            end

            if #unique_history == 0 then
              -- Return a message instead of nil to allow scope switching to continue
              return { "[No " .. scope .. " history found for " .. picker_type .. "]" }
            end

            return unique_history
          end

          -- Get initial history using the correct directory for local scope
          local unique_history = refresh_history_display("local", local_cwd)
          if not unique_history then
            unique_history = { "[No local history found for " .. picker_type .. "]" }
          end

          -- Create header text
          local function make_header(scope)
            return "Mode: " .. scope .. " | C-d: local | C-s: service/git | C-g: global | C-e: delete | C-c: clear"
          end

          -- Store opts for scope switching
          last_history_opts = opts

          -- Helper function to launch history with a specific scope
          local function launch_history_with_scope(scope, cwd)
            -- Use the appropriate directory for each scope
            local scope_cwd
            if scope == "local" then
              scope_cwd = local_cwd  -- Use the Oil/local directory
            elseif scope == "service" then
              scope_cwd = get_service_repo_dir() or current_cwd  -- Use git root
            else
              scope_cwd = cwd  -- Use provided cwd for global
            end

            local history = refresh_history_display(scope, scope_cwd)
            if history then
              require('fzf-lua').fzf_exec(history, {
                prompt = "Search History (" .. picker_type .. " - " .. scope .. ")> ",
                fzf_opts = {
                  ["--header"] = make_header(scope),
                },
                actions = {
                  ["default"] = function(selected)
                    if not selected or #selected == 0 then return end
                    local query = selected[1]

                    -- Don't launch picker for placeholder messages
                    if query:match("^%[No .* history found") then
                      return
                    end

                    -- Re-launch the original picker with the selected query
                    vim.schedule(function()
                      local cwd_full = vim.fn.fnamemodify(scope_cwd, ":~")
                      if picker_type == "files" then
                        require('fzf-lua').files({ query = query, cwd = scope_cwd })
                      elseif picker_type == "grep" then
                        require('fzf-lua').live_grep({
                          query = query,
                          cwd = scope_cwd,
                          winopts = {
                            title = " " .. cwd_full .. " ",
                          },
                          fzf_opts = {
                            ["--history"] = get_history_path("grep", scope_cwd),
                          }
                        })
                      elseif picker_type == "buffers" then
                        require('fzf-lua').buffers({ query = query })
                      elseif picker_type == "oldfiles" then
                        require('fzf-lua').oldfiles({ query = query, cwd = scope_cwd })
                      elseif picker_type == "git_files" then
                        require('fzf-lua').git_files({ query = query })
                      elseif picker_type == "git_commits" then
                        require('fzf-lua').git_commits({ query = query })
                      elseif picker_type == "git_bcommits" then
                        require('fzf-lua').git_bcommits({ query = query })
                      elseif picker_type == "git_branches" then
                        require('fzf-lua').git_branches({ query = query })
                      elseif picker_type == "git_stash" then
                        require('fzf-lua').git_stash({ query = query })
                      elseif picker_type == "lsp_references" then
                        require('fzf-lua').lsp_references({ query = query })
                      elseif picker_type == "lsp_definitions" then
                        require('fzf-lua').lsp_definitions({ query = query })
                      elseif picker_type == "lsp_implementations" then
                        require('fzf-lua').lsp_implementations({ query = query })
                      elseif picker_type == "lsp_doc_symbols" then
                        require('fzf-lua').lsp_document_symbols({ query = query })
                      elseif picker_type == "lsp_workspace_symbols" then
                        require('fzf-lua').lsp_workspace_symbols({ query = query })
                      elseif picker_type == "lsp_symbols" then
                        require('fzf-lua').lsp_symbols({ query = query })
                      else
                        -- Fallback to files picker
                        require('fzf-lua').files({ query = query, cwd = scope_cwd })
                      end
                    end)
                  end,
                  ["ctrl-d"] = function()
                    vim.cmd("stopinsert")
                    vim.schedule(function()
                      launch_history_with_scope("local", cwd)
                    end)
                  end,
                  ["ctrl-s"] = function()
                    vim.cmd("stopinsert")
                    vim.schedule(function()
                      launch_history_with_scope("service", cwd)
                    end)
                  end,
                  ["ctrl-g"] = function()
                    vim.cmd("stopinsert")
                    vim.schedule(function()
                      launch_history_with_scope("global", cwd)
                    end)
                  end,
                  ["ctrl-e"] = function(selected)
                    -- Edit functionality (only for local scope)
                    if not selected or #selected == 0 then return end
                    local query_to_remove = selected[1]

                    if query_to_remove:match("^%[No .* history found") then
                      return
                    end

                    if scope ~= "local" then
                      vim.notify("Can only edit local history. Switch to local mode (Ctrl-d) first.", vim.log.levels.WARN)
                      return
                    end

                    -- Get local history file using the correct scope_cwd
                    local history_file = get_history_path(picker_type, scope_cwd)

                    -- Read the file and remove the matching entry
                    local new_lines = {}
                    if vim.fn.filereadable(history_file) == 1 then
                      for line in io.lines(history_file) do
                        if line and #line > 0 then
                          local entry_cwd = extract_cwd_from_entry(line)
                          local search_term = extract_search_from_entry(line)

                          -- Keep the line if it's either:
                          -- 1. From a different directory
                          -- 2. Has a different search term
                          if entry_cwd and entry_cwd ~= scope_cwd then
                            -- Different directory, keep it
                            table.insert(new_lines, line)
                          elseif search_term ~= query_to_remove then
                            -- Same directory but different search, keep it
                            table.insert(new_lines, line)
                          end
                          -- Otherwise, skip the line (it's the one we want to remove)
                        end
                      end
                    end

                    -- Write back to file
                    local file = io.open(history_file, "w")
                    if file then
                      for _, line in ipairs(new_lines) do
                        file:write(line .. "\n")
                      end
                      file:close()
                      vim.notify("Removed from history: " .. query_to_remove, vim.log.levels.INFO)

                      -- Re-launch with same scope
                      vim.schedule(function()
                        launch_history_with_scope(scope, scope_cwd)
                      end)
                    else
                      vim.notify("Failed to update history file", vim.log.levels.ERROR)
                    end
                  end,
                  ["ctrl-c"] = function()
                    -- Clear functionality (only for local scope)
                    if scope ~= "local" then
                      vim.notify("Can only clear local history. Switch to local mode (Ctrl-d) first.", vim.log.levels.WARN)
                      return
                    end

                    local confirm = vim.fn.confirm(
                      "Clear local history for " .. picker_type .. " in current directory?",
                      "&Yes\n&No",
                      2
                    )
                    if confirm == 1 then
                      local history_file = get_history_path(picker_type, scope_cwd)

                      -- Read the file and keep only entries from other directories
                      local new_lines = {}
                      if vim.fn.filereadable(history_file) == 1 then
                        for line in io.lines(history_file) do
                          if line and #line > 0 then
                            local entry_cwd = extract_cwd_from_entry(line)
                            -- Keep entries from other directories
                            if entry_cwd and entry_cwd ~= scope_cwd then
                              table.insert(new_lines, line)
                            end
                          end
                        end
                      end

                      -- Write back to file (will be empty if all entries were from current dir)
                      local file = io.open(history_file, "w")
                      if file then
                        for _, line in ipairs(new_lines) do
                          file:write(line .. "\n")
                        end
                        file:close()
                        vim.notify("Cleared local history for " .. picker_type .. " in " .. vim.fn.fnamemodify(scope_cwd, ":~"), vim.log.levels.INFO)
                      else
                        vim.notify("Failed to clear history", vim.log.levels.ERROR)
                      end
                    end
                  end
                },
                winopts = {
                  height = 0.4,
                  width = 0.6,
                },
              })
            end
          end

          -- Launch initial history with current scope
          launch_history_with_scope(current_scope, current_cwd)
        end
      end

      -- ===== Main Configuration =====

      return {
        -- Global options
        global_resume = true,
        global_resume_query = true,

        -- Global fzf options - including history file for search persistence
        fzf_opts = {
          -- Default history path (will be overridden per-picker below)
          -- Enable history for all pickers with PWD-based storage
          -- ctrl-p/ctrl-n will automatically work for history navigation
          ["--history"] = get_history_path("default"),
          -- Enable multi-selection with Tab/Shift-Tab
          ["--multi"] = true,
        },

        -- Global keymaps for fzf
        keymap = {
          fzf = {
            -- History navigation is automatically enabled when --history is set
            -- ctrl-p and ctrl-n will work by default for navigating history
            ["ctrl-f"] = "preview-up",        -- Scroll up (line by line)
            ["ctrl-d"] = "preview-down",      -- Scroll down (line by line)
            ["ctrl-b"] = "preview-page-up",   -- Page up
            ["ctrl-/"] = "toggle-preview",    -- Toggle preview on/off
            -- ["ctrl-u"] is now free for other uses
          },
        },

        winopts = {
          height = 0.85,
          width = 0.85,
          row = 0.35,
          col = 0.50,
          border = "rounded",
          preview = {
            layout = "horizontal",
            horizontal = "right:60%",
            scrollbar = "float",
          },
          on_create = function()
            -- Set up Tab key to toggle focus between search and preview only
            -- Get the FzfWin instance to access window IDs
            local win = require("fzf-lua.win")

            -- In terminal mode (fzf search buffer)
            vim.keymap.set("t", "<C-t>", function()
              local self = win.__SELF()
              if self and self.preview_winid and vim.api.nvim_win_is_valid(self.preview_winid) then
                vim.cmd("stopinsert")  -- Exit insert mode in terminal
                vim.api.nvim_set_current_win(self.preview_winid)  -- Switch directly to preview
              end
            end, { buffer = true, silent = true })

            -- Set up Tab in normal mode for preview window
            -- This gets applied when we switch to the preview buffer
            vim.api.nvim_create_autocmd("WinEnter", {
              callback = function()
                local self = win.__SELF()
                if not self then return end

                local current_win = vim.api.nvim_get_current_win()
                -- Check if we're in the preview window
                if self.preview_winid and current_win == self.preview_winid then
                  local preview_buf = vim.api.nvim_win_get_buf(current_win)

                  -- Ctrl-t: Switch back to search
                  vim.keymap.set("n", "<C-t>", function()
                    if self.fzf_winid and vim.api.nvim_win_is_valid(self.fzf_winid) then
                      vim.api.nvim_set_current_win(self.fzf_winid)  -- Switch directly to search
                      vim.cmd("startinsert")  -- Re-enter insert mode in terminal
                    end
                  end, { buffer = preview_buf, silent = true })

                  -- i: Make preview buffer editable and enter insert mode
                  vim.keymap.set("n", "i", function()
                    -- Get the currently previewed entry from the previewer
                    if not self._previewer or not self._previewer.last_entry then
                      vim.notify("No preview entry available", vim.log.levels.WARN)
                      return
                    end

                    local entry_str = self._previewer.last_entry

                    -- Use fzf-lua's path module to parse the entry
                    local path = require("fzf-lua.path")
                    local entry = path.entry_to_file(entry_str, self._o)

                    if not entry or not entry.path then
                      vim.notify("Could not extract file path from entry", vim.log.levels.WARN)
                      return
                    end

                    local file_path = entry.path

                    -- Make the preview buffer editable
                    vim.bo[preview_buf].modifiable = true
                    vim.bo[preview_buf].readonly = false

                    -- Set the buffer name to the file path so it can be saved
                    vim.api.nvim_buf_set_name(preview_buf, file_path)

                    -- Mark as modified so user knows they need to save
                    vim.bo[preview_buf].modified = false

                    -- Enter insert mode
                    vim.cmd("startinsert")
                  end, { buffer = preview_buf, silent = true, desc = "Edit in preview buffer" })
                end
              end,
            })
          end,
        },

        -- File ignore patterns (matching telescope config)
        files = {
          prompt = "Find Files> ",
          fd_opts = "--color=never --type f --hidden --follow --exclude .git --exclude node_modules --exclude dist --exclude '*.lock' --exclude package-lock.json --exclude yarn.lock --exclude '*.log' --exclude '*.cache' --exclude '*.min.js' --exclude '*.min.css'",
          -- PWD-based history for file picker (evaluated dynamically)
          fzf_opts = function()
            return {
              ["--history"] = get_history_path("files"),
              ["--header"] = "C-y: copy path | C-f: copy full path | C-r: history | M-g/s/l/d/p: scope | M-o: browse",
            }
          end,
          actions = {
            ["default"] = file_edit_with_cwd,  -- Custom action to handle cwd properly
            ["alt-g"] = create_scope_action(function() return vim.fn.expand("~/work") end, "Global"),
            ["alt-s"] = create_scope_action(function()
              local git_root = get_service_repo_dir()
              local repo_name = vim.fn.fnamemodify(git_root, ":t")
              return git_root
            end, "Git"),
            ["alt-l"] = create_scope_action(get_local_dir, "Local"),
            ["alt-d"] = create_scope_action(get_buffer_dir, "Buffer Dir"),
            ["alt-p"] = create_scope_action(function(opts)
              return get_parent_dir(opts.cwd)
            end, "Parent"),
            ["alt-b"] = navigate_history(-1),
            ["alt-n"] = navigate_history(1),
            ["alt-o"] = select_directory(),
            ["ctrl-r"] = search_history_action(),  -- Search history
            ["ctrl-y"] = function(selected, opts)
              if not selected or #selected == 0 then return end
              local path = require("fzf-lua.path")
              local file = path.entry_to_file(selected[1], opts)
              if file and file.path then
                -- Determine reference directory (Oil dir or picker's cwd)
                local ref_dir = opts.cwd or vim.fn.getcwd()

                -- Check if launched from Oil buffer
                if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                  local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                  if ft == "oil" then
                    local oil_dir = require("oil").get_current_dir(original_bufnr)
                    if oil_dir then
                      ref_dir = oil_dir
                    end
                  end
                end

                -- Make both absolute for comparison
                local abs_file = vim.fn.fnamemodify(file.path, ":p")
                local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                -- Calculate relative path
                local rel_path
                if abs_file:find(abs_ref, 1, true) == 1 then
                  rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                else
                  rel_path = abs_file  -- Fallback if outside ref_dir
                end

                vim.fn.setreg("+", rel_path)
              end
              return actions.resume(selected, opts)
            end,
            ["ctrl-f"] = function(selected, opts)
              if not selected or #selected == 0 then return end
              local path = require("fzf-lua.path")
              local file = path.entry_to_file(selected[1], opts)
              if file and file.path then
                -- Get the cwd from opts
                local cwd = opts.cwd or vim.fn.getcwd()
                local filepath = file.path

                -- If path is relative, make it absolute using the picker's cwd
                if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                  filepath = cwd .. "/" .. filepath
                end

                -- Normalize the path (resolve .., ., etc.)
                local abs_path = vim.fn.fnamemodify(filepath, ":p")
                vim.fn.setreg("+", abs_path)
              end
              return actions.resume(selected, opts)
            end,
          },
        },

        -- Live grep with advanced ripgrep support
        grep = {
          prompt = "Live Grep> ",
          input_prompt = "Grep For> ",
          rg_opts = "--column --line-number --no-heading --color=always --smart-case --max-columns=4096 --hidden --glob '!.git/*' --glob '!node_modules/*' --glob '!dist/*' --glob '!*.lock' --glob '!*.log' --glob '!*.cache' --glob '!*.min.js' --glob '!*.min.css'",
          -- PWD-based history for grep picker (evaluated dynamically)
          fzf_opts = function()
            return {
              ["--history"] = get_history_path("grep"),
              ["--header"] = "C-y: copy | C-f: copy full path | C-r: history | C-g: grep/lgrep | C-t: ignore | C-h: hidden",
            }
          end,
          actions = {
            ["default"] = file_edit_with_cwd,  -- Custom action to handle cwd properly
            ["alt-g"] = create_scope_action(function() return vim.fn.expand("~/work") end, "Global"),
            ["alt-s"] = create_scope_action(function()
              local git_root = get_service_repo_dir()
              local repo_name = vim.fn.fnamemodify(git_root, ":t")
              return git_root
            end, "Git"),
            ["alt-l"] = create_scope_action(get_local_dir, "Local"),
            ["alt-d"] = create_scope_action(get_buffer_dir, "Buffer Dir"),
            ["alt-p"] = create_scope_action(function(opts)
              return get_parent_dir(opts.cwd)
            end, "Parent"),
            ["alt-b"] = navigate_history(-1),
            ["alt-n"] = navigate_history(1),
            ["alt-o"] = select_directory(),
            -- Advanced grep controls
            ["ctrl-g"] = { actions.grep_lgrep },
            ["ctrl-r"] = search_history_action(),  -- Search history
            ["ctrl-t"] = { actions.toggle_ignore },
            ["ctrl-h"] = { actions.toggle_hidden },
            ["ctrl-y"] = function(selected, opts)
              if not selected or #selected == 0 then return end
              local path = require("fzf-lua.path")
              local file = path.entry_to_file(selected[1], opts)
              if file and file.path then
                -- Determine reference directory (Oil dir or picker's cwd)
                local ref_dir = opts.cwd or vim.fn.getcwd()

                -- Check if launched from Oil buffer
                if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                  local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                  if ft == "oil" then
                    local oil_dir = require("oil").get_current_dir(original_bufnr)
                    if oil_dir then
                      ref_dir = oil_dir
                    end
                  end
                end

                -- Make both absolute for comparison
                local abs_file = vim.fn.fnamemodify(file.path, ":p")
                local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                -- Calculate relative path
                local rel_path
                if abs_file:find(abs_ref, 1, true) == 1 then
                  rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                else
                  rel_path = abs_file  -- Fallback if outside ref_dir
                end

                vim.fn.setreg("+", rel_path)
              end
              return actions.resume(selected, opts)
            end,
            ["ctrl-f"] = function(selected, opts)
              if not selected or #selected == 0 then return end
              local path = require("fzf-lua.path")
              local file = path.entry_to_file(selected[1], opts)
              if file and file.path then
                -- Get the cwd from opts
                local cwd = opts.cwd or vim.fn.getcwd()
                local filepath = file.path

                -- If path is relative, make it absolute using the picker's cwd
                if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                  filepath = cwd .. "/" .. filepath
                end

                -- Normalize the path (resolve .., ., etc.)
                local abs_path = vim.fn.fnamemodify(filepath, ":p")
                vim.fn.setreg("+", abs_path)
              end
              return actions.resume(selected, opts)
            end,
          },
          -- Enable interactive ripgrep mode
          rg_glob = true,
          glob_flag = "--iglob",
          glob_separator = "%s%-%-",
        },

        -- Buffers
        buffers = {
          prompt = "Buffers> ",
          sort_mru = true,
          sort_lastused = true,
          show_all_buffers = true,
          -- PWD-based history for buffers picker (evaluated dynamically)
          fzf_opts = function()
            return {
              ["--history"] = get_history_path("buffers"),
              ["--header"] = "C-y: copy path | C-f: copy full path | C-d: delete | C-r: search history",
            }
          end,
          actions = {
            ["default"] = actions.buf_edit_or_qf,  -- Explicitly set default buffer open action
            ["alt-g"] = create_scope_action(function() return vim.fn.expand("~/work") end, "Global"),
            ["alt-s"] = create_scope_action(function()
              local git_root = get_service_repo_dir()
              return git_root
            end, "Git"),
            ["alt-l"] = create_scope_action(get_local_dir, "Local"),
            ["alt-d"] = create_scope_action(get_buffer_dir, "Buffer Dir"),
            ["alt-b"] = navigate_history(-1),
            ["alt-n"] = navigate_history(1),
            ["ctrl-d"] = { actions.buf_del, actions.resume },
            ["ctrl-r"] = search_history_action(),  -- Search history
            ["ctrl-y"] = function(selected, opts)
              if not selected or #selected == 0 then return end
              local path = require("fzf-lua.path")
              local file = path.entry_to_file(selected[1], opts)
              if file and file.path then
                -- Determine reference directory (Oil dir or picker's cwd)
                local ref_dir = opts.cwd or vim.fn.getcwd()

                -- Check if launched from Oil buffer
                if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                  local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                  if ft == "oil" then
                    local oil_dir = require("oil").get_current_dir(original_bufnr)
                    if oil_dir then
                      ref_dir = oil_dir
                    end
                  end
                end

                -- Make both absolute for comparison
                local abs_file = vim.fn.fnamemodify(file.path, ":p")
                local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                -- Calculate relative path
                local rel_path
                if abs_file:find(abs_ref, 1, true) == 1 then
                  rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                else
                  rel_path = abs_file  -- Fallback if outside ref_dir
                end

                vim.fn.setreg("+", rel_path)
              end
              return actions.resume(selected, opts)
            end,
            ["ctrl-f"] = function(selected, opts)
              if not selected or #selected == 0 then return end
              local path = require("fzf-lua.path")
              local file = path.entry_to_file(selected[1], opts)
              if file and file.path then
                -- Get the cwd from opts
                local cwd = opts.cwd or vim.fn.getcwd()
                local filepath = file.path

                -- If path is relative, make it absolute using the picker's cwd
                if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                  filepath = cwd .. "/" .. filepath
                end

                -- Normalize the path (resolve .., ., etc.)
                local abs_path = vim.fn.fnamemodify(filepath, ":p")
                vim.fn.setreg("+", abs_path)
              end
              return actions.resume(selected, opts)
            end,
          },
        },

        -- Oldfiles (Recent Files)
        oldfiles = {
          prompt = "Recent Files> ",
          cwd_only = false,
          include_current_session = true,
          -- PWD-based history for oldfiles picker (evaluated dynamically)
          fzf_opts = function()
            return {
              ["--history"] = get_history_path("oldfiles"),
            }
          end,
          actions = {
            ["default"] = file_edit_with_cwd,  -- Custom action to handle cwd properly
            ["alt-g"] = create_scope_action(function() return vim.fn.expand("~/work") end, "Global"),
            ["alt-s"] = create_scope_action(function()
              local git_root = get_service_repo_dir()
              return git_root
            end, "Git"),
            ["alt-l"] = create_scope_action(get_local_dir, "Local"),
            ["alt-d"] = create_scope_action(get_buffer_dir, "Buffer Dir"),
            ["alt-p"] = create_scope_action(function(opts)
              return get_parent_dir(opts.cwd)
            end, "Parent"),
            ["alt-b"] = navigate_history(-1),
            ["alt-n"] = navigate_history(1),
            ["ctrl-r"] = search_history_action(),  -- Search history
          },
        },

        -- Git integration
        git = {
          files = {
            prompt = "Git Files> ",
            -- PWD-based history for git files (evaluated dynamically)
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("git_files"),
                ["--header"] = "C-y: copy path | C-f: copy full path | C-r: search history",
              }
            end,
            actions = {
              ["ctrl-r"] = search_history_action(),  -- Search history
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          commits = {
            prompt = "Git Commits> ",
            preview = "git show --color {1}",
            -- PWD-based history for git commits (evaluated dynamically)
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("git_commits"),
                ["--header"] = "C-y: copy SHA | C-r: search history",
              }
            end,
            actions = {
              ["default"] = actions.git_checkout,
              ["ctrl-r"] = search_history_action(),  -- Search history
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local commit_sha = selected[1]:match("^([a-f0-9]+)")
                if commit_sha then
                  vim.fn.setreg("+", commit_sha)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          bcommits = {
            prompt = "Git Buffer Commits> ",
            preview = "git show --color {1}",
            -- PWD-based history for git buffer commits (evaluated dynamically)
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("git_bcommits"),
                ["--header"] = "C-y: copy SHA | C-r: search history",
              }
            end,
            actions = {
              ["default"] = actions.git_buf_edit,
              ["ctrl-r"] = search_history_action(),  -- Search history
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local commit_sha = selected[1]:match("^([a-f0-9]+)")
                if commit_sha then
                  vim.fn.setreg("+", commit_sha)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          branches = {
            prompt = "Git Branches> ",
            preview = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
            -- PWD-based history for git branches (evaluated dynamically)
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("git_branches"),
                ["--header"] = "C-y: copy branch | C-r: search history",
              }
            end,
            actions = {
              ["ctrl-r"] = search_history_action(),  -- Search history
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local branch = selected[1]:match("^%s*(%S+)")
                if branch then
                  vim.fn.setreg("+", branch)
                end
                return actions.resume(selected, opts)
              end,
              ["default"] = function(selected)
                if not selected or #selected == 0 then return end

                local branch = selected[1]:match("^%s*(%S+)")
                if not branch then
                  vim.notify("Could not extract branch name from: " .. selected[1], vim.log.levels.WARN)
                  return
                end

                -- Check for uncommitted changes
                local has_changes = vim.fn.system("bash -c 'git status --porcelain'"):match("%S")

                if has_changes then
                  local choice = vim.fn.confirm(
                    "You have uncommitted changes. What would you like to do?",
                    "&Stash and switch\n&Cancel",
                    1
                  )

                  if choice == 1 then
                    -- Stash changes with descriptive message
                    local stash_msg = string.format(
                      "WIP on %s before switching to %s",
                      vim.fn.system("bash -c 'git branch --show-current'"):gsub("\n", ""),
                      branch
                    )
                    vim.fn.system(string.format("bash -c \"git stash push -m '%s'\"", stash_msg))
                    vim.notify("Changes stashed: " .. stash_msg, vim.log.levels.INFO)

                    -- Switch branch
                    local result = vim.fn.system(string.format("bash -c 'git checkout %s'", branch))
                    if vim.v.shell_error == 0 then
                      vim.notify("Switched to branch: " .. branch, vim.log.levels.INFO)
                    else
                      vim.notify("Failed to switch branch: " .. result, vim.log.levels.ERROR)
                    end
                  end
                else
                  -- No changes, switch directly
                  local result = vim.fn.system(string.format("bash -c 'git checkout %s'", branch))
                  if vim.v.shell_error == 0 then
                    vim.notify("Switched to branch: " .. branch, vim.log.levels.INFO)
                  else
                    vim.notify("Failed to switch branch: " .. result, vim.log.levels.ERROR)
                  end
                end
              end,
            },
          },
          stash = {
            prompt = "Git Stash> ",
            preview = "git stash show --color -p {1}",
            -- PWD-based history for git stash (evaluated dynamically)
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("git_stash"),
                ["--header"] = "C-y: copy stash | C-x: drop | C-r: search history",
              }
            end,
            actions = {
              ["default"] = actions.git_stash_apply,
              ["ctrl-x"] = actions.git_stash_drop,
              ["ctrl-r"] = search_history_action(),  -- Search history
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local stash_ref = selected[1]:match("^(%S+)")
                if stash_ref then
                  vim.fn.setreg("+", stash_ref)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
        },

        -- LSP integration
        lsp = {
          symbols = {
            symbol_style = 1,
            -- PWD-based history for LSP symbols (evaluated dynamically)
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("lsp_symbols"),
                ["--header"] = "C-y: copy location | C-f: copy full path",
              }
            end,
            actions = {
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          -- Add history for other LSP pickers that might be used (evaluated dynamically)
          references = {
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("lsp_references"),
                ["--header"] = "C-y: copy location | C-f: copy full path",
              }
            end,
            actions = {
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          definitions = {
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("lsp_definitions"),
                ["--header"] = "C-y: copy location | C-f: copy full path",
              }
            end,
            actions = {
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          implementations = {
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("lsp_implementations"),
                ["--header"] = "C-y: copy location | C-f: copy full path",
              }
            end,
            actions = {
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          document_symbols = {
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("lsp_doc_symbols"),
                ["--header"] = "C-y: copy location | C-f: copy full path",
              }
            end,
            actions = {
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
          workspace_symbols = {
            fzf_opts = function()
              return {
                ["--history"] = get_history_path("lsp_workspace_symbols"),
                ["--header"] = "C-y: copy location | C-f: copy full path",
              }
            end,
            actions = {
              ["ctrl-y"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Determine reference directory (Oil dir or picker's cwd)
                  local ref_dir = opts.cwd or vim.fn.getcwd()

                  -- Check if launched from Oil buffer
                  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
                    local ft = vim.api.nvim_buf_get_option(original_bufnr, "filetype")
                    if ft == "oil" then
                      local oil_dir = require("oil").get_current_dir(original_bufnr)
                      if oil_dir then
                        ref_dir = oil_dir
                      end
                    end
                  end

                  -- Make both absolute for comparison
                  local abs_file = vim.fn.fnamemodify(file.path, ":p")
                  local abs_ref = vim.fn.fnamemodify(ref_dir, ":p")

                  -- Calculate relative path
                  local rel_path
                  if abs_file:find(abs_ref, 1, true) == 1 then
                    rel_path = abs_file:sub(#abs_ref + 1):gsub("^/", "")
                  else
                    rel_path = abs_file  -- Fallback if outside ref_dir
                  end

                  vim.fn.setreg("+", rel_path)
                end
                return actions.resume(selected, opts)
              end,
              ["ctrl-f"] = function(selected, opts)
                if not selected or #selected == 0 then return end
                local path = require("fzf-lua.path")
                local file = path.entry_to_file(selected[1], opts)
                if file and file.path then
                  -- Get the cwd from opts
                  local cwd = opts.cwd or vim.fn.getcwd()
                  local filepath = file.path

                  -- If path is relative, make it absolute using the picker's cwd
                  if not vim.startswith(filepath, "/") and not vim.startswith(filepath, "~") then
                    filepath = cwd .. "/" .. filepath
                  end

                  -- Normalize the path (resolve .., ., etc.)
                  local abs_path = vim.fn.fnamemodify(filepath, ":p")
                  vim.fn.setreg("+", abs_path)
                end
                return actions.resume(selected, opts)
              end,
            },
          },
        },

        -- Colorschemes picker with larger window
        colorschemes = {
          winopts = {
            height = 0.95,  -- Larger window for better preview
            width = 0.95,   -- Larger window for better preview
            row = 0.5,
            col = 0.5,
            preview = {
              layout = "horizontal",
              horizontal = "right:70%",  -- Give more space to preview for colorscheme
            },
          },
        },
      }
    end,

    config = function(_, opts)
      -- Store original buffer on picker launch
      local fzf = require("fzf-lua")
      local original_fns = {}

      -- Wrap all picker functions to capture original buffer and process history
      for name, fn in pairs(fzf) do
        if type(fn) == "function" and not name:match("^_") then
          original_fns[name] = fn
          fzf[name] = function(picker_opts, ...)
            original_bufnr = vim.api.nvim_get_current_buf()
            -- Capture CWD at picker open time (before any directory changes)
            local picker_cwd = (type(picker_opts) == "table" and picker_opts.cwd) or vim.fn.getcwd()

            -- Call the original function
            local result = original_fns[name](picker_opts, ...)

            -- Post-process history file after picker closes
            vim.defer_fn(function()
              -- Determine picker type for history file
              local picker_type = nil
              if name == "files" or name == "git_files" then
                picker_type = "files"
              elseif name == "live_grep" or name == "grep" or name == "grep_cword" or name == "grep_cWORD" or name == "grep_visual" then
                picker_type = "grep"
              elseif name == "buffers" then
                picker_type = "buffers"
              elseif name == "oldfiles" then
                picker_type = "oldfiles"
              elseif name:match("^git_") then
                picker_type = name
              elseif name:match("^lsp_") then
                picker_type = name
              end

              if picker_type then
                local history_file = get_history_path(picker_type, picker_cwd)
                process_history_file(history_file, picker_cwd)
              end
            end, 100) -- Small delay to ensure fzf has written to the file

            return result
          end
        end
      end

      -- Apply configuration
      fzf.setup(opts)

      -- Don't register with LazyVim.pick to avoid conflicts
      -- We use direct fzf-lua commands via keybindings instead
    end,

    keys = {
      -- File pickers
      { "<leader>ff", function() require("fzf-lua").files() end, desc = "Find Files" },
      { "<leader>fF", function() require("fzf-lua").files({ cwd = vim.fn.expand("~") }) end, desc = "Find Files (Home)" },

      -- Buffer pickers
      { "<leader>fb", function() require("fzf-lua").buffers({ prompt = "Buffers (Local)> " }) end, desc = "Buffers (with scope toggle)" },
      { "<leader>fB", function() require("fzf-lua").buffers({ prompt = "All Buffers> ", show_all_buffers = true }) end, desc = "All Buffers" },

      -- Recent files pickers
      {
        "<leader>fr",
        function()
          local cwd = vim.fn.getcwd()
          if vim.bo.filetype == "oil" then
            local oil_dir = require("oil").get_current_dir()
            if oil_dir then
              cwd = oil_dir
            end
          end
          require("fzf-lua").oldfiles({ cwd = cwd, prompt = "Recent Files (Local)> " })
        end,
        desc = "Recent Files (with scope toggle)"
      },
      { "<leader>fR", function() require("fzf-lua").oldfiles({ prompt = "Recent Files (Global)> " }) end, desc = "Recent Files (Global)" },

      -- Grep pickers
      { "<leader>fg", function()
        local cwd = vim.fn.getcwd()
        local cwd_full = vim.fn.fnamemodify(cwd, ":~")
        require("fzf-lua").live_grep({
          prompt = "Live Grep (" .. current_scope .. ")> ",
          winopts = {
            title = " " .. cwd_full .. " ",
          },
          fzf_opts = {
            ["--history"] = get_history_path("grep", cwd),
          },
          resume = false  -- Force fresh session with current directory
        })
      end, desc = "Live Grep with Args" },
      { "<leader>fG", function() require("fzf-lua").live_grep({ rg_opts = "--column --line-number --no-heading --color=always --smart-case --glob '!*test*' --glob '!*spec*' --glob '!*.min.*'" }) end, desc = "Live Grep (No Tests)" },
      { "<leader>fw", function() require("fzf-lua").grep_cword() end, desc = "Grep word under cursor" },
      { "<leader>fW", function() require("fzf-lua").grep_cWORD() end, desc = "Grep WORD under cursor" },
      { "<leader>fv", function() require("fzf-lua").grep_visual() end, mode = "v", desc = "Grep visual selection" },

      -- Git pickers
      { "<leader>gg", function() require("fzf-lua").git_status() end, desc = "Git status" },
      { "<leader>gl", function() require("fzf-lua").git_commits() end, desc = "Git commits" },
      { "<leader>gb", function() require("fzf-lua").git_branches() end, desc = "Git branches" },
      { "<leader>gf", function() require("fzf-lua").git_files() end, desc = "Git files" },
      { "<leader>gC", function() require("fzf-lua").git_bcommits() end, desc = "Git buffer commits" },
      { "<leader>gs", function() require("fzf-lua").git_stash() end, desc = "Git stash" },
      {
        "<leader>gx",
        function()
          require("fzf-lua").live_grep({
            prompt = "Git Conflicts> ",
            rg_opts = "--column --line-number --no-heading --color=always"
          })
        end,
        desc = "Find Git Conflicts"
      },

      -- DiffviewOpen pickers (multi-select with Tab, confirm with Enter)
      -- Flow: Pick ref(s) → Pick files to filter → Open Diffview
      {
        "<leader>gD",
        function()
          -- Helper to open Diffview with optional file filter
          local function open_with_filter(refs)
            local range_str
            if #refs == 1 then
              range_str = refs[1]
            elseif #refs >= 2 then
              range_str = refs[2] .. ".." .. refs[1]
            else
              return
            end

            -- Get list of changed files for the selection
            -- Single ref: files changed IN that commit (not vs working tree)
            -- Range: files changed between the two refs
            local diff_cmd = #refs == 1
              and string.format("git diff-tree --no-commit-id --name-only -r %s", refs[1])
              or string.format("git diff --name-only %s %s", refs[2], refs[1])
            local files = vim.fn.systemlist(diff_cmd)

            if #files == 0 then
              vim.cmd("DiffviewOpen " .. range_str)
              return
            end

            -- Show file picker for filtering
            require("fzf-lua").fzf_exec(files, {
              prompt = "Filter files (Tab=multi, Enter=open, Ctrl-A=all)> ",
              fzf_opts = { ["--multi"] = true },
              actions = {
                ["default"] = function(selected)
                  if selected and #selected > 0 then
                    -- Quote each path in case of spaces
                    local quoted_paths = {}
                    for _, path in ipairs(selected) do
                      table.insert(quoted_paths, vim.fn.shellescape(path))
                    end
                    vim.cmd("DiffviewOpen " .. range_str .. " -- " .. table.concat(quoted_paths, " "))
                  else
                    -- No selection, open all files
                    vim.cmd("DiffviewOpen " .. range_str)
                  end
                end,
                ["ctrl-a"] = function()
                  -- Explicit "open all files" action
                  vim.cmd("DiffviewOpen " .. range_str)
                end,
              },
            })
          end

          require("fzf-lua").git_commits({
            prompt = "Diffview Commits (Tab=multi, Enter=confirm)> ",
            fzf_opts = { ["--multi"] = true },
            actions = {
              ["default"] = function(selected)
                if not selected or #selected == 0 then return end
                local refs = {}
                for _, item in ipairs(selected) do
                  local hash = item:match("[a-f0-9]+")
                  if hash then table.insert(refs, hash) end
                end
                open_with_filter(refs)
              end,
            },
          })
        end,
        desc = "Diffview commit picker (multi-select)",
      },
      {
        "<leader>gB",
        function()
          -- Helper to open Diffview with optional file filter
          local function open_with_filter(refs)
            local range_str
            if #refs == 1 then
              range_str = refs[1]
            elseif #refs >= 2 then
              range_str = refs[2] .. ".." .. refs[1]
            else
              return
            end

            -- Get list of changed files for the selection
            -- Single ref: files changed IN that commit (not vs working tree)
            -- Range: files changed between the two refs
            local diff_cmd = #refs == 1
              and string.format("git diff-tree --no-commit-id --name-only -r %s", refs[1])
              or string.format("git diff --name-only %s %s", refs[2], refs[1])
            local files = vim.fn.systemlist(diff_cmd)

            if #files == 0 then
              vim.cmd("DiffviewOpen " .. range_str)
              return
            end

            -- Show file picker for filtering
            require("fzf-lua").fzf_exec(files, {
              prompt = "Filter files (Tab=multi, Enter=open, Ctrl-A=all)> ",
              fzf_opts = { ["--multi"] = true },
              actions = {
                ["default"] = function(selected)
                  if selected and #selected > 0 then
                    -- Quote each path in case of spaces
                    local quoted_paths = {}
                    for _, path in ipairs(selected) do
                      table.insert(quoted_paths, vim.fn.shellescape(path))
                    end
                    vim.cmd("DiffviewOpen " .. range_str .. " -- " .. table.concat(quoted_paths, " "))
                  else
                    -- No selection, open all files
                    vim.cmd("DiffviewOpen " .. range_str)
                  end
                end,
                ["ctrl-a"] = function()
                  -- Explicit "open all files" action
                  vim.cmd("DiffviewOpen " .. range_str)
                end,
              },
            })
          end

          require("fzf-lua").git_branches({
            prompt = "Diffview Branches (Tab=multi, Enter=confirm)> ",
            fzf_opts = { ["--multi"] = true },
            actions = {
              ["default"] = function(selected)
                if not selected or #selected == 0 then return end
                local refs = {}
                for _, item in ipairs(selected) do
                  local branch = item:gsub("^%s*%*?%s*", ""):match("^%S+")
                  if branch then table.insert(refs, branch) end
                end
                open_with_filter(refs)
              end,
            },
          })
        end,
        desc = "Diffview branch picker (multi-select)",
      },

      -- Undo history
      { "<leader>fu", function() require("fzf-lua").changes() end, desc = "Undo History" },

      -- Marks
      { "<leader>fm", function() require("fzf-lua").marks() end, desc = "Find marks" },

      -- Help and commands
      { "<leader>fh", function() require("fzf-lua").help_tags() end, desc = "Help Tags" },
      { "<leader>fc", function() require("fzf-lua").commands() end, desc = "Commands" },

      -- Resume last picker
      { "<leader>f<leader>", function() require("fzf-lua").resume() end, desc = "Resume last picker" },

      -- Quickfix list
      { "<leader>fq", function() require("fzf-lua").quickfix() end, desc = "Quickfix list" },

      -- FZF-Lua builtin picker with neoclip integration
      {
        "<leader>fz",
        function()
          local fzf = require("fzf-lua")

          -- Create custom builtin menu including neoclip
          fzf.fzf_exec(function(cb)
            -- Add standard fzf-lua builtins
            local builtins = {
              "files", "git_files", "grep", "live_grep", "grep_cword", "grep_cWORD",
              "buffers", "tabs", "lines", "blines",
              "tags", "btags", "marks", "jumps", "changes",
              "registers", "keymaps", "commands", "command_history",
              "help_tags", "man_pages", "colorschemes",
              "git_commits", "git_bcommits", "git_branches", "git_status", "git_stash",
              "lsp_references", "lsp_definitions", "lsp_declarations", "lsp_typedefs",
              "lsp_implementations", "lsp_document_symbols", "lsp_workspace_symbols",
              "diagnostics_document", "diagnostics_workspace",
              "oldfiles", "quickfix", "loclist",
            }

            for _, builtin in ipairs(builtins) do
              cb(builtin)
            end

            -- Add neoclip as a custom entry
            cb("yank_history")

            cb(nil)  -- Signal completion
          end, {
            prompt = "FZF-Lua Builtins> ",
            actions = {
              ["default"] = function(selected)
                if not selected or #selected == 0 then return end
                local choice = selected[1]

                -- Handle neoclip specially
                if choice == "yank_history" then
                  vim.schedule(function()
                    require("neoclip.fzf")()
                  end)
                else
                  -- Launch standard builtin
                  vim.schedule(function()
                    fzf[choice]()
                  end)
                end
              end
            }
          })
        end,
        desc = "FZF-Lua Builtin Pickers"
      },
    },
  },

  -- Zoxide integration with Oil.nvim
  -- Note: fzf-lua has built-in zoxide support, but we keep this for Oil integration
  {
    "nanotee/zoxide.vim",
    dependencies = { "ibhagwan/fzf-lua", "stevearc/oil.nvim" },
    keys = {
      {
        "<leader>cd",
        function()
          local home = vim.fn.expand("~")

          -- Determine preview command based on available tools
          local preview_cmd
          if vim.fn.executable("eza") == 1 then
            preview_cmd = "eza -la --color=always --icons -g --group-directories-first"
          elseif vim.fn.executable("lsd") == 1 then
            preview_cmd = "lsd -la --color=always --icon=always --group-directories-first --literal"
          else
            preview_cmd = "ls -la"
          end

          -- Recursive function to launch zoxide picker with optional query
          local function launch_zoxide_picker(initial_query)
            require("fzf-lua").zoxide({
              prompt = "Zoxide (Tab=fill, Enter=cd)> ",
              query = initial_query or "",
              -- Custom command that strips home directory for display
              cmd = "zoxide query --list --score | sed 's|" .. home .. "/||g'",
              -- Preview uses shell script to reconstruct full path
              preview = "bash -c 'path=$(echo {2..} | xargs); [[ \"$path\" != /* ]] && path=\"" .. home .. "/$path\"; " .. preview_cmd .. " \"$path\"'",
              winopts = {
                -- Override the global on_create to prevent Tab from toggling preview
                on_create = function()
                  -- Don't set up the Tab toggle for this picker
                  -- Tab will be handled by the fzf-lua action below
                end,
              },
              actions = {
                ["default"] = function(selected)
                  if not selected or #selected == 0 then return end
                  -- Extract the path (second field after tab or spaces)
                  local line = selected[1]
                  -- Try tab separator first, then space separator
                  local _, path = line:match("^(%s*%S+)\t(.+)$")
                  if not path then
                    _, path = line:match("^(%s*%S+)%s+(.+)$")
                  end
                  if not path then
                    vim.notify("Could not extract path from: " .. line, vim.log.levels.ERROR)
                    return
                  end

                  -- Reconstruct full path if it was transformed
                  if not path:match("^/") then
                    path = home .. "/" .. path
                  end

                  -- Change working directory
                  vim.cmd("cd " .. vim.fn.fnameescape(path))
                  -- Open oil in that directory
                  require("oil").open(path)
                end,
                ["tab"] = function(selected)
                  if not selected or #selected == 0 then return end
                  -- Extract the path (displayed value, not reconstructed full path)
                  local line = selected[1]
                  local _, path = line:match("^(%s*%S+)\t(.+)$")
                  if not path then
                    _, path = line:match("^(%s*%S+)%s+(.+)$")
                  end
                  if not path then
                    vim.notify("Could not extract path from: " .. line, vim.log.levels.ERROR)
                    return
                  end

                  -- Use the displayed path as-is for the query (don't reconstruct)
                  -- Add trailing slash to indicate we're navigating into this directory
                  local query = path .. "/"

                  -- Restart picker with selected path as query for further navigation
                  vim.schedule(function()
                    launch_zoxide_picker(query)
                  end)
                end
              }
            })
          end

          -- Launch initial picker
          launch_zoxide_picker()
        end,
        desc = "Zoxide jump to Oil"
      },
    },
  },

  -- Project management with fzf-lua integration
  {
    "ahmedkhalf/project.nvim",
    opts = {
      manual_mode = false,
      detection_methods = { "lsp", "pattern" },
      patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json", "Cargo.toml" },
      show_hidden = false,
      silent_chdir = true,
    },
    event = "VeryLazy",
    config = function(_, opts)
      require("project_nvim").setup(opts)
    end,
    keys = {
      {
        "<leader>fp",
        function()
          -- Use fzf-lua for project selection
          local project_nvim = require("project_nvim")
          local history = require("project_nvim.utils.history")
          local projects = history.get_recent_projects()

          require("fzf-lua").fzf_exec(projects, {
            prompt = "Projects> ",
            actions = {
              ["default"] = function(selected)
                if not selected or #selected == 0 then return end
                local project_path = selected[1]
                vim.cmd("cd " .. vim.fn.fnameescape(project_path))
                vim.notify("Changed to project: " .. project_path, vim.log.levels.INFO)
              end
            }
          })
        end,
        desc = "Projects"
      },

      -- DAP pickers (Debug Adapter Protocol integration)
      { "<leader>fdb", function() require("fzf-lua").dap_breakpoints() end, desc = "DAP Breakpoints" },
      { "<leader>fdc", function() require("fzf-lua").dap_commands() end, desc = "DAP Commands" },
      { "<leader>fdC", function() require("fzf-lua").dap_configurations() end, desc = "DAP Configurations" },
      { "<leader>fdv", function() require("fzf-lua").dap_variables() end, desc = "DAP Variables" },
      { "<leader>fdf", function() require("fzf-lua").dap_frames() end, desc = "DAP Frames" },
    },
  },

  -- Yank history with neoclip
  {
    "AckslD/nvim-neoclip.lua",
    dependencies = {
      "ibhagwan/fzf-lua",
      "kkharji/sqlite.lua",  -- Required for persistent history
    },
    opts = {
      default_register = '+',  -- Use system clipboard
      enable_persistent_history = true,
      keys = {
        fzf = {
          select = 'default',
          paste = 'ctrl-p',
          paste_behind = 'ctrl-k',
          custom = {},
        },
      },
    },
    config = function(_, opts)
      require("neoclip").setup(opts)
    end,
    keys = {
      {
        "<leader>fy",
        function()
          require("neoclip.fzf")()
        end,
        desc = "Yank History"
      },
    },
  },
}

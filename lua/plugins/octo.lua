-- GitHub integration with octo.nvim
-- Requires: gh CLI installed and authenticated (gh auth login)

local git_command = require("git.command")

local function run_gh(args)
  local cmd = { "gh" }
  vim.list_extend(cmd, args)
  if vim.system then
    local result = vim.system(cmd, { text = true, env = { MISE_QUIET = "1" } }):wait()
    local stdout = result.stdout or ""
    local stderr = result.stderr or ""
    return result.code == 0, vim.trim(stdout ~= "" and stdout or stderr)
  end

  local output = vim.fn.system(vim.list_extend({ "env", "MISE_QUIET=1" }, cmd))
  return vim.v.shell_error == 0, vim.trim(output or "")
end

return {
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "ibhagwan/fzf-lua",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    -- octo buffers only exist after :Octo (cmd trigger); completion in octo
    -- buffers is provided by blink-cmp-git, not by loading octo eagerly.
    -- ft handles session-restored octo buffers.
    ft = "octo",
    keys = {
      -- ══════════════════════════════════════════════════════════════
      -- NOTIFICATIONS (Inbox)
      -- ══════════════════════════════════════════════════════════════
      { "<leader>gon", "<cmd>Octo notification list<cr>", desc = "Notifications (inbox)" },

      -- ══════════════════════════════════════════════════════════════
      -- PULL REQUESTS & ISSUES
      -- ══════════════════════════════════════════════════════════════
      {
        "<leader>gop",
        function()
          if _G.octo_pr_picker then
            _G.octo_pr_picker()
          else
            vim.cmd("Octo pr list")
          end
        end,
        desc = "PRs & Issues hub (M-t entity | M-s state | M-m scope | M-u author | M-l label | M-f search | M-g global | M-k checks | CR open | ^o create | ^d diffview | ^x checkout | ^b browser)",
      },
      {
        "<leader>gok",
        function()
          -- Defer to the global set up in config; falls back to the buffer cmd
          if _G.octo_pr_checks then
            _G.octo_pr_checks()
          else
            vim.cmd("Octo pr checks")
          end
        end,
        desc = "PR checks (current branch CI)",
      },

      -- ══════════════════════════════════════════════════════════════
      -- CODE REVIEW
      -- ══════════════════════════════════════════════════════════════
      { "<leader>gor", "<cmd>Octo review start<cr>", desc = "Start review" },
      { "<leader>goR", "<cmd>Octo review resume<cr>", desc = "Resume review" },
      { "<leader>gos", "<cmd>Octo review submit<cr>", desc = "Submit review" },

      -- ══════════════════════════════════════════════════════════════
      -- QUICK ACTIONS
      -- ══════════════════════════════════════════════════════════════
      { "<leader>goA", "<cmd>Octo actions<cr>", desc = "Actions (all commands)" },
      { "<leader>gob", "<cmd>Octo repo browser<cr>", desc = "Open repo in browser" },
      { "<leader>goy", "<cmd>Octo repo url<cr>", desc = "Copy repo URL" },

      -- ══════════════════════════════════════════════════════════════
      -- DIFFVIEW INTEGRATION
      -- ══════════════════════════════════════════════════════════════
      {
        "<leader>god",
        function()
          -- Defer to global function set up in config
          if _G.octo_diffview and _G.octo_diffview.open_pr_in_diffview then
            _G.octo_diffview.open_pr_in_diffview()
          else
            vim.notify("Octo not loaded yet. Open a PR first.", vim.log.levels.WARN)
          end
        end,
        desc = "Open PR in DiffView",
      },
    },
    config = function()
      require("octo").setup({
        -- Use fzf-lua as picker (integrates with your existing setup)
        picker = "fzf-lua",

        -- Default remote to use
        default_remote = { "origin", "upstream" },

        -- SSH host aliases (maps SSH config hosts to actual GitHub hostname)
        -- Required because git remotes use github.com-dfe and github.com-personal
        ssh_aliases = {
          ["github.com-dfe"] = "github.com",
          ["github.com-personal"] = "github.com",
        },

        -- GitHub Enterprise support (if needed)
        -- github_hostname = "github.mycompany.com",

        -- UI settings
        ui = {
          use_signcolumn = true,
        },

        -- Issue/PR buffer settings
        issues = {
          order_by = {
            field = "UPDATED_AT",
            direction = "DESC",
          },
        },
        pull_requests = {
          order_by = {
            field = "UPDATED_AT",
            direction = "DESC",
          },
        },

        -- File panel (similar to diffview)
        file_panel = {
          size = 10,
          icons = true,
        },

        -- Mappings within octo buffers
        mappings = {
          issue = {
            close_issue = { lhs = "<leader>goic", desc = "Close issue" },
            reopen_issue = { lhs = "<leader>goio", desc = "Reopen issue" },
            list_issues = { lhs = "<leader>goil", desc = "List issues" },
            reload = { lhs = "<C-r>", desc = "Reload" },
            open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
            copy_url = { lhs = "<C-y>", desc = "Copy URL" },
            add_assignee = { lhs = "<leader>goaa", desc = "Add assignee" },
            remove_assignee = { lhs = "<leader>goad", desc = "Remove assignee" },
            add_label = { lhs = "<leader>gola", desc = "Add label" },
            remove_label = { lhs = "<leader>gold", desc = "Remove label" },
            goto_issue = { lhs = "<leader>gogi", desc = "Go to issue" },
            add_comment = { lhs = "<leader>goca", desc = "Add comment" },
            delete_comment = { lhs = "<leader>gocd", desc = "Delete comment" },
            react_hooray = { lhs = "<leader>gorp", desc = "React party" },
            react_heart = { lhs = "<leader>gorh", desc = "React heart" },
            react_eyes = { lhs = "<leader>gore", desc = "React eyes" },
            react_thumbs_up = { lhs = "<leader>gor+", desc = "React +1" },
            react_thumbs_down = { lhs = "<leader>gor-", desc = "React -1" },
            react_rocket = { lhs = "<leader>gorr", desc = "React rocket" },
            react_laugh = { lhs = "<leader>gorl", desc = "React laugh" },
            react_confused = { lhs = "<leader>gorc", desc = "React confused" },
          },
          pull_request = {
            checkout_pr = { lhs = "<leader>gopo", desc = "Checkout PR" },
            merge_pr = { lhs = "<leader>gopm", desc = "Merge PR" },
            squash_and_merge_pr = { lhs = "<leader>gops", desc = "Squash and merge" },
            rebase_and_merge_pr = { lhs = "<leader>gopr", desc = "Rebase and merge" },
            list_commits = { lhs = "<leader>gopc", desc = "List commits" },
            list_changed_files = { lhs = "<leader>gopf", desc = "List changed files" },
            show_pr_diff = { lhs = "<leader>gopd", desc = "Show PR diff" },
            add_reviewer = { lhs = "<leader>gova", desc = "Add reviewer" },
            remove_reviewer = { lhs = "<leader>govd", desc = "Remove reviewer" },
            close_issue = { lhs = "<leader>goic", desc = "Close PR" },
            reopen_issue = { lhs = "<leader>goio", desc = "Reopen PR" },
            reload = { lhs = "<C-r>", desc = "Reload" },
            open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
            copy_url = { lhs = "<C-y>", desc = "Copy URL" },
            add_assignee = { lhs = "<leader>goaa", desc = "Add assignee" },
            remove_assignee = { lhs = "<leader>goad", desc = "Remove assignee" },
            add_label = { lhs = "<leader>gola", desc = "Add label" },
            remove_label = { lhs = "<leader>gold", desc = "Remove label" },
            goto_issue = { lhs = "<leader>gogi", desc = "Go to issue" },
            add_comment = { lhs = "<leader>goca", desc = "Add comment" },
            delete_comment = { lhs = "<leader>gocd", desc = "Delete comment" },
            react_hooray = { lhs = "<leader>gorp", desc = "React party" },
            react_heart = { lhs = "<leader>gorh", desc = "React heart" },
            react_eyes = { lhs = "<leader>gore", desc = "React eyes" },
            react_thumbs_up = { lhs = "<leader>gor+", desc = "React +1" },
            react_thumbs_down = { lhs = "<leader>gor-", desc = "React -1" },
            react_rocket = { lhs = "<leader>gorr", desc = "React rocket" },
            react_laugh = { lhs = "<leader>gorl", desc = "React laugh" },
            react_confused = { lhs = "<leader>gorc", desc = "React confused" },
          },
          review_thread = {
            goto_issue = { lhs = "<leader>gogi", desc = "Go to issue" },
            add_comment = { lhs = "<leader>goca", desc = "Add comment" },
            add_suggestion = { lhs = "<leader>gosa", desc = "Add suggestion" },
            delete_comment = { lhs = "<leader>gocd", desc = "Delete comment" },
            next_comment = { lhs = "]c", desc = "Next comment" },
            prev_comment = { lhs = "[c", desc = "Prev comment" },
            select_next_entry = { lhs = "]q", desc = "Next changed file" },
            select_prev_entry = { lhs = "[q", desc = "Prev changed file" },
            select_first_entry = { lhs = "[Q", desc = "First changed file" },
            select_last_entry = { lhs = "]Q", desc = "Last changed file" },
            close_review_tab = { lhs = "<C-c>", desc = "Close review" },
            react_hooray = { lhs = "<leader>gorp", desc = "React party" },
            react_heart = { lhs = "<leader>gorh", desc = "React heart" },
            react_eyes = { lhs = "<leader>gore", desc = "React eyes" },
            react_thumbs_up = { lhs = "<leader>gor+", desc = "React +1" },
            react_thumbs_down = { lhs = "<leader>gor-", desc = "React -1" },
            react_rocket = { lhs = "<leader>gorr", desc = "React rocket" },
            react_laugh = { lhs = "<leader>gorl", desc = "React laugh" },
            react_confused = { lhs = "<leader>gorc", desc = "React confused" },
          },
          submit_win = {
            approve_review = { lhs = "<C-a>", desc = "Approve" },
            comment_review = { lhs = "<C-m>", desc = "Comment" },
            request_changes = { lhs = "<C-r>", desc = "Request changes" },
            close_review_tab = { lhs = "<C-c>", desc = "Close" },
          },
          review_diff = {
            submit_review = { lhs = "<leader>govs", desc = "Submit review" },
            discard_review = { lhs = "<leader>govd", desc = "Discard review" },
            add_review_comment = { lhs = "<leader>goca", desc = "Add comment" },
            add_review_suggestion = { lhs = "<leader>gosa", desc = "Add suggestion" },
            focus_files = { lhs = "<leader>goe", desc = "Focus files" },
            toggle_files = { lhs = "<leader>gof", desc = "Toggle files" },
            next_thread = { lhs = "]t", desc = "Next thread" },
            prev_thread = { lhs = "[t", desc = "Prev thread" },
            select_next_entry = { lhs = "]q", desc = "Next file" },
            select_prev_entry = { lhs = "[q", desc = "Prev file" },
            select_first_entry = { lhs = "[Q", desc = "First file" },
            select_last_entry = { lhs = "]Q", desc = "Last file" },
            close_review_tab = { lhs = "<C-c>", desc = "Close review" },
            toggle_viewed = { lhs = "<leader>gotv", desc = "Toggle viewed" },
            goto_file = { lhs = "gf", desc = "Go to file" },
          },
          file_panel = {
            submit_review = { lhs = "<leader>govs", desc = "Submit review" },
            discard_review = { lhs = "<leader>govd", desc = "Discard review" },
            next_entry = { lhs = "j", desc = "Next" },
            prev_entry = { lhs = "k", desc = "Prev" },
            select_entry = { lhs = "<cr>", desc = "Select" },
            refresh_files = { lhs = "R", desc = "Refresh" },
            focus_files = { lhs = "<leader>goe", desc = "Focus files" },
            toggle_files = { lhs = "<leader>gof", desc = "Toggle files" },
            select_next_entry = { lhs = "]q", desc = "Next file" },
            select_prev_entry = { lhs = "[q", desc = "Prev file" },
            select_first_entry = { lhs = "[Q", desc = "First file" },
            select_last_entry = { lhs = "]Q", desc = "Last file" },
            close_review_tab = { lhs = "<C-c>", desc = "Close review" },
            toggle_viewed = { lhs = "<leader>gotv", desc = "Toggle viewed" },
          },
          notification = {
            -- Note: Use <C-x> format for fzf-lua compatibility (not <cr>)
            read = { lhs = "<C-r>", desc = "Mark as read" },
            done = { lhs = "<C-d>", desc = "Mark as done" },
            unsubscribe = { lhs = "<C-u>", desc = "Unsubscribe" },
            open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
          },
        },
      })

      -- ════════════════════════════════════════════════════════════════
      -- Which-key group labels for Octo buffer-local keymaps
      -- Registers group names so pressing <leader> shows organized categories
      -- ════════════════════════════════════════════════════════════════
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "octo",
        callback = function(ev)
          local ok, wk = pcall(require, "which-key")
          if not ok then
            return
          end
          wk.add({
            { "<leader>gop", group = "PR ops", buffer = ev.buf },
            { "<leader>goi", group = "issue ops", buffer = ev.buf },
            { "<leader>gov", group = "review", buffer = ev.buf },
            { "<leader>goa", group = "assignee", buffer = ev.buf },
            { "<leader>gol", group = "label", buffer = ev.buf },
            { "<leader>gor", group = "reactions", buffer = ev.buf },
            { "<leader>goc", group = "comment", buffer = ev.buf },
            { "<leader>gos", group = "suggestion", buffer = ev.buf },
            { "<leader>got", group = "toggle", buffer = ev.buf },
            { "<leader>gog", group = "goto", buffer = ev.buf },
          })
        end,
      })

      -- ════════════════════════════════════════════════════════════════
      -- Octo + DiffView Integration
      -- Opens the current PR's changes in DiffView for visual diff navigation
      -- ════════════════════════════════════════════════════════════════

      ---Find an Octo PR buffer and extract PR metadata
      ---@return table|nil pr_info Table with {base, head, repo, number, state, headSha, mergeCommit} or nil
      local function get_octo_pr_info()
        -- Check if _G.octo_buffers exists
        if type(_G.octo_buffers) ~= "table" then
          return nil
        end

        -- First check current buffer, then search all Octo buffers
        local buffers_to_check = { vim.api.nvim_get_current_buf() }
        for bufnr, _ in pairs(_G.octo_buffers) do
          if bufnr ~= buffers_to_check[1] then
            table.insert(buffers_to_check, bufnr)
          end
        end

        for _, bufnr in ipairs(buffers_to_check) do
          local buffer = _G.octo_buffers[bufnr]
          if buffer and buffer.isPullRequest and buffer:isPullRequest() then
            local pr = buffer:pullRequest()
            if pr then
              -- Extract state and commit info
              local state = pr.state -- "OPEN", "CLOSED", "MERGED"
              local head_sha = pr.headRefOid -- The HEAD commit SHA
              local merge_commit = pr.mergeCommit and pr.mergeCommit.oid or nil

              return {
                base = pr.baseRefName,
                head = pr.headRefName,
                repo = buffer.repo,
                number = buffer.number,
                state = state,
                headSha = head_sha,
                mergeCommit = merge_commit,
                -- Full ref for remote tracking
                base_ref = "origin/" .. pr.baseRefName,
              }
            end
          end
        end

        return nil
      end

      ---Get current git branch name
      ---@return string|nil
      local function get_current_branch()
        local ok, result = git_command.output({ "rev-parse", "--abbrev-ref", "HEAD" })
        return ok and result or nil
      end

      ---Check if a git ref exists
      ---@param ref string
      ---@return boolean
      local function ref_exists(ref)
        return git_command.succeeds({ "rev-parse", "--verify", ref })
      end

      ---Get the current local repo's remote URL (normalized)
      ---@return string|nil
      local function get_local_repo_name()
        local ok, result = git_command.output({ "remote", "get-url", "origin" })
        if not ok then
          return nil
        end
        -- Normalize: extract owner/repo from various URL formats
        -- git@github.com:owner/repo.git or https://github.com/owner/repo.git
        -- Also handles git@github.com-alias:owner/repo.git
        local owner, repo = result:match("[:/]([^/]+)/([^/%.]+)%.?g?i?t?%s*$")
        if owner and repo then
          return owner .. "/" .. repo
        end
        return nil
      end

      ---Find a repo's local path by searching common directories
      ---@param repo_name string The repo name in "owner/repo" format
      ---@return string|nil The local path if found
      local function find_repo_local_path(repo_name)
        local owner, repo = repo_name:match("([^/]+)/(.+)")
        if not repo then
          return nil
        end

        -- Common directories to search (in order of preference)
        local search_dirs = {
          vim.fn.expand("~/work"),
          vim.fn.expand("~/code"),
          vim.fn.expand("~/projects"),
          vim.fn.expand("~/repos"),
          vim.fn.expand("~/dev"),
          vim.fn.expand("~"),
        }

        -- Try to find the repo directory
        for _, dir in ipairs(search_dirs) do
          if vim.fn.isdirectory(dir) == 1 then
            -- Check direct match: ~/work/repo-name
            local direct_path = dir .. "/" .. repo
            if vim.fn.isdirectory(direct_path .. "/.git") == 1 then
              -- Verify it's the right repo by checking remote
              local _, remote = git_command.output({ "remote", "get-url", "origin" }, { cwd = direct_path })
              if remote:lower():find(repo_name:lower(), 1, true) then
                return direct_path
              end
            end

            -- Check nested: ~/work/owner/repo-name
            local nested_path = dir .. "/" .. owner .. "/" .. repo
            if vim.fn.isdirectory(nested_path .. "/.git") == 1 then
              return nested_path
            end
          end
        end

        return nil
      end

      ---Open a PR in DiffView from explicit PR metadata (no Octo buffer required)
      ---@param pr_info table {base, head, repo, number, state, headSha}
      ---@param opts? {notify: boolean}
      local function open_pr_from_info(pr_info, opts)
        opts = opts or { notify = true }

        if not pr_info then
          return false
        end

        -- Register cleanup for temp-branch DiffView sessions. Shared by both
        -- the fetch and apply-diff paths for merged/closed PRs below.
        local function register_diffview_cleanup(original_branch, temp_branch, had_stash)
          _G.octo_diffview.cleanup = function()
            vim.cmd("DiffviewClose")
            git_command.run({ "checkout", original_branch })
            git_command.run({ "branch", "-D", temp_branch })
            if had_stash then
              git_command.run({ "stash", "pop" })
            end
            vim.notify("Cleaned up and restored to " .. original_branch, vim.log.levels.INFO)
          end

          vim.api.nvim_create_user_command("OctoDiffCleanup", function()
            if _G.octo_diffview.cleanup then
              _G.octo_diffview.cleanup()
            end
          end, { desc = "Clean up after Octo DiffView" })
        end

        -- Check if we're in the correct repo
        local local_repo = get_local_repo_name()
        if local_repo and pr_info.repo and local_repo:lower() ~= pr_info.repo:lower() then
          -- Try to find and cd to the correct repo
          local target_path = find_repo_local_path(pr_info.repo)
          if target_path then
            vim.notify(
              string.format("Switching to %s...", pr_info.repo),
              vim.log.levels.INFO
            )
            vim.cmd("cd " .. vim.fn.fnameescape(target_path))
          else
            if opts.notify then
              vim.notify(
                string.format(
                  "PR #%d is from '%s'\nbut you're in '%s'.\n\nRepo not found in ~/work, ~/code, ~/projects.",
                  pr_info.number,
                  pr_info.repo,
                  local_repo
                ),
                vim.log.levels.WARN
              )
            end
            return false
          end
        end

        local current_branch = get_current_branch()
        local base_ref = "origin/" .. pr_info.base
        local head_ref
        local state_info = ""

        -- For merged/closed PRs, use gh pr diff directly (most reliable)
        -- Original commits may not exist (squash merge) or PR ref may be garbage collected
        local is_merged_or_closed = pr_info.state == "MERGED" or pr_info.state == "CLOSED"
          or pr_info.state == "merged" or pr_info.state == "closed"

        if is_merged_or_closed then
          -- For merged PRs, use gh pr checkout to fetch the PR's commits from GitHub
          -- This is more reliable than git apply as it fetches actual commits
          vim.notify(
            string.format("PR #%d [%s] - fetching from GitHub...", pr_info.number, pr_info.state),
            vim.log.levels.INFO
          )

          -- Save current branch to return to later
          local original_branch = get_current_branch() or "main"

          -- Stash any uncommitted changes
          local had_stash = git_command.succeeds({ "stash", "push", "-m", "octo-diffview-temp" })

          -- Strategy: Use gh api to get PR head SHA, then fetch that commit
          -- This works even when refs/pull/{n}/head isn't available
          local temp_branch = string.format("octo-pr-%d", pr_info.number)
          local fetch_ok = false

          -- First, get the head SHA from GitHub API
          local head_sha = pr_info.headSha
          if not head_sha or head_sha == "" then
            -- Fetch from API if not in pr_info
            local api_ok, api_result = run_gh({ "api", "repos/" .. pr_info.repo .. "/pulls/" .. pr_info.number, "--jq", ".head.sha" })
            if api_ok then
              head_sha = api_result
            end
          end

          if head_sha and head_sha ~= "" then
            -- Try to fetch the specific commit
            -- First, try fetching with the commit SHA directly
            if git_command.succeeds({ "fetch", "origin", head_sha }) then
              -- Create branch from fetched commit
              fetch_ok = git_command.succeeds({ "branch", "-f", temp_branch, head_sha })
            end

            -- If that failed, try fetching via PR ref
            if not fetch_ok then
              if git_command.succeeds({ "fetch", "origin", "pull/" .. pr_info.number .. "/head" }) then
                fetch_ok = git_command.succeeds({ "branch", "-f", temp_branch, "FETCH_HEAD" })
              end
            end

            -- Last resort: fetch all and hope the commit is reachable
            if not fetch_ok then
              git_command.run({ "fetch", "origin" })
              if ref_exists(head_sha) then
                fetch_ok = git_command.succeeds({ "branch", "-f", temp_branch, head_sha })
              end
            end
          end

          if fetch_ok then
            -- Checkout the temp branch
            local checkout_result = git_command.run({ "checkout", temp_branch })

            if checkout_result.ok then
              -- Success! Now use DiffView
              local diff_cmd = string.format("DiffviewOpen origin/%s...HEAD", pr_info.base)
              vim.notify(
                string.format("PR #%d: %s → %s [%s]", pr_info.number, pr_info.base, pr_info.head, pr_info.state),
                vim.log.levels.INFO
              )
              vim.cmd(diff_cmd)

              -- Store cleanup info for later (user can run :OctoDiffCleanup)
              register_diffview_cleanup(original_branch, temp_branch, had_stash)

              return true
            end
          end

          -- Fetch/checkout failed - try applying the diff to create commits
          vim.notify(
            string.format("PR #%d: Commits unavailable, applying diff...", pr_info.number),
            vim.log.levels.INFO
          )

          -- Get the diff from GitHub
          local diff_ok, diff_output = run_gh({ "pr", "diff", tostring(pr_info.number), "--repo", pr_info.repo })

          if diff_ok and diff_output ~= "" then
            -- Checkout the base branch
            local checkout_base = git_command.run({ "checkout", "origin/" .. pr_info.base })
            if not checkout_base.ok then
              -- Try without origin/ prefix
              git_command.run({ "checkout", pr_info.base })
            end

            -- Create temp branch from base
            local checkout_temp = git_command.run({ "checkout", "-b", temp_branch })

            if checkout_temp.ok then
              -- Write diff to temp file and apply
              local temp_file = vim.fn.tempname() .. ".patch"
              local f = io.open(temp_file, "w")
              if f then
                f:write(diff_output)
                f:close()

                -- Apply the diff (--3way handles conflicts better)
                git_command.run({ "apply", "--3way", temp_file })
                vim.fn.delete(temp_file)

                -- Check if apply worked (may have partial success)
                local _, status = git_command.output({ "status", "--porcelain" })
                if status ~= "" then
                  -- Stage and commit all changes
                  git_command.run({ "add", "-A" })
                  local commit_result = git_command.run({ "commit", "-m", string.format("PR #%d: %s", pr_info.number, pr_info.head) })

                  if commit_result.ok then
                    -- Success! Open DiffView
                    local diff_cmd = string.format("DiffviewOpen origin/%s...HEAD", pr_info.base)
                    vim.notify(
                      string.format("PR #%d: %s → %s [%s] (applied)", pr_info.number, pr_info.base, pr_info.head, pr_info.state),
                      vim.log.levels.INFO
                    )
                    vim.cmd(diff_cmd)

                    -- Store cleanup
                    register_diffview_cleanup(original_branch, temp_branch, had_stash)

                    return true
                  end
                end
              end
            end
          end

          -- All methods failed - restore state and show scratch buffer
          git_command.run({ "checkout", original_branch })
          git_command.run({ "branch", "-D", temp_branch })
          if had_stash then
            git_command.run({ "stash", "pop" })
          end

          -- Fall back to scratch buffer
          vim.notify(
            string.format("PR #%d: Could not apply diff for DiffView. Showing raw diff...", pr_info.number),
            vim.log.levels.WARN
          )
          local fallback_ok, diff_output = run_gh({ "pr", "diff", tostring(pr_info.number), "--repo", pr_info.repo })

          if fallback_ok and diff_output ~= "" then
            vim.cmd("tabnew")
            local buf = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
            vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
            vim.api.nvim_buf_set_option(buf, "swapfile", false)
            vim.api.nvim_buf_set_name(buf, string.format("PR #%d diff [%s]", pr_info.number, pr_info.repo))
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff_output, "\n"))
            vim.api.nvim_buf_set_option(buf, "filetype", "diff")
            vim.api.nvim_buf_set_option(buf, "modifiable", false)
            return true
          else
            vim.notify(
              string.format("Could not fetch PR #%d. Refs may have been garbage collected.", pr_info.number),
              vim.log.levels.WARN
            )
            return false
          end
        end

        -- If we don't have head_ref yet, try the normal methods
        if not head_ref then
          if current_branch == pr_info.head then
            -- We're on the PR branch locally, use HEAD
            head_ref = "HEAD"
          elseif ref_exists("origin/" .. pr_info.head) then
            -- PR branch exists on origin (same-repo PR)
            head_ref = "origin/" .. pr_info.head
          else
            -- Fork PR or Dependabot - fetch using GitHub's PR ref
            -- GitHub exposes all PRs at refs/pull/{number}/head
            vim.notify(string.format("Fetching PR #%d from origin...", pr_info.number), vim.log.levels.INFO)

            local fetch_result = git_command.run({ "fetch", "origin", "pull/" .. pr_info.number .. "/head" })

            if not fetch_result.ok then
              -- Last resort: try using the head SHA if available
              if pr_info.headSha then
                vim.notify("Branch ref unavailable, using commit SHA...", vim.log.levels.INFO)
                -- Force fetch by SHA (may not work if commit is unreachable)
                git_command.run({ "fetch", "origin" })
                if ref_exists(pr_info.headSha) then
                  head_ref = pr_info.headSha
                end
              end

              if not head_ref then
                if opts.notify then
                  vim.notify(
                    string.format(
                      "PR #%d: Could not find branch or commit.\n"
                        .. "The PR may be from a deleted fork.\n"
                        .. "Head SHA: %s",
                      pr_info.number,
                      pr_info.headSha or "unknown"
                    ),
                    vim.log.levels.ERROR
                  )
                end
                return false
              end
            else
              -- Use FETCH_HEAD which now points to the PR
              head_ref = "FETCH_HEAD"
            end
          end
        end

        -- Build the diff command: base...head shows what the PR introduces
        local diff_cmd = string.format("DiffviewOpen %s...%s", base_ref, head_ref)

        if opts.notify then
          vim.notify(
            string.format("PR #%d: %s → %s%s", pr_info.number, pr_info.base, pr_info.head, state_info),
            vim.log.levels.INFO
          )
        end

        vim.cmd(diff_cmd)
        return true
      end

      ---Open current Octo PR in DiffView (resolves PR info from current buffer)
      ---@param opts? {notify: boolean}
      local function open_pr_in_diffview(opts)
        opts = opts or { notify = true }
        local pr_info = get_octo_pr_info()
        if not pr_info then
          if opts.notify then
            vim.notify("No Octo PR buffer found. Open a PR with :Octo pr list first.", vim.log.levels.WARN)
          end
          return false
        end
        return open_pr_from_info(pr_info, opts)
      end

      -- Expose for use in keymaps (used by the keys array above)
      _G.octo_diffview = {
        open_pr_in_diffview = open_pr_in_diffview,
        open_pr_from_info = open_pr_from_info,
        get_octo_pr_info = get_octo_pr_info,
      }

      -- ════════════════════════════════════════════════════════════════
      -- Monkey-patch: Add notification filtering to Octo picker
      -- Type filters: All, PRs, Issues, Discussions (alt-a/p/i/d)
      -- State filters: All, Open, Closed, Merged (alt-s/o/c/m) - PRs only
      -- ════════════════════════════════════════════════════════════════
      local fzf = require("fzf-lua")
      local gh = require("octo.gh")
      local entry_maker = require("octo.pickers.fzf-lua.entry_maker")
      local utils = require("octo.utils")
      local octo_notifications = require("octo.notifications")
      local headers = require("octo.gh.headers")
      local previewers = require("octo.pickers.fzf-lua.previewers")
      local fzf_actions = require("octo.pickers.fzf-lua.pickers.fzf_actions")
      local octo_config = require("octo.config")
      local picker_utils = require("octo.pickers.fzf-lua.pickers.utils")

      -- Persistent filter states across picker invocations
      local type_filter = "all" -- "all", "pull_request", "issue", "discussion"
      local state_filter = "all" -- "all", "open", "closed", "merged"

      -- Module-level cache for filter operations (avoids re-fetching on filter change)
      local notification_cache = {
        entries = {},     -- All notification entries from API
        pr_list = {},     -- PRs that need state fetching
        pr_states = {},   -- repo#number -> state mapping
        opts = nil,       -- Original opts passed to picker
      }

      -- Clear cache (call on fresh picker invocation)
      local function clear_notification_cache()
        notification_cache.entries = {}
        notification_cache.pr_list = {}
        notification_cache.pr_states = {}
        notification_cache.opts = nil
      end

      -- State display helpers
      local state_icons = {
        open = { icon = "●", hl = "OctoGreen", label = "Open" },
        closed = { icon = "●", hl = "OctoRed", label = "Closed" },
        merged = { icon = "●", hl = "OctoPurple", label = "Merged" },
      }

      -- Build GraphQL query for PR states using aliases
      local function build_pr_state_query(pr_list)
        local parts = { "query {" }
        for i, pr in ipairs(pr_list) do
          local owner, name = pr.repo:match("([^/]+)/(.+)")
          if owner and name then
            -- Create unique alias for each PR
            local alias = string.format("pr_%d", i)
            table.insert(parts, string.format(
              '  %s: repository(owner: "%s", name: "%s") { pullRequest(number: %d) { number state merged } }',
              alias, owner, name, pr.number
            ))
          end
        end
        table.insert(parts, "}")
        return table.concat(parts, "\n")
      end

      -- Parse GraphQL response into state map
      local function parse_pr_states(response, pr_list)
        local states = {}
        if not response or not response.data then return states end

        for i, pr in ipairs(pr_list) do
          local alias = string.format("pr_%d", i)
          local repo_data = response.data[alias]
          if repo_data and repo_data.pullRequest then
            local pr_data = repo_data.pullRequest
            local key = pr.repo .. "#" .. pr.number
            if pr_data.merged then
              states[key] = "merged"
            elseif pr_data.state == "OPEN" then
              states[key] = "open"
            else
              states[key] = "closed"
            end
          end
        end
        return states
      end

      -- Forward declaration for recursive reference
      local filtered_notifications_picker

      -- Helper to create filter action with query preservation
      -- This allows filters to work in-place without closing the picker completely
      local function make_filter_action(filter_type, filter_value)
        return function()
          -- Update the appropriate filter state
          if filter_type == "type" then
            type_filter = filter_value
          else
            state_filter = filter_value
          end
          -- Preserve the user's search query across filter changes
          local query = fzf.get_last_query() or ""
          -- Re-invoke picker with cached data and preserved query
          vim.schedule(function()
            filtered_notifications_picker({ query = query, use_cache = true })
          end)
        end
      end

      -- Replace the notifications picker with our filtered version
      filtered_notifications_picker = function(opts)
        opts = opts or {}
        local current_type = opts.type_filter or type_filter
        local current_state = opts.state_filter or state_filter

        -- Check if we should use cached data (for filter changes)
        local use_cache = opts.use_cache and #notification_cache.entries > 0

        -- References to data (either cache or fresh)
        local all_entries, pr_list, pr_states
        if use_cache then
          all_entries = notification_cache.entries
          pr_list = notification_cache.pr_list
          pr_states = notification_cache.pr_states
        else
          -- Fresh fetch - clear cache first
          clear_notification_cache()
          all_entries = {}
          pr_list = {}
          pr_states = {}
        end

        local function collect_notifications(done_cb)
          gh.api.get({
            "/notifications",
            paginate = true,
            F = { all = opts.all, since = opts.since },
            opts = {
              headers = { headers.diff },
              stream_cb = function(data, err)
                if err and not utils.is_blank(err) then
                  utils.error(err)
                elseif data then
                  local resp = vim.json.decode(data)
                  for _, notification in ipairs(resp) do
                    local entry = entry_maker.gen_from_notification(notification)
                    if entry ~= nil then
                      table.insert(all_entries, entry)
                      -- Track PRs for state fetching
                      if entry.kind == "pull_request" then
                        local number = entry.obj.subject.url:match("/(%d+)$")
                        if number then
                          table.insert(pr_list, {
                            repo = entry.obj.repository.full_name,
                            number = tonumber(number),
                          })
                        end
                      end
                    end
                  end
                end
              end,
              cb = done_cb,
            },
          })
        end

        -- Phase 2: Fetch PR states via GraphQL (non-critical enrichment).
        -- Runs with a hard deadline so a hung/slow GraphQL request can never
        -- block the picker: on success, error, OR timeout we still advance to
        -- the next phase (state badges are simply omitted when unavailable).
        local function fetch_pr_states(done_cb)
          if #pr_list == 0 then
            return done_cb()
          end

          local query = build_pr_state_query(pr_list)

          vim.system(
            { "gh", "api", "graphql", "-f", "query=" .. query },
            { text = true, timeout = 4000, env = { MISE_QUIET = "1" } },
            function(obj)
              if obj.code == 0 then
                local ok, response = pcall(vim.json.decode, obj.stdout or "")
                if ok then
                  pr_states = parse_pr_states(response, pr_list)
                end
              end
              vim.schedule(done_cb)
            end
          )
        end

        -- Phase 3: Display picker with filters
        local function display_picker()
          local formatted_notifications = {}
          local cached_notification_infos = {}
          local display_items = {}

          for _, entry in ipairs(all_entries) do
            -- Apply type filter
            if current_type ~= "all" and entry.kind ~= current_type then
              goto continue
            end

            -- Apply state filter (PRs only)
            local entry_state = nil
            if entry.kind == "pull_request" then
              local number = entry.obj.subject.url:match("/(%d+)$")
              if number then
                local key = entry.obj.repository.full_name .. "#" .. number
                entry_state = pr_states[key]
              end
              if current_state ~= "all" and entry_state ~= current_state then
                goto continue
              end
            end

            -- Build display content
            local icons = utils.icons
            local unread_icon = entry.obj.unread and icons.notification[entry.kind].unread
              or icons.notification[entry.kind].read
            local unread_text = fzf.utils.ansi_from_hl(unread_icon[2], unread_icon[1])
            local id_text = "#" .. (entry.obj.subject.url:match("/(%d+)$") or "NA")
            local repo_text = fzf.utils.ansi_from_hl("Number", entry.obj.repository.full_name)

            -- Add state indicator for PRs
            local state_text = ""
            if entry_state and state_icons[entry_state] then
              local si = state_icons[entry_state]
              state_text = fzf.utils.ansi_from_hl(si.hl, "[" .. si.label .. "]") .. " "
            end

            local content = table.concat({ unread_text, state_text .. id_text, repo_text, entry.obj.subject.title }, " ")
            -- Derive entry_id by stripping ANSI from content (guarantees match with fzf selection)
            local entry_id = fzf.utils.strip_ansi_coloring(content)

            formatted_notifications[entry_id] = entry
            table.insert(display_items, content)

            ::continue::
          end

          -- Build actions
          local cfg = octo_config.values
          local actions = fzf_actions.common_buffer_actions(formatted_notifications)

          -- Copy URL action
          actions[utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = {
            fn = function(selected)
              octo_notifications.copy_notification_url(formatted_notifications[selected[1]].obj)
            end,
            reload = true,
          }

          -- Mark as read action
          if not cfg.mappings.notification.read.lhs:match("leader>") then
            actions[utils.convert_vim_mapping_to_fzf(cfg.mappings.notification.read.lhs)] = {
              fn = function(selected)
                octo_notifications.request_read_notification(formatted_notifications[selected[1]].thread_id)
              end,
              reload = true,
            }
          end

          -- Mark as done action
          if not cfg.mappings.notification.done.lhs:match("leader>") then
            actions[utils.convert_vim_mapping_to_fzf(cfg.mappings.notification.done.lhs)] = {
              fn = function(selected)
                octo_notifications.delete_notification(formatted_notifications[selected[1]].thread_id)
              end,
              reload = true,
            }
          end

          -- Unsubscribe action
          if not cfg.mappings.notification.unsubscribe.lhs:match("leader>") then
            actions[utils.convert_vim_mapping_to_fzf(cfg.mappings.notification.unsubscribe.lhs)] = {
              fn = function(selected)
                octo_notifications.unsubscribe_notification(formatted_notifications[selected[1]].thread_id)
              end,
              reload = true,
            }
          end

          -- Type filter toggle actions (using alt-* to avoid terminal keycode conflicts)
          -- NOTE: ctrl-m = Enter, ctrl-i = Tab, ctrl-s = horizontal split in fzf-lua
          -- Uses make_filter_action to preserve query and use cached data
          actions["alt-a"] = make_filter_action("type", "all")
          actions["alt-p"] = make_filter_action("type", "pull_request")
          actions["alt-i"] = make_filter_action("type", "issue")
          actions["alt-d"] = make_filter_action("type", "discussion")

          -- State filter toggle actions (for PRs)
          actions["alt-s"] = make_filter_action("state", "all")
          actions["alt-o"] = make_filter_action("state", "open")
          actions["alt-c"] = make_filter_action("state", "closed")
          actions["alt-m"] = make_filter_action("state", "merged")

          -- Build header
          local type_names = { all = "All", pull_request = "PRs", issue = "Issues", discussion = "Discussions" }
          local state_names = { all = "All", open = "Open", closed = "Closed", merged = "Merged" }
          local header = string.format(
            "Type: %s │ State: %s\nM-a:All M-p:PRs M-i:Issues M-d:Disc\nM-s:AllState M-o:Open M-c:Closed M-m:Merged │ C-/:Preview",
            type_names[current_type],
            state_names[current_state]
          )

          local fzf_opts = {
            ["--no-multi"] = "",
            ["--header"] = header,
            ["--info"] = "default",
          }
          -- Restore search query if provided (for filter changes)
          if opts.query and opts.query ~= "" then
            fzf_opts["--query"] = opts.query
          end

          fzf.fzf_exec(display_items, {
            prompt = picker_utils.get_prompt(opts.prompt_title or ("Notifications")),
            previewer = previewers.notifications(formatted_notifications, cached_notification_infos),
            fzf_opts = fzf_opts,
            -- Free ctrl-d (mark done) and ctrl-b (browser) from the global
            -- preview binds (see fzf-lua.lua keymap.fzf); relocate preview
            -- paging to shift-up/down. (keymap.builtin["<C-/>"] still toggles.)
            keymap = {
              fzf = {
                ["ctrl-d"] = false,
                ["ctrl-b"] = false,
                ["shift-up"] = "preview-page-up",
                ["shift-down"] = "preview-page-down",
              },
            },
            winopts = {
              title = string.format(" Notifications (%s/%s) ", type_names[current_type], state_names[current_state]),
              title_pos = "center",
            },
            actions = actions,
            silent = true,
          })
        end

        -- Execute phases - skip fetch if using cached data
        if use_cache then
          -- Directly display with cached data
          vim.schedule(display_picker)
        else
          -- Fetch fresh data, then store to cache
          collect_notifications(function()
            -- Store entries to cache
            notification_cache.entries = all_entries
            notification_cache.pr_list = pr_list
            notification_cache.opts = opts

            fetch_pr_states(function()
              -- Store PR states to cache
              notification_cache.pr_states = pr_states
              vim.schedule(display_picker)
            end)
          end)
        end
      end

      -- ══════════════════════════════════════════════════════════════
      -- BUG FIX: Guard against nil comment body on :w
      -- Root cause: get_extmark_region uses strict=true in nvim_buf_get_lines,
      -- which fails silently for comments near buffer end, leaving body = nil
      -- ══════════════════════════════════════════════════════════════

      -- Patch 1: Fix get_extmark_region to use strict=false
      local octo_utils = require("octo.utils")
      octo_utils.get_extmark_region = function(bufnr, mark)
        local start_line = mark[1] + 1
        if start_line == 1 then
          start_line = 0
        end
        local end_line = mark[3]["end_row"] - 2
        if start_line > end_line then
          end_line = start_line
        end
        local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
        if lines then
          local text = vim.fn.join(lines, "\n")
          return start_line, end_line, text
        end
      end

      -- Patch 2: Guard do_add_issue_comment against nil body
      local OctoBuffer = require("octo.model.octo-buffer")
      local original_do_add_issue_comment = OctoBuffer.do_add_issue_comment
      function OctoBuffer:do_add_issue_comment(comment_metadata)
        if not comment_metadata.body or octo_utils.is_blank(comment_metadata.body) then
          vim.notify("[octo] Comment body is empty — nothing to submit", vim.log.levels.WARN)
          return
        end
        original_do_add_issue_comment(self, comment_metadata)
      end

      -- ══════════════════════════════════════════════════════════════
      -- Custom fzf-lua GitHub picker — fuzzy-search PRs *and* Issues:
      --   Enter   → open in Octo buffer (edit)
      --   ctrl-s  → open in horizontal split
      --   ctrl-v  → open in vertical split
      --   ctrl-d  → open PR in Diffview            (PRs only, repo mode)
      --   ctrl-b  → open in browser
      --   ctrl-x  → checkout PR branch             (PRs only, repo mode)
      --   ctrl-n  → quick comment (single-line prompt → gh comment)
      --   ctrl-r  → quick 👍 reaction
      --   ctrl-y  → copy item URL to clipboard
      --   alt-t   → toggle entity PRs ⇄ Issues
      --   alt-s   → cycle state filter (persisted per entity)
      --             PRs: open→merged→closed→all   Issues: open→closed→all
      --   alt-u   → filter by author (blank = clear, @me = you)
      --   alt-m   → cycle scope (review-requested/assigned/created; review-requested = PRs only)
      --   alt-l   → filter by label(s), comma-separated (AND; blank = clear)
      --   alt-g   → toggle repo ⇄ global (your work across all repos, via gh search)
      --   alt-f   → server-side search (GitHub query; bypasses the 200-item ceiling)
      --   alt-r   → force-refresh (clear cache for current filters, re-fetch)
      --   alt-k   → CI checks for the selected PR (pipeline runs; PRs only)
      -- ctrl-n/ctrl-r/ctrl-y keep the picker open (act on several items in a row).
      -- Preview is octo's own fzf-lua previewer (Octo-style buffer, focusable).
      -- NOTE: alt-* (not ctrl-i) is used for switches — ctrl-i == Tab in terminals.
      -- ══════════════════════════════════════════════════════════════

      -- Persisted filters across picker invocations
      local gh_entity = "pr" -- "pr" | "issue"
      local pr_state_filter = "open" -- "open", "closed", "merged", "all"
      local issue_state_filter = "open" -- "open", "closed", "all"
      local gh_author_filter = nil -- login string, "@me", or nil (no filter)
      local gh_scope = "none" -- "none" | "review-requested" | "assigned" | "created"
      local gh_label_filter = nil -- list of label names, or nil (no filter)
      local gh_repo_scope = "repo" -- "repo" (current repo) | "global" (all my repos)
      local gh_search_query = nil -- free-text GitHub search query, or nil
      local gh_repo = nil -- owner/name, resolved once per top-level invocation

      -- Short-TTL cache of `gh` results, keyed by the full filter tuple, so
      -- re-invoking the picker with unchanged filters renders instantly.
      local gh_list_cache = {}
      local gh_cache_ttl = 30000 -- ms (vim.uv.now); ~30s
      -- Key over EVERY variable that influences the fetched result set. \31 (unit
      -- separator) keeps component boundaries unambiguous.
      local function gh_cache_key()
        local entity = gh_entity
        local cur_state = (entity == "pr") and pr_state_filter or issue_state_filter
        return table.concat({
          entity,
          cur_state,
          gh_scope,
          gh_author_filter or "",
          gh_label_filter and table.concat(gh_label_filter, ",") or "",
          gh_repo_scope,
          gh_search_query or "",
          gh_repo or "",
        }, "\31")
      end

      -- Map a `gh pr list` JSON entry to the pr_info shape the diffview core consumes
      local function pr_info_from(pr, repo)
        return {
          repo = repo,
          number = pr.number,
          base = pr.baseRefName,
          head = pr.headRefName,
          state = pr.state,
          headSha = pr.headRefOid,
        }
      end

      -- CI status glyph from a PR's statusCheckRollup list → (glyph, highlight)
      local function ci_glyph(rollup)
        if type(rollup) ~= "table" or #rollup == 0 then
          return nil
        end
        local failed, pending = false, false
        for _, c in ipairs(rollup) do
          local s = c.conclusion
          if s == nil or s == "" then
            s = c.state or c.status or ""
          end
          s = tostring(s):upper()
          if
            s == "FAILURE"
            or s == "ERROR"
            or s == "TIMED_OUT"
            or s == "CANCELLED"
            or s == "ACTION_REQUIRED"
            or s == "STARTUP_FAILURE"
          then
            failed = true
          elseif
            s == "PENDING"
            or s == "IN_PROGRESS"
            or s == "QUEUED"
            or s == "WAITING"
            or s == "EXPECTED"
            or s == ""
          then
            pending = true
          end
        end
        if failed then
          return "✗", "OctoRed"
        elseif pending then
          return "●", "DiagnosticWarn"
        end
        return "✓", "OctoGreen"
      end

      -- Compact relative age from an ISO-8601 timestamp (e.g. "3h", "2d", "1w")
      local function relative_time(iso)
        if type(iso) ~= "string" then
          return nil
        end
        local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
        if not y then
          return nil
        end
        local t = os.time({
          year = tonumber(y),
          month = tonumber(mo),
          day = tonumber(d),
          hour = tonumber(h),
          min = tonumber(mi),
          sec = tonumber(s),
        })
        -- iso is UTC; correct for local timezone offset so "now" compares correctly
        local offset = os.difftime(os.time(os.date("*t")), os.time(os.date("!*t")))
        local diff = os.time() - (t - offset)
        if diff < 0 then
          diff = 0
        end
        if diff < 3600 then
          return math.max(1, math.floor(diff / 60)) .. "m"
        elseif diff < 86400 then
          return math.floor(diff / 3600) .. "h"
        elseif diff < 604800 then
          return math.floor(diff / 86400) .. "d"
        end
        return math.floor(diff / 604800) .. "w"
      end

      -- CI checks drill-down for a PR: list individual pipeline runs for the
      -- head commit via `gh pr checks`. opts = { number, repo } or nil for the
      -- current branch's PR. Works cross-repo (gh pr checks -R), so it stays
      -- usable from the picker's global mode.
      _G.octo_pr_checks = function(opts)
        opts = opts or {}
        local label = opts.number and ("#" .. opts.number) or "current branch"
        local args = { "gh", "pr", "checks" }
        if opts.number then
          table.insert(args, tostring(opts.number))
        end
        if opts.repo then
          table.insert(args, "--repo")
          table.insert(args, opts.repo)
        end
        table.insert(args, "--json")
        table.insert(args, "name,workflow,state,bucket,link,startedAt,completedAt,description")

        vim.system(args, { text = true, env = { MISE_QUIET = "1" } }, function(obj)
          vim.schedule(function()
            -- gh pr checks exits 8 (pending) or 1 (failures/none) on success too,
            -- so parse stdout regardless of exit code; empty stdout = no checks.
            local fzf = require("fzf-lua")
            local ok, checks = pcall(vim.json.decode, obj.stdout or "")
            if not ok or type(checks) ~= "table" or #checks == 0 then
              local msg = (obj.stderr and vim.trim(obj.stderr) ~= "") and vim.trim(obj.stderr)
                or ("No CI checks reported for " .. label)
              vim.notify(msg, vim.log.levels.INFO)
              return
            end

            local glyphs = {
              pass = { "✓", "OctoGreen" },
              fail = { "✗", "OctoRed" },
              pending = { "●", "DiagnosticWarn" },
              skipping = { "○", "Comment" },
              cancel = { "⊘", "Comment" },
            }
            -- Failures first, then pending, so the rows that need attention lead.
            local rank = { fail = 1, pending = 2, cancel = 3, skipping = 4, pass = 5 }
            table.sort(checks, function(a, b)
              local ra, rb = rank[a.bucket] or 9, rank[b.bucket] or 9
              if ra ~= rb then
                return ra < rb
              end
              return (a.name or "") < (b.name or "")
            end)

            -- Run duration from ISO-8601 start/end timestamps (epoch diff).
            local function epoch(iso)
              if type(iso) ~= "string" then
                return nil
              end
              local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
              if not y then
                return nil
              end
              return os.time({
                year = tonumber(y),
                month = tonumber(mo),
                day = tonumber(d),
                hour = tonumber(h),
                min = tonumber(mi),
                sec = tonumber(s),
              })
            end
            local function duration(startedAt, completedAt)
              local a, b = epoch(startedAt), epoch(completedAt)
              if not a or not b then
                return nil
              end
              local diff = b - a
              if diff < 0 then
                diff = 0
              end
              if diff < 60 then
                return diff .. "s"
              elseif diff < 3600 then
                return math.floor(diff / 60) .. "m"
              end
              return math.floor(diff / 3600) .. "h"
            end

            local counts = { pass = 0, fail = 0, pending = 0, skipping = 0, cancel = 0 }
            local display_items = {}
            local by_line = {}
            for _, c in ipairs(checks) do
              local bk = c.bucket
              if bk and counts[bk] ~= nil then
                counts[bk] = counts[bk] + 1
              end
              local g = glyphs[bk] or { "·", "Comment" }
              -- Parenthesize ansi_from_hl: it returns multiple values and would
              -- otherwise expand as the last arg to table.concat's parts list.
              local glyph = (fzf.utils.ansi_from_hl(g[2], g[1]))
              local wf, nm = c.workflow or "", c.name or ""
              local title = (wf ~= "" and wf ~= nm) and (wf .. " / " .. nm)
                or ((nm ~= "") and nm or wf)
              local parts = { glyph, title }
              local dur = duration(c.startedAt, c.completedAt)
              if dur then
                table.insert(parts, (fzf.utils.ansi_from_hl("Comment", "· " .. dur)))
              end
              if c.description and c.description ~= "" then
                table.insert(parts, (fzf.utils.ansi_from_hl("Comment", "· " .. c.description)))
              end
              local line = table.concat(parts, " ")
              table.insert(display_items, line)
              by_line[fzf.utils.strip_ansi_coloring(line)] = c
            end

            local function check_from(selected)
              if not selected or not selected[1] then
                return nil
              end
              return by_line[fzf.utils.strip_ansi_coloring(selected[1])]
            end

            local title = string.format(
              " %s checks · %d✓ %d✗ %d● ",
              label,
              counts.pass,
              counts.fail,
              counts.pending
            )

            -- Open a URL in the browser, surfacing failures (vim.ui.open
            -- returns nil + an error when no handler is available).
            local function open_in_browser(url)
              if not url or url == "" then
                vim.notify("No link for this check", vim.log.levels.WARN)
                return
              end
              local cmd, err = vim.ui.open(url)
              if not cmd then
                vim.notify("Failed to open browser: " .. (err or "unknown"), vim.log.levels.ERROR)
              end
            end

            -- Open a check's job logs in a read-only scratch buffer. GitHub
            -- Actions links carry the job id; external/non-Actions checks have
            -- none, so fall back to opening the check link in the browser.
            local function open_logs(c)
              if not c then
                return
              end
              -- Accept both /job/ and /jobs/ link shapes; fall back to the
              -- run id when the link carries no job segment at all.
              local job_id = c.link and c.link:match("/actions/runs/%d+/jobs?/(%d+)")
              local run_id = c.link and c.link:match("/actions/runs/(%d+)")
              if not job_id and not run_id then
                -- Genuinely external CI (CircleCI/Jenkins/etc.) — no gh logs.
                vim.notify("No TUI logs for this check (external CI); opening in browser", vim.log.levels.WARN)
                open_in_browser(c.link)
                return
              end
              -- Logs are only archived once a run finishes; a pending run would
              -- 410 on the archive endpoint, so go straight to the browser.
              if c.bucket == "pending" then
                vim.notify(
                  "Run still in progress — logs aren't archived yet; opening job page in browser",
                  vim.log.levels.WARN
                )
                open_in_browser(c.link)
                return
              end
              local run_args = { "gh", "run", "view" }
              if job_id then
                table.insert(run_args, "--job")
                table.insert(run_args, job_id)
              else
                -- Whole-run logs (all jobs) when the link has no job id.
                table.insert(run_args, run_id)
              end
              table.insert(run_args, "--log")
              if opts.repo then
                table.insert(run_args, "--repo")
                table.insert(run_args, opts.repo)
              end
              vim.notify("Fetching logs for " .. (c.name or "job") .. "…")
              vim.system(run_args, { text = true, env = { MISE_QUIET = "1" } }, function(o)
                vim.schedule(function()
                  local out = o.stdout or ""
                  if o.code ~= 0 and vim.trim(out) == "" then
                    local msg = vim.trim(o.stderr or "")
                    -- Expired or not-yet-archived logs return HTTP 410/404; fall
                    -- back to the job page in the browser rather than erroring.
                    if msg:match("HTTP 41%d") or msg:match("HTTP 404") or msg:match("Gone") then
                      vim.notify(
                        "Logs unavailable (run in progress or expired); opening job page in browser",
                        vim.log.levels.WARN
                      )
                open_in_browser(c.link)
                      return
                    end
                    vim.notify(
                      "Failed to fetch logs: " .. (msg ~= "" and msg or "job may still be in progress"),
                      vim.log.levels.ERROR
                    )
                    return
                  end
                  local lines = vim.split(out, "\n", { plain = true })
                  vim.cmd("botright new")
                  local buf = vim.api.nvim_get_current_buf()
                  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                  vim.bo[buf].buftype = "nofile"
                  vim.bo[buf].bufhidden = "wipe"
                  vim.bo[buf].swapfile = false
                  vim.bo[buf].modifiable = false
                  vim.bo[buf].filetype = "log"
                  pcall(vim.api.nvim_buf_set_name, buf, "octo://checks/" .. (c.name or "job") .. ".log")
                end)
              end)
            end

            fzf.fzf_exec(display_items, {
              prompt = "Checks> ",
              fzf_opts = {
                ["--no-multi"] = "",
                ["--header"] = "⏎:Logs  ^b:Job page  ^y:Copy link  ^o:All checks",
                ["--info"] = "default",
              },
              winopts = { title = title, title_pos = "center" },
              -- The global keymap.fzf binds ctrl-b to preview-page-up; this
              -- picker has no preview, so free ctrl-b for the job-page action.
              keymap = { fzf = { ["ctrl-b"] = false } },
              actions = {
                -- Enter: view this job's logs in a read-only TUI scratch buffer.
                ["default"] = function(selected)
                  open_logs(check_from(selected))
                end,
                -- ^b: open this specific job's page in the browser.
                ["ctrl-b"] = function(selected)
                  local c = check_from(selected)
                  open_in_browser(c and c.link)
                end,
                ["ctrl-y"] = function(selected)
                  local c = check_from(selected)
                  if c and c.link and c.link ~= "" then
                    vim.fn.setreg("+", c.link)
                    vim.notify("Copied " .. c.link)
                  end
                end,
                -- ^o: open the PR's overall checks page in the browser.
                ["ctrl-o"] = function()
                  local web = { "gh", "pr", "checks" }
                  if opts.number then
                    table.insert(web, tostring(opts.number))
                  end
                  if opts.repo then
                    table.insert(web, "--repo")
                    table.insert(web, opts.repo)
                  end
                  table.insert(web, "--web")
                  vim.system(web, { text = true, env = { MISE_QUIET = "1" } }, function(o)
                    if o.code ~= 0 then
                      vim.schedule(function()
                        vim.notify("Failed to open checks page: " .. (o.stderr or ""), vim.log.levels.ERROR)
                      end)
                    end
                  end)
                end,
              },
              silent = true,
            })
          end)
        end)
      end

      -- Render up to 3 labels as truecolor ANSI chips ("+N" overflow). Raw SGR
      -- escapes are stripped by strip_ansi_coloring, so preview_map keys stay stable.
      local function render_labels(labels)
        if type(labels) ~= "table" or #labels == 0 then
          return nil
        end
        local out = {}
        for i, lb in ipairs(labels) do
          if i > 3 then
            table.insert(out, "+" .. (#labels - 3))
            break
          end
          local name = lb.name or ""
          local r, g, b = (lb.color or ""):match("(%x%x)(%x%x)(%x%x)")
          if r then
            table.insert(
              out,
              string.format("\27[38;2;%d;%d;%dm%s\27[0m", tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), name)
            )
          else
            table.insert(out, name)
          end
        end
        return table.concat(out, ",")
      end

      local gh_picker
      gh_picker = function()
        -- Repo is resolved once by the public entry point (_G.octo_pr_picker)
        -- and reused across filter switches, which re-invoke this inner picker.
        local repo = gh_repo
        if not repo or repo == "" then
          vim.notify("Not in a GitHub repo (gh repo view failed)", vim.log.levels.ERROR)
          return
        end

        local entity = gh_entity
        local global = (gh_repo_scope == "global")
        local cur_state = (entity == "pr") and pr_state_filter or issue_state_filter
        -- Field set differs: `gh search` exposes `repository` but not the PR-rich
        -- columns (headRefName/reviewDecision/statusCheckRollup/mergeStateStatus).
        local json_fields
        if global then
          json_fields = (entity == "pr")
              and "number,title,state,author,isDraft,labels,url,updatedAt,repository"
            or "number,title,state,author,labels,url,updatedAt,repository"
        else
          json_fields = (entity == "pr")
              and "number,title,headRefName,baseRefName,state,headRefOid,author,isDraft,reviewDecision,statusCheckRollup,mergeStateStatus,labels,url,updatedAt"
            or "number,title,state,author,labels,url,updatedAt"
        end
        local list_cmd = (entity == "pr") and "pr" or "issue"

        -- Cache key for this exact filter combination (see gh_cache_key).
        local cache_key = gh_cache_key()

        -- render(items): sort, build display lines, wire actions, open fzf.
        local function render(items)
          -- Most-recently-updated first (matches octo's UPDATED_AT native pickers).
          -- updatedAt is ISO-8601, so lexicographic compare gives correct ordering.
          table.sort(items, function(a, b)
            return (a.updatedAt or "") > (b.updatedAt or "")
          end)

          -- Build display lines + number→item lookup.
          -- preview_map feeds octo's own fzf-lua previewer (renders an Octo-style
          -- buffer). octo indexes it by the ANSI-stripped fzf line, so the key
          -- must be exactly strip_ansi_coloring(display_line).
          local item_by_num = {}
          local display_items = {}
          local preview_map = {}
          for _, it in ipairs(items) do
            item_by_num[it.number] = it

            -- Plain (uncolored) number first for robust field/preview extraction
            local num_text = "#" .. it.number

            -- ANSI-colored state label
            local state_key = it.state and it.state:lower() or "open"
            local label, hl
            if it.isDraft then
              label, hl = "[DRAFT]", "Comment"
            elseif state_key == "open" then
              label, hl = "[OPEN]", "OctoGreen"
            elseif state_key == "merged" then
              label, hl = "[MERGED]", "OctoPurple"
            else
              label, hl = "[CLOSED]", "OctoRed"
            end
            local state_text = fzf.utils.ansi_from_hl(hl, label)

            local author = it.author and it.author.login or "?"
            local author_text = fzf.utils.ansi_from_hl("Comment", "@" .. author)

            local parts = { num_text, state_text }
            if entity == "pr" then
              -- CI status: ✓ passing / ● running / ✗ failing (repo mode only;
              -- gh search does not expose statusCheckRollup)
              local cg, chl = ci_glyph(it.statusCheckRollup)
              if cg then
                table.insert(parts, (fzf.utils.ansi_from_hl(chl, cg)))
              end
              -- Merge conflict marker
              if it.mergeStateStatus == "DIRTY" then
                table.insert(parts, (fzf.utils.ansi_from_hl("OctoRed", "⚠")))
              end
              -- Review decision (repo mode only; absent under gh search)
              if not global then
                local rd = it.reviewDecision
                local rlabel, rhl
                if rd == "APPROVED" then
                  rlabel, rhl = "✓", "OctoGreen"
                elseif rd == "CHANGES_REQUESTED" then
                  rlabel, rhl = "✗", "OctoRed"
                elseif rd == "REVIEW_REQUIRED" then
                  rlabel, rhl = "•", "OctoPurple"
                else
                  rlabel, rhl = "·", "Comment"
                end
                -- Parenthesize: ansi_from_hl returns multiple values; table.insert
                -- expands a multi-return last arg, so truncate it to one.
                table.insert(parts, (fzf.utils.ansi_from_hl(rhl, rlabel)))
              end
            end
            table.insert(parts, it.title or "")
            table.insert(parts, author_text)
            -- In global mode show the owning repo instead of the head branch.
            if global then
              local rname = it.repository and it.repository.nameWithOwner or ""
              if rname ~= "" then
                table.insert(parts, (fzf.utils.ansi_from_hl("Directory", rname)))
              end
            elseif entity == "pr" then
              table.insert(parts, (fzf.utils.ansi_from_hl("Number", it.headRefName or "")))
            end
            -- Labels (truecolor) + relative age, for both entities
            local lbls = render_labels(it.labels)
            if lbls then
              table.insert(parts, lbls)
            end
            local age = relative_time(it.updatedAt)
            if age then
              table.insert(parts, (fzf.utils.ansi_from_hl("Comment", "· " .. age)))
            end
            local line = table.concat(parts, " ")
            table.insert(display_items, line)
            -- octo's previewer looks the entry up by the ANSI-stripped line. In
            -- global mode each item carries its own repo.
            local item_repo = global and (it.repository and it.repository.nameWithOwner) or repo
            preview_map[fzf.utils.strip_ansi_coloring(line)] = {
              value = it.number,
              repo = item_repo,
              kind = (entity == "pr") and "pull_request" or "issue",
              ordinal = it.number .. " " .. (it.title or ""),
            }
          end

          local entity_label = (entity == "pr") and "PRs" or "Issues"
          local match_count = #items
          local view_cmd = (entity == "pr") and "pr" or "issue"
          if #display_items == 0 then
            display_items = { "-- No " .. cur_state .. " " .. entity_label .. " found --" }
          end

          -- Resolve the selected item from a (possibly ansi-stripped) fzf line
          local function item_from_selection(selected)
            if not selected or #selected == 0 then
              return nil
            end
            local line = fzf.utils.strip_ansi_coloring(selected[1])
            local num = line:match("#(%d+)")
            if not num then
              return nil
            end
            return item_by_num[tonumber(num)]
          end

          -- Resolve an item's repo (per-item in global mode, else the cwd repo)
          local function repo_of(it)
            return global and (it.repository and it.repository.nameWithOwner) or repo
          end

          -- Open an item's Octo buffer, optionally in a split. In global mode the
          -- item may live in another repo, so open by URL (octo parses any repo).
          local function open_item(it, splitcmd)
            if splitcmd then
              vim.cmd(splitcmd)
            end
            if global and it.url then
              vim.cmd("Octo " .. it.url)
            else
              vim.cmd("Octo " .. view_cmd .. " edit " .. it.number)
            end
          end

          -- Entity toggle: PRs ⇄ Issues (persist + re-invoke picker)
          local function toggle_entity()
            gh_entity = (gh_entity == "pr") and "issue" or "pr"
            vim.schedule(gh_picker)
          end

          -- State cycle: advance the filter for the current entity (persist + re-invoke).
          -- PRs: open→merged→closed→all→open   Issues: open→closed→all→open
          local function cycle_state()
            if gh_entity == "pr" then
              local next_state = { open = "merged", merged = "closed", closed = "all", all = "open" }
              pr_state_filter = next_state[pr_state_filter] or "open"
            else
              local next_state = { open = "closed", closed = "all", all = "open" }
              issue_state_filter = next_state[issue_state_filter] or "open"
            end
            vim.schedule(gh_picker)
          end

          -- Author filter: prompt, persist, re-invoke (blank clears)
          local function prompt_author()
            vim.schedule(function()
              vim.ui.input({ prompt = "Filter by author (blank = clear, @me = you): " }, function(input)
                if input == nil then
                  return
                end -- cancelled → keep current
                input = vim.trim(input)
                gh_author_filter = (input ~= "") and input or nil
                gh_picker()
              end)
            end)
          end

          -- Scope cycle: filter to your review queue / assigned / created work.
          -- review-requested is PR-only; issues skip straight to assigned.
          local function cycle_scope()
            local nx
            if gh_entity == "pr" then
              nx = {
                none = "review-requested",
                ["review-requested"] = "assigned",
                assigned = "created",
                created = "none",
              }
            else
              nx = { none = "assigned", assigned = "created", created = "none" }
            end
            gh_scope = nx[gh_scope] or "none"
            vim.schedule(gh_picker)
          end

          -- Label filter: prompt, persist, re-invoke (blank clears)
          local function prompt_label()
            vim.schedule(function()
              local current = gh_label_filter and table.concat(gh_label_filter, ", ") or ""
              vim.ui.input(
                { prompt = "Filter by label(s), comma-separated (blank = clear): ", default = current },
                function(input)
                  if input == nil then
                    return
                  end
                  -- Split on commas; trim each; drop empties. AND semantics (gh
                  -- `--label` repeated). nil when nothing remains.
                  local labels = {}
                  for _, label in ipairs(vim.split(input, ",", { trimempty = true })) do
                    local trimmed = vim.trim(label)
                    if trimmed ~= "" then
                      table.insert(labels, trimmed)
                    end
                  end
                  gh_label_filter = (#labels > 0) and labels or nil
                  gh_picker()
                end
              )
            end)
          end

          -- Toggle current-repo ⇄ global "my work across all repos" (gh search)
          local function cycle_repo_scope()
            gh_repo_scope = (gh_repo_scope == "repo") and "global" or "repo"
            vim.schedule(gh_picker)
          end

          -- Server-side search: send a GitHub query so matching happens server
          -- side across all items (blank clears, returning to the listing).
          local function prompt_search()
            vim.schedule(function()
              vim.ui.input({ prompt = "Server search (GitHub query, blank = clear): " }, function(input)
                if input == nil then
                  return
                end
                input = vim.trim(input)
                gh_search_query = (input ~= "") and input or nil
                gh_picker()
              end)
            end)
          end

          -- Force-refresh: drop this combo's cache entry and re-fetch from gh.
          local function force_refresh()
            gh_list_cache[cache_key] = nil
            vim.schedule(gh_picker)
          end

          local state_names = { open = "Open", closed = "Closed", merged = "Merged", all = "All" }
          local state_label = state_names[cur_state] or cur_state
          local author_label = gh_author_filter and (" │ Author: " .. gh_author_filter) or ""
          local scope_label = (gh_scope ~= "none") and (" │ Scope: " .. gh_scope) or ""
          local label_label = gh_label_filter and (" │ Label: " .. table.concat(gh_label_filter, ", ")) or ""
          local global_label = global and " │ Global" or ""
          local search_label = gh_search_query and (" │ Search: " .. gh_search_query) or ""
          local act_hints = (entity == "pr")
              and "⏎:Open ^o:Create ^s:HSplit ^v:VSplit ^d:Diffview ^b:Browser ^x:Checkout ^n:Comment ^r:👍 ^y:Copy"
            or "⏎:Open ^o:Create ^s:HSplit ^v:VSplit ^b:Browser ^n:Comment ^r:👍 ^y:Copy"
          local header = string.format(
            "%s · State:%s%s%s%s%s%s\n%s\nM-t:PRs⇄Issues │ M-s:State │ M-m:Scope │ M-u:Author │ M-l:Label │ M-g:Global │ M-f:Search │ M-r:Refresh",
            entity_label,
            state_label,
            author_label,
            scope_label,
            label_label,
            global_label,
            search_label,
            act_hints
          )
          -- Surface the checks drill-down on the switches row for PRs only.
          if entity == "pr" then
            header = header .. " │ M-k:Checks"
          end
          header = header .. " │ S-Up/Dn:Scroll"

          -- Entity-aware actions (PR-only actions added conditionally below)
          local actions = {
            ["default"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                open_item(it)
              end
            end,
            ["ctrl-s"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                open_item(it, "split")
              end
            end,
            ["ctrl-v"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                open_item(it, "vsplit")
              end
            end,
            ["ctrl-b"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                vim.system(
                  { "gh", view_cmd, "view", tostring(it.number), "--repo", repo_of(it), "--web" },
                  { text = true, env = { MISE_QUIET = "1" } },
                  function(o)
                    if o.code ~= 0 then
                      vim.schedule(function()
                        vim.notify("Failed to open in browser: " .. (o.stderr or ""), vim.log.levels.ERROR)
                      end)
                    end
                  end
                )
              end
            end,
            -- Create a new issue/PR for the active entity. Closes the picker
            -- (create opens its own multi-step input flow, unlike ^n/^r/^y).
            ["ctrl-o"] = function()
              vim.cmd("Octo " .. view_cmd .. " create")
            end,
            ["alt-t"] = toggle_entity,
            ["alt-s"] = cycle_state,
            ["alt-u"] = prompt_author,
            ["alt-m"] = cycle_scope,
            ["alt-l"] = prompt_label,
            ["alt-g"] = cycle_repo_scope,
            ["alt-f"] = prompt_search,
            ["alt-r"] = force_refresh,
            -- Quick comment: prompt (single-line) then post via gh. Works for
            -- both PRs and issues; keeps the picker open (reload) for repeats.
            ["ctrl-n"] = {
              reload = true,
              fn = function(selected)
                local it = item_from_selection(selected)
                if not it then
                  return
                end
                vim.schedule(function()
                  vim.ui.input({ prompt = "Comment on #" .. it.number .. ": " }, function(input)
                    if input == nil or vim.trim(input) == "" then
                      return
                    end
                    vim.system(
                      { "gh", view_cmd, "comment", tostring(it.number), "--repo", repo_of(it), "--body", input },
                      { text = true, env = { MISE_QUIET = "1" } },
                      function(obj)
                        vim.schedule(function()
                          if obj.code == 0 then
                            vim.notify("Commented on #" .. it.number)
                          else
                            vim.notify("Comment failed: " .. (obj.stderr or ""), vim.log.levels.ERROR)
                          end
                        end)
                      end
                    )
                  end)
                end)
              end,
            },
            -- Quick 👍 reaction via the REST reactions endpoint (PRs are issues
            -- for this endpoint); keeps the picker open (reload) for repeats.
            ["ctrl-r"] = {
              reload = true,
              fn = function(selected)
                local it = item_from_selection(selected)
                if not it then
                  return
                end
                vim.system(
                  { "gh", "api", "repos/" .. repo_of(it) .. "/issues/" .. it.number .. "/reactions", "-f", "content=+1" },
                  { text = true, env = { MISE_QUIET = "1" } },
                  function(obj)
                    vim.schedule(function()
                      if obj.code == 0 then
                        vim.notify("👍 reacted to #" .. it.number)
                      else
                        vim.notify("Reaction failed: " .. (obj.stderr or ""), vim.log.levels.ERROR)
                      end
                    end)
                  end
                )
              end,
            },
            -- Copy the selected item URL to the clipboard; keeps picker open.
            ["ctrl-y"] = {
              reload = true,
              fn = function(selected)
                local it = item_from_selection(selected)
                if it and it.url then
                  vim.fn.setreg("+", it.url)
                  vim.notify("Copied " .. it.url)
                end
              end,
            },
          }
          if entity == "pr" then
            actions["ctrl-d"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                if global then
                  vim.notify("Diffview is only available in repo mode", vim.log.levels.WARN)
                elseif _G.octo_diffview and _G.octo_diffview.open_pr_from_info then
                  _G.octo_diffview.open_pr_from_info(pr_info_from(it, repo))
                else
                  vim.notify("Octo diffview core not available", vim.log.levels.WARN)
                end
              end
            end
            actions["ctrl-x"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                if global then
                  vim.notify("Checkout is only available in repo mode", vim.log.levels.WARN)
                else
                  vim.cmd("Octo pr checkout " .. it.number)
                end
              end
            end
            -- CI checks (pipeline runs) for the selected PR's head commit. Works
            -- cross-repo (gh pr checks -R), so it stays enabled in global mode.
            actions["alt-k"] = function(selected)
              local it = item_from_selection(selected)
              if it then
                _G.octo_pr_checks({ number = it.number, repo = repo_of(it) })
              end
            end
          end

          local title_mode = global and " · global" or (gh_search_query and " · search" or "")
          local exec_opts = {
            prompt = entity_label .. "> ",
            fzf_opts = {
              ["--no-multi"] = "",
              ["--header"] = header,
              ["--info"] = "default",
            },
            winopts = {
              title = string.format(" %s (%s)%s · %d ", entity_label, state_label, title_mode, match_count),
              title_pos = "center",
            },
            -- Free ctrl-d/ctrl-b from the global preview binds (see fzf-lua.lua
            -- keymap.fzf) so the Diffview/Browser actions fire; relocate preview
            -- paging to shift-up/down.
            keymap = {
              fzf = {
                ["ctrl-d"] = false,
                ["ctrl-b"] = false,
                ["shift-up"] = "preview-page-up",
                ["shift-down"] = "preview-page-down",
              },
            },
            actions = actions,
            silent = true,
          }

          -- Prefer octo's own fzf-lua previewer: it re-fetches via GraphQL and
          -- renders an Octo-style buffer (title/details/body/reactions). Indexed
          -- by the ANSI-stripped line via preview_map. Skip it for the empty-state
          -- placeholder (no map entry → it would index nil). Fall back to a shell
          -- `gh view` preview if octo's previewer module can't be loaded.
          local ok_prev, octo_prev = pcall(require, "octo.pickers.fzf-lua.previewers")
          if match_count > 0 and ok_prev then
            exec_opts.previewer = octo_prev.issue(preview_map)
          elseif match_count > 0 then
            -- Strip the leading '#' from field {1} so `gh <entity> view <n>` resolves
            exec_opts.preview = "MISE_QUIET=1 GH_FORCE_TTY=80% gh "
              .. view_cmd
              .. " view $(echo {1} | tr -d '#') --color=always 2>/dev/null"
          end

          fzf.fzf_exec(display_items, exec_opts)
        end

        -- Cache hit: a fresh entry for this filter combo renders directly,
        -- skipping the gh round-trip. alt-r clears it to force a refetch.
        local cached = gh_list_cache[cache_key]
        if cached and (vim.uv.now() - cached.time) < gh_cache_ttl then
          render(cached.items)
          return
        end

        -- Build the argv. Global mode fans out across repos via `gh search`;
        -- repo mode uses `gh <entity> list`, switching to --search when a scope
        -- or free-text query is active so GitHub qualifiers govern the results.
        local scope = gh_scope
        -- review-requested only applies to PRs; degrade to assigned for issues.
        if scope == "review-requested" and entity ~= "pr" then
          scope = "assigned"
        end
        local args
        if global then
          local sub = (entity == "pr") and "prs" or "issues"
          args = { "gh", "search", sub, "--limit", "200", "--json", json_fields }
          if scope == "review-requested" then
            table.insert(args, "--review-requested=@me")
          elseif scope == "assigned" then
            table.insert(args, "--assignee=@me")
          elseif scope == "created" then
            table.insert(args, "--author=@me")
          else
            table.insert(args, "--involves=@me")
          end
          if cur_state == "open" then
            table.insert(args, "--state")
            table.insert(args, "open")
          elseif cur_state == "closed" then
            table.insert(args, "--state")
            table.insert(args, "closed")
          elseif cur_state == "merged" and entity == "pr" then
            table.insert(args, "--merged")
          end
          if gh_label_filter then
            for _, label in ipairs(gh_label_filter) do
              table.insert(args, "--label")
              table.insert(args, label)
            end
          end
          if gh_search_query then
            table.insert(args, gh_search_query)
          end
        else
          args = { "gh", list_cmd, "list", "--limit", "200", "--json", json_fields }
          local use_search = (scope ~= "none") or (gh_search_query ~= nil)
          if not use_search then
            table.insert(args, "--state")
            table.insert(args, cur_state)
            if gh_author_filter then
              table.insert(args, "--author")
              table.insert(args, gh_author_filter)
            end
            if gh_label_filter then
              for _, label in ipairs(gh_label_filter) do
                table.insert(args, "--label")
                table.insert(args, label)
              end
            end
          else
            table.insert(args, "--state")
            table.insert(args, "all")
            local q = {}
            if scope == "review-requested" then
              table.insert(q, "review-requested:@me")
            elseif scope == "assigned" then
              table.insert(q, "assignee:@me")
            elseif scope == "created" then
              table.insert(q, "author:@me")
            end
            if cur_state == "open" then
              table.insert(q, "is:open")
            elseif cur_state == "closed" then
              table.insert(q, "is:closed")
            elseif cur_state == "merged" then
              table.insert(q, "is:merged")
            end
            if gh_author_filter then
              table.insert(q, "author:" .. gh_author_filter)
            end
            if gh_label_filter then
              for _, label in ipairs(gh_label_filter) do
                table.insert(q, 'label:"' .. label .. '"')
              end
            end
            if gh_search_query then
              table.insert(q, gh_search_query)
            end
            table.insert(args, "--search")
            table.insert(args, table.concat(q, " "))
          end
        end

        -- Fetch asynchronously so the UI never blocks on slow networks; each
        -- filter switch re-invokes gh_picker, keeping cycling responsive.
        -- A transient GitHub gateway error (HTTP 502/503/504) is retried once
        -- after a short backoff; on hard failure we fall back to any cached
        -- items for this filter combo (even stale) so the picker stays usable.
        local function on_fetch_fail(stderr)
          stderr = stderr or ""
          local stale = gh_list_cache[cache_key]
          if stale then
            vim.notify(
              "GitHub unreachable; showing cached " .. entity .. " results.\n" .. stderr,
              vim.log.levels.WARN
            )
            render(stale.items)
          elseif stderr:match("HTTP 50[234]") then
            vim.notify(
              "GitHub is having a moment (5xx) fetching " .. entity .. "s; try again shortly.\n" .. stderr,
              vim.log.levels.ERROR
            )
          else
            vim.notify("gh " .. entity .. " fetch failed: " .. stderr, vim.log.levels.ERROR)
          end
        end

        local function do_fetch(attempt)
          vim.system(args, { text = true, env = { MISE_QUIET = "1" } }, function(obj)
            vim.schedule(function()
              if obj.code ~= 0 then
                local stderr = obj.stderr or ""
                -- Retry once on a transient gateway error before giving up.
                if attempt == 1 and stderr:match("HTTP 50[234]") then
                  vim.defer_fn(function()
                    do_fetch(2)
                  end, 750)
                  return
                end
                on_fetch_fail(stderr)
                return
              end
              local ok, items = pcall(vim.json.decode, obj.stdout or "")
              if not ok or type(items) ~= "table" then
                vim.notify("Failed to parse gh " .. entity .. " output", vim.log.levels.ERROR)
                return
              end
              gh_list_cache[cache_key] = { time = vim.uv.now(), items = items }
              render(items)
            end)
          end)
        end

        do_fetch(1)
      end

      -- The <leader>gop keymap calls _G.octo_pr_picker. The public entry
      -- resolves the repo fresh (cwd may have changed), then hands off to the
      -- inner gh_picker, which reuses gh_repo across filter switches.
      _G.octo_pr_picker = function()
        vim.system(
          { "gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner" },
          { text = true, env = { MISE_QUIET = "1" } },
          function(obj)
            vim.schedule(function()
              local r = vim.trim(obj.stdout or "")
              if obj.code ~= 0 or r == "" then
                vim.notify("Not in a GitHub repo (gh repo view failed)", vim.log.levels.ERROR)
                return
              end
              gh_repo = r
              gh_picker()
            end)
          end
        )
      end

      -- KEY FIX: Patch octo.picker directly (not package.loaded)
      -- This overwrites the already-assigned function reference
      require("octo.picker").notifications = filtered_notifications_picker
    end,
  },
}

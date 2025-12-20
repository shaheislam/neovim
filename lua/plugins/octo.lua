-- GitHub integration with octo.nvim
-- Requires: gh CLI installed and authenticated (gh auth login)

return {
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "ibhagwan/fzf-lua",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    event = "VeryLazy", -- Load for completion support
    keys = {
      -- ══════════════════════════════════════════════════════════════
      -- NOTIFICATIONS (Inbox)
      -- ══════════════════════════════════════════════════════════════
      { "<leader>On", "<cmd>Octo notification list<cr>", desc = "Notifications (inbox)" },

      -- ══════════════════════════════════════════════════════════════
      -- ISSUES
      -- ══════════════════════════════════════════════════════════════
      { "<leader>Oi", "<cmd>Octo issue list<cr>", desc = "List issues" },
      { "<leader>OI", "<cmd>Octo issue search<cr>", desc = "Search issues" },
      { "<leader>Oc", "<cmd>Octo issue create<cr>", desc = "Create issue" },

      -- ══════════════════════════════════════════════════════════════
      -- PULL REQUESTS
      -- ══════════════════════════════════════════════════════════════
      { "<leader>Op", "<cmd>Octo pr list<cr>", desc = "List PRs" },
      { "<leader>OP", "<cmd>Octo pr search<cr>", desc = "Search PRs" },
      { "<leader>OC", "<cmd>Octo pr create<cr>", desc = "Create PR" },
      { "<leader>Ox", "<cmd>Octo pr checkout<cr>", desc = "Checkout PR" },

      -- ══════════════════════════════════════════════════════════════
      -- CODE REVIEW
      -- ══════════════════════════════════════════════════════════════
      { "<leader>Or", "<cmd>Octo review start<cr>", desc = "Start review" },
      { "<leader>OR", "<cmd>Octo review resume<cr>", desc = "Resume review" },
      { "<leader>Os", "<cmd>Octo review submit<cr>", desc = "Submit review" },

      -- ══════════════════════════════════════════════════════════════
      -- QUICK ACTIONS
      -- ══════════════════════════════════════════════════════════════
      { "<leader>Ob", "<cmd>Octo repo browser<cr>", desc = "Open repo in browser" },
      { "<leader>Oy", "<cmd>Octo repo url<cr>", desc = "Copy repo URL" },

      -- ══════════════════════════════════════════════════════════════
      -- DIFFVIEW INTEGRATION
      -- ══════════════════════════════════════════════════════════════
      {
        "<leader>Od",
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
          use_icons = true,
        },

        -- Mappings within octo buffers
        mappings = {
          issue = {
            close_issue = { lhs = "<leader>ic", desc = "Close issue" },
            reopen_issue = { lhs = "<leader>io", desc = "Reopen issue" },
            list_issues = { lhs = "<leader>il", desc = "List issues" },
            reload = { lhs = "<C-r>", desc = "Reload" },
            open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
            copy_url = { lhs = "<C-y>", desc = "Copy URL" },
            add_assignee = { lhs = "<leader>aa", desc = "Add assignee" },
            remove_assignee = { lhs = "<leader>ad", desc = "Remove assignee" },
            add_label = { lhs = "<leader>la", desc = "Add label" },
            remove_label = { lhs = "<leader>ld", desc = "Remove label" },
            goto_issue = { lhs = "<leader>gi", desc = "Go to issue" },
            add_comment = { lhs = "<leader>ca", desc = "Add comment" },
            delete_comment = { lhs = "<leader>cd", desc = "Delete comment" },
            react_hooray = { lhs = "<leader>rp", desc = "React party" },
            react_heart = { lhs = "<leader>rh", desc = "React heart" },
            react_eyes = { lhs = "<leader>re", desc = "React eyes" },
            react_thumbs_up = { lhs = "<leader>r+", desc = "React +1" },
            react_thumbs_down = { lhs = "<leader>r-", desc = "React -1" },
            react_rocket = { lhs = "<leader>rr", desc = "React rocket" },
            react_laugh = { lhs = "<leader>rl", desc = "React laugh" },
            react_confused = { lhs = "<leader>rc", desc = "React confused" },
          },
          pull_request = {
            checkout_pr = { lhs = "<leader>po", desc = "Checkout PR" },
            merge_pr = { lhs = "<leader>pm", desc = "Merge PR" },
            squash_and_merge_pr = { lhs = "<leader>psm", desc = "Squash and merge" },
            rebase_and_merge_pr = { lhs = "<leader>prm", desc = "Rebase and merge" },
            list_commits = { lhs = "<leader>pc", desc = "List commits" },
            list_changed_files = { lhs = "<leader>pf", desc = "List changed files" },
            show_pr_diff = { lhs = "<leader>pd", desc = "Show PR diff" },
            add_reviewer = { lhs = "<leader>va", desc = "Add reviewer" },
            remove_reviewer = { lhs = "<leader>vd", desc = "Remove reviewer" },
            close_issue = { lhs = "<leader>ic", desc = "Close PR" },
            reopen_issue = { lhs = "<leader>io", desc = "Reopen PR" },
            reload = { lhs = "<C-r>", desc = "Reload" },
            open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
            copy_url = { lhs = "<C-y>", desc = "Copy URL" },
            add_assignee = { lhs = "<leader>aa", desc = "Add assignee" },
            remove_assignee = { lhs = "<leader>ad", desc = "Remove assignee" },
            add_label = { lhs = "<leader>la", desc = "Add label" },
            remove_label = { lhs = "<leader>ld", desc = "Remove label" },
            goto_issue = { lhs = "<leader>gi", desc = "Go to issue" },
            add_comment = { lhs = "<leader>ca", desc = "Add comment" },
            delete_comment = { lhs = "<leader>cd", desc = "Delete comment" },
            react_hooray = { lhs = "<leader>rp", desc = "React party" },
            react_heart = { lhs = "<leader>rh", desc = "React heart" },
            react_eyes = { lhs = "<leader>re", desc = "React eyes" },
            react_thumbs_up = { lhs = "<leader>r+", desc = "React +1" },
            react_thumbs_down = { lhs = "<leader>r-", desc = "React -1" },
            react_rocket = { lhs = "<leader>rr", desc = "React rocket" },
            react_laugh = { lhs = "<leader>rl", desc = "React laugh" },
            react_confused = { lhs = "<leader>rc", desc = "React confused" },
          },
          review_thread = {
            goto_issue = { lhs = "<leader>gi", desc = "Go to issue" },
            add_comment = { lhs = "<leader>ca", desc = "Add comment" },
            add_suggestion = { lhs = "<leader>sa", desc = "Add suggestion" },
            delete_comment = { lhs = "<leader>cd", desc = "Delete comment" },
            next_comment = { lhs = "]c", desc = "Next comment" },
            prev_comment = { lhs = "[c", desc = "Prev comment" },
            select_next_entry = { lhs = "]q", desc = "Next changed file" },
            select_prev_entry = { lhs = "[q", desc = "Prev changed file" },
            select_first_entry = { lhs = "[Q", desc = "First changed file" },
            select_last_entry = { lhs = "]Q", desc = "Last changed file" },
            close_review_tab = { lhs = "<C-c>", desc = "Close review" },
            react_hooray = { lhs = "<leader>rp", desc = "React party" },
            react_heart = { lhs = "<leader>rh", desc = "React heart" },
            react_eyes = { lhs = "<leader>re", desc = "React eyes" },
            react_thumbs_up = { lhs = "<leader>r+", desc = "React +1" },
            react_thumbs_down = { lhs = "<leader>r-", desc = "React -1" },
            react_rocket = { lhs = "<leader>rr", desc = "React rocket" },
            react_laugh = { lhs = "<leader>rl", desc = "React laugh" },
            react_confused = { lhs = "<leader>rc", desc = "React confused" },
          },
          submit_win = {
            approve_review = { lhs = "<C-a>", desc = "Approve" },
            comment_review = { lhs = "<C-m>", desc = "Comment" },
            request_changes = { lhs = "<C-r>", desc = "Request changes" },
            close_review_tab = { lhs = "<C-c>", desc = "Close" },
          },
          review_diff = {
            submit_review = { lhs = "<leader>vs", desc = "Submit review" },
            discard_review = { lhs = "<leader>vd", desc = "Discard review" },
            add_review_comment = { lhs = "<leader>ca", desc = "Add comment" },
            add_review_suggestion = { lhs = "<leader>sa", desc = "Add suggestion" },
            focus_files = { lhs = "<leader>e", desc = "Focus files" },
            toggle_files = { lhs = "<leader>b", desc = "Toggle files" },
            next_thread = { lhs = "]t", desc = "Next thread" },
            prev_thread = { lhs = "[t", desc = "Prev thread" },
            select_next_entry = { lhs = "]q", desc = "Next file" },
            select_prev_entry = { lhs = "[q", desc = "Prev file" },
            select_first_entry = { lhs = "[Q", desc = "First file" },
            select_last_entry = { lhs = "]Q", desc = "Last file" },
            close_review_tab = { lhs = "<C-c>", desc = "Close review" },
            toggle_viewed = { lhs = "<leader>tv", desc = "Toggle viewed" },
            goto_file = { lhs = "gf", desc = "Go to file" },
          },
          file_panel = {
            submit_review = { lhs = "<leader>vs", desc = "Submit review" },
            discard_review = { lhs = "<leader>vd", desc = "Discard review" },
            next_entry = { lhs = "j", desc = "Next" },
            prev_entry = { lhs = "k", desc = "Prev" },
            select_entry = { lhs = "<cr>", desc = "Select" },
            refresh_files = { lhs = "R", desc = "Refresh" },
            focus_files = { lhs = "<leader>e", desc = "Focus files" },
            toggle_files = { lhs = "<leader>b", desc = "Toggle files" },
            select_next_entry = { lhs = "]q", desc = "Next file" },
            select_prev_entry = { lhs = "[q", desc = "Prev file" },
            select_first_entry = { lhs = "[Q", desc = "First file" },
            select_last_entry = { lhs = "]Q", desc = "Last file" },
            close_review_tab = { lhs = "<C-c>", desc = "Close review" },
            toggle_viewed = { lhs = "<leader>tv", desc = "Toggle viewed" },
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
        local result = vim.fn.system("MISE_QUIET=1 git rev-parse --abbrev-ref HEAD 2>/dev/null")
        if vim.v.shell_error == 0 then
          return vim.trim(result)
        end
        return nil
      end

      ---Check if a git ref exists
      ---@param ref string
      ---@return boolean
      local function ref_exists(ref)
        vim.fn.system("MISE_QUIET=1 git rev-parse --verify " .. ref .. " 2>/dev/null")
        return vim.v.shell_error == 0
      end

      ---Get the current local repo's remote URL (normalized)
      ---@return string|nil
      local function get_local_repo_name()
        local result = vim.fn.system("MISE_QUIET=1 git remote get-url origin 2>/dev/null")
        if vim.v.shell_error ~= 0 then
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
              local remote = vim.fn.system(
                string.format("MISE_QUIET=1 git -C %q remote get-url origin 2>/dev/null", direct_path)
              )
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

      ---Open current Octo PR in DiffView
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
          vim.fn.system("MISE_QUIET=1 git stash push -m 'octo-diffview-temp' 2>/dev/null")
          local had_stash = vim.v.shell_error == 0

          -- Strategy: Use gh api to get PR head SHA, then fetch that commit
          -- This works even when refs/pull/{n}/head isn't available
          local temp_branch = string.format("octo-pr-%d", pr_info.number)
          local fetch_ok = false

          -- First, get the head SHA from GitHub API
          local head_sha = pr_info.headSha
          if not head_sha or head_sha == "" then
            -- Fetch from API if not in pr_info
            local api_result = vim.fn.system(
              string.format("MISE_QUIET=1 gh api repos/%s/pulls/%d --jq .head.sha 2>/dev/null", pr_info.repo, pr_info.number)
            )
            if vim.v.shell_error == 0 then
              head_sha = vim.trim(api_result)
            end
          end

          if head_sha and head_sha ~= "" then
            -- Try to fetch the specific commit
            -- First, try fetching with the commit SHA directly
            vim.fn.system(string.format("MISE_QUIET=1 git fetch origin %s 2>&1", head_sha))
            if vim.v.shell_error == 0 then
              -- Create branch from fetched commit
              vim.fn.system(string.format("MISE_QUIET=1 git branch -f %s %s 2>&1", temp_branch, head_sha))
              fetch_ok = vim.v.shell_error == 0
            end

            -- If that failed, try fetching via PR ref
            if not fetch_ok then
              vim.fn.system(string.format("MISE_QUIET=1 git fetch origin pull/%d/head 2>&1", pr_info.number))
              if vim.v.shell_error == 0 then
                vim.fn.system(string.format("MISE_QUIET=1 git branch -f %s FETCH_HEAD 2>&1", temp_branch))
                fetch_ok = vim.v.shell_error == 0
              end
            end

            -- Last resort: fetch all and hope the commit is reachable
            if not fetch_ok then
              vim.fn.system("MISE_QUIET=1 git fetch origin 2>&1")
              if ref_exists(head_sha) then
                vim.fn.system(string.format("MISE_QUIET=1 git branch -f %s %s 2>&1", temp_branch, head_sha))
                fetch_ok = vim.v.shell_error == 0
              end
            end
          end

          if fetch_ok then
            -- Checkout the temp branch
            local checkout_result = vim.fn.system(
              string.format("MISE_QUIET=1 git checkout %s 2>&1", temp_branch)
            )

            if vim.v.shell_error == 0 then
              -- Success! Now use DiffView
              local diff_cmd = string.format("DiffviewOpen origin/%s...HEAD", pr_info.base)
              vim.notify(
                string.format("PR #%d: %s → %s [%s]", pr_info.number, pr_info.base, pr_info.head, pr_info.state),
                vim.log.levels.INFO
              )
              vim.cmd(diff_cmd)

              -- Store cleanup info for later (user can run :OctoDiffCleanup)
              _G.octo_diffview.cleanup = function()
                vim.cmd("DiffviewClose")
                vim.fn.system("MISE_QUIET=1 git checkout " .. original_branch .. " 2>/dev/null")
                vim.fn.system("MISE_QUIET=1 git branch -D " .. temp_branch .. " 2>/dev/null")
                if had_stash then
                  vim.fn.system("MISE_QUIET=1 git stash pop 2>/dev/null")
                end
                vim.notify("Cleaned up and restored to " .. original_branch, vim.log.levels.INFO)
              end

              vim.api.nvim_create_user_command("OctoDiffCleanup", function()
                if _G.octo_diffview.cleanup then
                  _G.octo_diffview.cleanup()
                end
              end, { desc = "Clean up after Octo DiffView" })

              return true
            end
          end

          -- Fetch/checkout failed - try applying the diff to create commits
          vim.notify(
            string.format("PR #%d: Commits unavailable, applying diff...", pr_info.number),
            vim.log.levels.INFO
          )

          -- Get the diff from GitHub
          local diff_output = vim.fn.system(
            string.format("MISE_QUIET=1 gh pr diff %d --repo %s 2>/dev/null", pr_info.number, pr_info.repo)
          )

          if vim.v.shell_error == 0 and diff_output ~= "" then
            -- Checkout the base branch
            vim.fn.system(string.format("MISE_QUIET=1 git checkout origin/%s 2>&1", pr_info.base))
            if vim.v.shell_error ~= 0 then
              -- Try without origin/ prefix
              vim.fn.system(string.format("MISE_QUIET=1 git checkout %s 2>&1", pr_info.base))
            end

            -- Create temp branch from base
            vim.fn.system(string.format("MISE_QUIET=1 git checkout -b %s 2>&1", temp_branch))

            if vim.v.shell_error == 0 then
              -- Write diff to temp file and apply
              local temp_file = vim.fn.tempname() .. ".patch"
              local f = io.open(temp_file, "w")
              if f then
                f:write(diff_output)
                f:close()

                -- Apply the diff (--3way handles conflicts better)
                local apply_result = vim.fn.system(
                  string.format("MISE_QUIET=1 git apply --3way %s 2>&1", temp_file)
                )
                vim.fn.delete(temp_file)

                -- Check if apply worked (may have partial success)
                local status = vim.fn.system("MISE_QUIET=1 git status --porcelain 2>/dev/null")
                if status ~= "" then
                  -- Stage and commit all changes
                  vim.fn.system("MISE_QUIET=1 git add -A 2>/dev/null")
                  vim.fn.system(string.format(
                    'MISE_QUIET=1 git commit -m "PR #%d: %s" 2>/dev/null',
                    pr_info.number, pr_info.head
                  ))

                  if vim.v.shell_error == 0 then
                    -- Success! Open DiffView
                    local diff_cmd = string.format("DiffviewOpen origin/%s...HEAD", pr_info.base)
                    vim.notify(
                      string.format("PR #%d: %s → %s [%s] (applied)", pr_info.number, pr_info.base, pr_info.head, pr_info.state),
                      vim.log.levels.INFO
                    )
                    vim.cmd(diff_cmd)

                    -- Store cleanup
                    _G.octo_diffview.cleanup = function()
                      vim.cmd("DiffviewClose")
                      vim.fn.system("MISE_QUIET=1 git checkout " .. original_branch .. " 2>/dev/null")
                      vim.fn.system("MISE_QUIET=1 git branch -D " .. temp_branch .. " 2>/dev/null")
                      if had_stash then
                        vim.fn.system("MISE_QUIET=1 git stash pop 2>/dev/null")
                      end
                      vim.notify("Cleaned up and restored to " .. original_branch, vim.log.levels.INFO)
                    end

                    vim.api.nvim_create_user_command("OctoDiffCleanup", function()
                      if _G.octo_diffview.cleanup then
                        _G.octo_diffview.cleanup()
                      end
                    end, { desc = "Clean up after Octo DiffView" })

                    return true
                  end
                end
              end
            end
          end

          -- All methods failed - restore state and show scratch buffer
          vim.fn.system("MISE_QUIET=1 git checkout " .. original_branch .. " 2>/dev/null")
          vim.fn.system("MISE_QUIET=1 git branch -D " .. temp_branch .. " 2>/dev/null")
          if had_stash then
            vim.fn.system("MISE_QUIET=1 git stash pop 2>/dev/null")
          end

          -- Fall back to scratch buffer
          vim.notify(
            string.format("PR #%d: Could not apply diff for DiffView. Showing raw diff...", pr_info.number),
            vim.log.levels.WARN
          )
          local diff_output = vim.fn.system(
            string.format("MISE_QUIET=1 gh pr diff %d --repo %s 2>/dev/null", pr_info.number, pr_info.repo)
          )

          if vim.v.shell_error == 0 and diff_output ~= "" then
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

            local fetch_cmd = string.format("MISE_QUIET=1 git fetch origin pull/%d/head 2>&1", pr_info.number)
            local fetch_result = vim.fn.system(fetch_cmd)

            if vim.v.shell_error ~= 0 then
              -- Last resort: try using the head SHA if available
              if pr_info.headSha then
                vim.notify("Branch ref unavailable, using commit SHA...", vim.log.levels.INFO)
                -- Force fetch by SHA (may not work if commit is unreachable)
                vim.fn.system("MISE_QUIET=1 git fetch origin 2>/dev/null")
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

      -- Expose for use in keymaps (used by the keys array above)
      _G.octo_diffview = {
        open_pr_in_diffview = open_pr_in_diffview,
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

        -- Phase 2: Fetch PR states via GraphQL
        local function fetch_pr_states(done_cb)
          if #pr_list == 0 then
            return done_cb()
          end

          local query = build_pr_state_query(pr_list)
          local Job = require("plenary.job")

          Job:new({
            command = "gh",
            args = { "api", "graphql", "-f", "query=" .. query },
            on_exit = function(j, return_val)
              if return_val == 0 then
                local result = table.concat(j:result(), "\n")
                local ok, response = pcall(vim.json.decode, result)
                if ok then
                  pr_states = parse_pr_states(response, pr_list)
                end
              end
              vim.schedule(done_cb)
            end,
          }):start()
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
            "Type: %s │ State: %s │ M-a:All M-p:PRs M-i:Issues M-d:Disc │ M-s:AllState M-o:Open M-c:Closed M-m:Merged │ C-/:Preview",
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
            -- keymap inherits from global fzf-lua config (keymap.builtin["<C-/>"] = "toggle-preview")
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

      -- KEY FIX: Patch octo.picker directly (not package.loaded)
      -- This overwrites the already-assigned function reference
      require("octo.picker").notifications = filtered_notifications_picker
    end,
  },
}

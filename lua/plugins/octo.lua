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
      -- Monkey-patch: Add notification type filtering to Octo picker
      -- Filters: All, PRs, Issues, Discussions (toggle with alt-a/p/i/d)
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

      -- Persistent filter state across picker invocations
      local notification_filter = "all" -- "all", "pull_request", "issue", "discussion"

      -- Replace the notifications picker with our filtered version
      local filtered_notifications_picker = function(opts)
        opts = opts or {}
        local filter = opts.filter or notification_filter
        local formatted_notifications = {}
        local cached_notification_infos = {}

        local function get_contents(fzf_cb)
          gh.api.get({
            "/notifications",
            paginate = true,
            F = { all = opts.all, since = opts.since },
            opts = {
              headers = { headers.diff },
              stream_cb = function(data, err)
                if err and not utils.is_blank(err) then
                  utils.error(err)
                  fzf_cb()
                elseif data then
                  local resp = vim.json.decode(data)
                  for _, notification in ipairs(resp) do
                    local entry = entry_maker.gen_from_notification(notification)
                    if entry ~= nil then
                      -- Apply filter: skip entries that don't match current filter
                      if filter ~= "all" and entry.kind ~= filter then
                        goto continue
                      end

                      local icons = utils.icons
                      local unread_icon = entry.obj.unread and icons.notification[entry.kind].unread
                        or icons.notification[entry.kind].read
                      local unread_text = fzf.utils.ansi_from_hl(unread_icon[2], unread_icon[1])
                      local id_text = "#" .. (entry.obj.subject.url:match("/(%d+)$") or "NA")
                      local repo_text = fzf.utils.ansi_from_hl("Number", entry.obj.repository.full_name)
                      local content = table.concat({ unread_text, id_text, repo_text, entry.obj.subject.title }, " ")
                      local entry_id =
                        table.concat({ unread_icon[1], id_text, entry.obj.repository.full_name, entry.obj.subject.title }, " ")
                      formatted_notifications[entry_id] = entry
                      fzf_cb(content)
                    end
                    ::continue::
                  end
                end
              end,
              cb = function()
                fzf_cb()
              end,
            },
          })
        end

        -- Build actions with existing Octo actions + filter toggles
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

        -- Filter toggle actions
        local picker = require("octo.picker")
        actions["alt-a"] = function()
          notification_filter = "all"
          picker.notifications(opts)
        end
        actions["alt-p"] = function()
          notification_filter = "pull_request"
          picker.notifications(opts)
        end
        actions["alt-i"] = function()
          notification_filter = "issue"
          picker.notifications(opts)
        end
        actions["alt-d"] = function()
          notification_filter = "discussion"
          picker.notifications(opts)
        end

        local filter_names = { all = "All", pull_request = "PRs", issue = "Issues", discussion = "Discussions" }
        local header = string.format(
          "Filter: %s │ M-a:All M-p:PRs M-i:Issues M-d:Discussions",
          filter_names[filter]
        )

        fzf.fzf_exec(get_contents, {
          prompt = picker_utils.get_prompt(opts.prompt_title or ("Notifications (" .. filter_names[filter] .. ")")),
          previewer = previewers.notifications(formatted_notifications, cached_notification_infos),
          fzf_opts = {
            ["--no-multi"] = "",
            ["--header"] = header,
            ["--info"] = "default",
          },
          winopts = {
            title = " Notifications ",
            title_pos = "center",
          },
          actions = actions,
          silent = true,
        })
      end

      -- KEY FIX: Patch octo.picker directly (not package.loaded)
      -- This overwrites the already-assigned function reference
      require("octo.picker").notifications = filtered_notifications_picker
    end,
  },
}

-- Atlas.nvim (pilot) — GitHub PR/issue dashboard with an inline review UI,
-- trialled alongside octo.nvim (lua/plugins/octo.lua), not replacing it.
-- Octo remains the tool for GitHub-native editing, multi-line suggestions
-- and Discussions; Atlas is being trialled for its unified PR dashboard and
-- Diffview-like review surface. GitLab stays on gitlab.nvim
-- (lua/plugins/git/gitlab.lua) — only the GitHub provider is enabled here.
-- Requires: gh CLI installed and authenticated (gh auth login) — same as Octo.

local git_command = require("git.command")

local ssh_aliases = {
  ["github.com-dfe"] = "github.com",
  ["github.com-personal"] = "github.com",
}

---Plain (non-pattern) substring replacement. `alias` keys contain `.` and
---`-`, which are Lua pattern magic characters, so `string.gsub` can't be
---used directly here without escaping them.
---@param url string
---@return string
local function normalize_ssh_alias(url)
  for alias, real in pairs(ssh_aliases) do
    local start_idx, end_idx = url:find(alias, 1, true)
    if start_idx then
      return url:sub(1, start_idx - 1) .. real .. url:sub(end_idx + 1)
    end
  end
  return url
end

---Resolve the current repo's `owner/repo` slug from its git remotes so every
---Atlas view/bookmark can be qualified with `repo:owner/repo` instead of
---falling back to Atlas's global (cross-repo) defaults.
---@return string|nil
local function resolve_github_slug()
  for _, remote in ipairs({ "origin", "upstream" }) do
    local ok, url = git_command.output({ "remote", "get-url", remote })
    if ok and url ~= "" then
      url = normalize_ssh_alias(url)
      local owner, repo = url:match("github%.com[:/]([^/]+)/(.+)$")
      if owner and repo then
        repo = repo:gsub("%.git$", "")
        return owner .. "/" .. repo
      end
    end
  end
  return nil
end

---Prompt for free text, then run an Ex command with it appended.
---@param prompt string
---@param cmd string
local function prompt_and_run(prompt, cmd)
  vim.ui.input({ prompt = prompt }, function(input)
    if input and input ~= "" then
      vim.cmd(cmd .. " " .. input)
    end
  end)
end

---Re-apply this repo's transparent styling to Atlas's highlight groups a few
---times after opening it. Atlas (re)defines several opaque groups on setup
---and per-render, so a single ColorScheme-triggered pass isn't enough.
local function reapply_transparency()
  local ok, styling = pcall(require, "config.autocmds.styling")
  if not ok or not styling.apply_atlas_transparency then
    return
  end
  for _, delay in ipairs({ 0, 50, 200, 600, 1500 }) do
    vim.defer_fn(styling.apply_atlas_transparency, delay)
  end
end

return {
  {
    "emrearmagan/atlas.nvim",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "MeanderingProgrammer/render-markdown.nvim",
    },
    cmd = {
      "AtlasPulls",
      "AtlasIssues",
      "AtlasDiff",
      "AtlasNotes",
      "AtlasCreatePR",
      "AtlasCreateIssue",
      "AtlasSearch",
      "AtlasOpen",
      "AtlasClearCache",
      "AtlasLogs",
    },
    keys = {
      {
        "<leader>gAp",
        function()
          vim.cmd("AtlasPulls github")
          reapply_transparency()
        end,
        desc = "Atlas: Pull requests (pilot)",
      },
      {
        "<leader>gAi",
        function()
          vim.cmd("AtlasIssues github")
          reapply_transparency()
        end,
        desc = "Atlas: Issues (pilot)",
      },
      {
        "<leader>gAd",
        function()
          prompt_and_run("Atlas diff (base...head or PR URL): ", "AtlasDiff")
          reapply_transparency()
        end,
        desc = "Atlas: Diff range or PR URL",
      },
      {
        "<leader>gAn",
        function()
          vim.cmd("AtlasNotes")
          reapply_transparency()
        end,
        desc = "Atlas: Review notes",
      },
      {
        "<leader>gAs",
        function()
          vim.cmd("AtlasSearch github")
          reapply_transparency()
        end,
        desc = "Atlas: Search GitHub",
      },
      {
        "<leader>gAo",
        function()
          prompt_and_run("Atlas open (URL, #123, owner/repo#123): ", "AtlasOpen")
        end,
        desc = "Atlas: Open target",
      },
      { "<leader>gAc", "<cmd>AtlasClearCache<cr>", desc = "Atlas: Clear cache" },
      { "<leader>gAl", "<cmd>AtlasLogs<cr>", desc = "Atlas: Toggle logs (pilot)" },
    },
    config = function()
      local slug = resolve_github_slug()
      if not slug then
        vim.notify(
          "Atlas: could not resolve a GitHub owner/repo from git remotes; PR/issue views will use Atlas's unscoped defaults.",
          vim.log.levels.WARN
        )
      end

      local github_pulls = {}
      local github_issues = {}
      local repo_config = nil

      if slug then
        github_pulls = {
          views = {
            { name = "Open", key = "1", layout = "plain", search = "repo:" .. slug .. " is:open" },
            {
              name = "Review requested",
              key = "2",
              layout = "plain",
              search = "repo:" .. slug .. " is:open is:pr review-requested:@me",
            },
            {
              name = "Assigned",
              key = "3",
              layout = "plain",
              search = "repo:" .. slug .. " is:open assignee:@me",
            },
            {
              name = "Created",
              key = "4",
              layout = "plain",
              search = "repo:" .. slug .. " is:open author:@me",
            },
          },
          bookmarks = {
            items = {
              ["Drafts"] = "repo:" .. slug .. " is:pr is:draft author:@me",
              ["Recently merged"] = "repo:" .. slug .. " is:pr is:merged sort:updated-desc",
            },
          },
        }
        github_issues = {
          views = {
            { name = "Assigned", key = "1", layout = "plain", search = "repo:" .. slug .. " is:open assignee:@me" },
            { name = "Created", key = "2", layout = "plain", search = "repo:" .. slug .. " is:open author:@me" },
          },
        }
        -- Scope checkout/diff path resolution to this clone only; do not add
        -- mappings for other repositories without an explicit request.
        repo_config = {
          paths = {
            [slug] = vim.fn.getcwd(),
          },
        }
      end

      require("atlas").setup({
        pulls = {
          providers = {
            github = github_pulls,
          },
          diff = {
            -- Keep Atlas's native review UI; do not pull in Diffview/CodeDiff
            -- as a dependency for this pilot.
            open_cmd = "AtlasDiff",
            layout = "inline",
            compact = true,
          },
          repo_config = repo_config,
        },
        issues = {
          providers = {
            github = github_issues,
          },
        },
      })

      reapply_transparency()
    end,
  },
}

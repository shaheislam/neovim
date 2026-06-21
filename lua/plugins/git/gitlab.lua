-- gitlab.nvim — inline GitLab MR review (the GitLab analog of octo.nvim).
-- Ships a Go binary (built via the `build` hook) that talks to the GitLab REST
-- API with a personal access token; it is NOT a `glab` CLI wrapper.
--
-- Auth (gitlab.com): export GITLAB_TOKEN with `api` scope in your shell env
-- (keep it out of this repo). GITLAB_URL is only needed for self-hosted
-- instances. Alternatively a project-root `.gitlab.nvim` file works, but then
-- add `.gitlab.nvim` to .gitignore so the token is never committed.
--
-- Default global gl* / g? maps are disabled; a curated <leader>gL set is used
-- instead (matches this config's leader-namespaced, which-key-discoverable
-- convention). In-buffer discussion-tree, reviewer, and popup keymaps stay at
-- plugin defaults (buffer-local, no collision).
local function gl(fn)
  return function()
    require("gitlab")[fn]()
  end
end

return {
  {
    "harrisoncramer/gitlab.nvim",
    version = false,
    build = function()
      require("gitlab.server").build(true)
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "dlyongemallo/diffview.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>gLc", gl("choose_merge_request"), desc = "Choose MR for review" },
      { "<leader>gLS", gl("review"), desc = "Start review (current branch)" },
      { "<leader>gLs", gl("summary"), desc = "MR summary (editable)" },
      { "<leader>gLd", gl("toggle_discussions"), desc = "Toggle discussions" },
      { "<leader>gLp", gl("pipeline"), desc = "Pipeline status" },
      { "<leader>gLA", gl("approve"), desc = "Approve MR" },
      { "<leader>gLR", gl("revoke"), desc = "Revoke approval" },
      { "<leader>gLM", gl("merge"), desc = "Merge MR" },
      {
        "<leader>gLm",
        function()
          require("gitlab").merge({ auto_merge = true })
        end,
        desc = "Auto-merge on pipeline success",
      },
      { "<leader>gLC", gl("create_mr"), desc = "Create MR (current branch)" },
      { "<leader>gLn", gl("create_note"), desc = "Create note" },
      { "<leader>gLP", gl("publish_all_drafts"), desc = "Publish all drafts" },
      { "<leader>gLD", gl("toggle_draft_mode"), desc = "Toggle draft mode" },
      { "<leader>gLo", gl("open_in_browser"), desc = "Open MR in browser" },
      { "<leader>gLu", gl("copy_mr_url"), desc = "Copy MR URL" },
    },
    config = function()
      require("gitlab").setup({
        keymaps = {
          -- Use the curated <leader>gL set above; disable the plugin's default
          -- bare gl*/g? global maps. Buffer-local maps (discussion tree,
          -- reviewer diff, popups) remain at their defaults.
          global = {
            disable_all = true,
          },
        },
      })
    end,
  },
}

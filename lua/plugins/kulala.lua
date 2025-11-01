-- kulala.nvim - REST client for Neovim
-- Supports HTTP, GraphQL, gRPC, and WebSocket requests

return {
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    keys = {
      { "<leader>Rs", "<cmd>lua require('kulala').run()<cr>", desc = "Send the request" },
      { "<leader>Rt", "<cmd>lua require('kulala').toggle_view()<cr>", desc = "Toggle headers/body" },
      { "<leader>Rn", "<cmd>lua require('kulala').jump_next()<cr>", desc = "Jump to next request" },
      { "<leader>Rp", "<cmd>lua require('kulala').jump_prev()<cr>", desc = "Jump to previous request" },
      { "<leader>Ri", "<cmd>lua require('kulala').inspect()<cr>", desc = "Inspect current request" },
      { "<leader>Re", "<cmd>lua require('kulala').set_selected_env()<cr>", desc = "Set environment" },
      { "<leader>Rc", "<cmd>lua require('kulala').copy()<cr>", desc = "Copy as cURL" },
      { "<leader>Rr", "<cmd>lua require('kulala').replay()<cr>", desc = "Replay last request" },
      { "<leader>Ra", "<cmd>lua require('kulala').run_all()<cr>", desc = "Run all requests" },
      { "<leader>RS", "<cmd>lua require('kulala').scratchpad()<cr>", desc = "Open scratchpad" },
      { "<leader>Rq", "<cmd>lua require('kulala').close()<cr>", desc = "Close window" },
      { "<leader>RG", "<cmd>lua require('kulala').download_graphql_schema()<cr>", desc = "Download GraphQL schema" },
    },
    opts = {
      -- Default formatters for different content types
      formatters = {
        json = { "jq", "." },
        xml = { "xmllint", "--format", "-" },
        html = { "xmllint", "--format", "--html", "-" },
      },
      -- Default content type if not specified
      default_view = "body",
      -- Show icons in the UI
      icons = {
        inlay = {
          loading = "⏳",
          done = "✅",
          error = "❌",
        },
        lualine = "🐼",
      },
      -- Additional cURL options
      additional_curl_options = {},
      -- Scratchpad default contents
      scratchpad_default_contents = {
        "@MY_TOKEN_NAME=my_token_value",
        "",
        "# @name scratchpad",
        "POST https://httpbin.org/post HTTP/1.1",
        "accept: application/json",
        "content-type: application/json",
        "",
        "{",
        '  "foo": "bar"',
        "}",
      },
      -- Debug mode
      debug = false,
    },
    config = function(_, opts)
      require("kulala").setup(opts)

      -- Set up filetype detection for .http and .rest files
      vim.filetype.add({
        extension = {
          http = "http",
          rest = "http",
        },
      })
    end,
  },
}

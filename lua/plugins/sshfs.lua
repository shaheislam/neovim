return {
  {
    "uhs-robert/sshfs.nvim",
    lazy = true,
    cmd = {
      "SSHConnect",
      "SSHFiles",
      "SSHGrep",
      "SSHLiveFind",
      "SSHLiveGrep",
      "SSHTerminal",
      "SSHDisconnect",
      "SSHDisconnectAll",
    },
    keys = {
      { "<leader>sc", "<cmd>SSHConnect<cr>", desc = "SSH: Connect to host" },
      { "<leader>sf", "<cmd>SSHFiles<cr>", desc = "SSH: Browse files" },
      { "<leader>sg", "<cmd>SSHGrep<cr>", desc = "SSH: Grep files" },
      { "<leader>sG", "<cmd>SSHLiveGrep<cr>", desc = "SSH: Live grep (streaming)" },
      { "<leader>sF", "<cmd>SSHLiveFind<cr>", desc = "SSH: Live find (streaming)" },
      { "<leader>st", "<cmd>SSHTerminal<cr>", desc = "SSH: Open terminal" },
      { "<leader>sd", "<cmd>SSHDisconnect<cr>", desc = "SSH: Disconnect host" },
      { "<leader>sD", "<cmd>SSHDisconnectAll<cr>", desc = "SSH: Disconnect all" },
    },
    opts = {
      connections = {
        ssh_configs = { "$HOME/.ssh/config" },
        control_persist = "10m",
        socket_dir = "$HOME/.ssh/sockets",
        sshfs_options = {
          -- Connection stability
          reconnect = true,
          ServerAliveInterval = 15,
          ServerAliveCountMax = 3,
          ConnectTimeout = 10,
          -- Compression
          compression = "yes",
          -- Caching (performance)
          cache = "yes",
          dcache_timeout = 300,
          dcache_max_size = 10000,
          attr_timeout = 60,
        },
      },
      mounts = {
        base_dir = "$HOME/mnt",
      },
      -- Common directories available on all hosts
      global_paths = {
        "~",
        "/var/log",
        "/etc",
        "/tmp",
      },
      hooks = {
        on_mount = "SSHFiles",
        on_exit = {
          auto_unmount = true,
          auto_clean = true,
        },
      },
      ui = {
        local_picker = "fzf-lua",
        remote_picker = "fzf-lua",
      },
    },
    config = function(_, opts)
      require("sshfs").setup(opts)

      local ok, which_key = pcall(require, "which-key")
      if ok then
        which_key.add({ { "<leader>s", group = "SSH/SSHFS" } })
      end
    end,
  },
}

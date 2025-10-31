-- DevOps LSP Configuration
-- Terraform, Ansible, YAML schema support, and filetype detection

return {
  -- Additional LSP configurations for DevOps tools
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- Ensure opts.servers exists
      opts.servers = opts.servers or {}

      -- Terraform LSP with enhanced settings
      opts.servers.terraformls = vim.tbl_deep_extend("force", opts.servers.terraformls or {}, {
        filetypes = { "terraform", "tf", "terraform-vars", "hcl" },
        root_dir = function(fname)
          return require("lspconfig.util").root_pattern(".terraform", ".git")(fname)
        end,
      })

      -- Ansible LSP configuration
      opts.servers.ansiblels = vim.tbl_deep_extend("force", opts.servers.ansiblels or {}, {
        filetypes = { "yaml.ansible", "ansible" },
        root_dir = function(fname)
          return require("lspconfig.util").root_pattern("ansible.cfg", ".ansible-lint")(fname)
        end,
        single_file_support = true,
      })

      -- YAML LSP with schema support
      opts.servers.yamlls = vim.tbl_deep_extend("force", opts.servers.yamlls or {}, {
        settings = {
          yaml = {
            schemas = {
              -- Kubernetes schemas
              ["https://raw.githubusercontent.com/instrumenta/kubernetes-json-schema/master/v1.18.0-standalone-strict/all.json"] = "k8s/**/*.yaml",
              -- GitHub Actions
              ["https://json.schemastore.org/github-workflow.json"] = ".github/workflows/*",
              -- Docker Compose
              ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "docker-compose*.yml",
              -- Ansible
              ["https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json"] = "ansible/**/*.yml",
            },
            validate = true,
            completion = true,
            hover = true,
          },
        },
      })

      -- Docker LSP
      opts.servers.dockerls = vim.tbl_deep_extend("force", opts.servers.dockerls or {}, {
        filetypes = { "dockerfile" },
        root_dir = function(fname)
          return require("lspconfig.util").root_pattern("Dockerfile", "docker-compose.yml")(fname)
        end,
      })

      -- Helm LSP
      opts.servers.helm_ls = vim.tbl_deep_extend("force", opts.servers.helm_ls or {}, {
        filetypes = { "helm" },
        root_dir = function(fname)
          return require("lspconfig.util").root_pattern("Chart.yaml")(fname)
        end,
      })

      return opts
    end,
  },

  -- Auto-detect filetypes for DevOps files
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.filetype.add({
        extension = {
          tf = "terraform",
          tfvars = "terraform",
          hcl = "hcl",
          nomad = "hcl",
          consul = "hcl",
          vault = "hcl",
        },
        filename = {
          ["Dockerfile"] = "dockerfile",
          [".dockerignore"] = "dockerfile",
          ["docker-compose.yml"] = "yaml.docker-compose",
          ["docker-compose.yaml"] = "yaml.docker-compose",
          ["playbook.yml"] = "yaml.ansible",
          ["playbook.yaml"] = "yaml.ansible",
          ["inventory"] = "ini",
          ["Jenkinsfile"] = "groovy",
          ["Vagrantfile"] = "ruby",
        },
        pattern = {
          [".*%.ya?ml%.j2"] = "yaml.jinja",
          [".*ansible.*%.ya?ml"] = "yaml.ansible",
          [".*playbook.*%.ya?ml"] = "yaml.ansible",
          [".*k8s.*%.ya?ml"] = "yaml",
          [".*kubernetes.*%.ya?ml"] = "yaml",
          [".*%.tf"] = "terraform",
          [".*%.tfvars"] = "terraform",
        },
      })
    end,
  },
}

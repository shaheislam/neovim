-- DevOps Filetype Detection
-- Auto-detect filetypes for DevOps files (Terraform, Docker, Ansible, etc.)
-- NOTE: LSP server configurations are in lsp.lua using vim.lsp.config API

return {
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

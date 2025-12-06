-- kubectl integration for Neovim
-- Provides commands for copying files to/from Kubernetes pods
--
-- Commands:
--   :KubeCpFrom <pod>:<path>    - Copy file from pod, open in buffer
--   :KubeCpTo <pod>:<path>      - Copy current buffer to pod
--   :KubeCpPicker               - Interactive fzf picker for pod/file

local M = {}

-- Get current namespace from kubectl config
local function get_namespace()
  local handle = io.popen("kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null")
  if not handle then
    return "default"
  end
  local result = handle:read("*a")
  handle:close()
  return result ~= "" and result or "default"
end

-- Copy file FROM pod to local temp, open in buffer
local function kube_cp_from(args)
  local input = args.args
  if input == "" then
    vim.notify("Usage: :KubeCpFrom <pod>:<path> or :KubeCpFrom <pod> <path>", vim.log.levels.ERROR)
    return
  end

  local pod, remote_path
  -- Parse pod:path format
  if input:match(":") then
    local parts = vim.split(input, ":", { plain = true })
    pod = parts[1]
    remote_path = table.concat({ unpack(parts, 2) }, ":")
  else
    -- Try space-separated
    local parts = vim.split(input, " ")
    pod = parts[1]
    remote_path = parts[2]
  end

  if not pod or not remote_path then
    vim.notify("Usage: :KubeCpFrom <pod>:<path>", vim.log.levels.ERROR)
    return
  end

  local ns = get_namespace()
  local filename = vim.fn.fnamemodify(remote_path, ":t")
  local local_path = "/tmp/kube-" .. pod .. "-" .. filename

  vim.notify("Copying from " .. ns .. "/" .. pod .. ":" .. remote_path .. "...", vim.log.levels.INFO)

  local cmd = string.format("kubectl cp %s/%s:%s %s 2>&1", ns, pod, remote_path, local_path)
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("kubectl cp failed: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Open the file in a new buffer
  vim.cmd("edit " .. local_path)

  -- Store metadata for KubeCpTo
  vim.b.kube_pod = pod
  vim.b.kube_namespace = ns
  vim.b.kube_remote_path = remote_path

  vim.notify("Copied to buffer. Use :KubeCpTo to save back.", vim.log.levels.INFO)
end

-- Copy current buffer TO pod
local function kube_cp_to(args)
  local input = args.args

  local pod, remote_path, ns

  if input ~= "" then
    -- Parse from args
    if input:match(":") then
      local parts = vim.split(input, ":", { plain = true })
      pod = parts[1]
      remote_path = table.concat({ unpack(parts, 2) }, ":")
    else
      local parts = vim.split(input, " ")
      pod = parts[1]
      remote_path = parts[2]
    end
  else
    -- Use buffer metadata from KubeCpFrom
    pod = vim.b.kube_pod
    ns = vim.b.kube_namespace
    remote_path = vim.b.kube_remote_path
  end

  if not pod or not remote_path then
    vim.notify("Usage: :KubeCpTo <pod>:<path> or use after :KubeCpFrom", vim.log.levels.ERROR)
    return
  end

  ns = ns or get_namespace()

  -- Save buffer first
  vim.cmd("write")
  local local_path = vim.fn.expand("%:p")

  vim.notify("Copying to " .. ns .. "/" .. pod .. ":" .. remote_path .. "...", vim.log.levels.INFO)

  local cmd = string.format("kubectl cp %s %s/%s:%s 2>&1", local_path, ns, pod, remote_path)
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("kubectl cp failed: " .. result, vim.log.levels.ERROR)
    return
  end

  vim.notify("Copied to " .. pod .. ":" .. remote_path, vim.log.levels.INFO)
end

-- Interactive picker using fzf-lua
local function kube_cp_picker()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required for :KubeCpPicker", vim.log.levels.ERROR)
    return
  end

  local ns = get_namespace()

  -- First, pick a pod
  fzf.fzf_exec("kubectl get pods -n " .. ns .. " -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null", {
    prompt = "Select pod> ",
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        local pod = selected[1]

        -- Then, browse the pod's filesystem
        fzf.fzf_exec(
          "kubectl exec " .. pod .. " -n " .. ns .. " -- find / -type f 2>/dev/null | head -500",
          {
            prompt = "Select file (" .. pod .. ")> ",
            previewer = false, -- Can't easily preview remote files
            actions = {
              ["default"] = function(file_selected)
                if not file_selected or #file_selected == 0 then
                  return
                end
                local remote_path = file_selected[1]
                -- Call KubeCpFrom with the selection
                kube_cp_from({ args = pod .. ":" .. remote_path })
              end,
            },
          }
        )
      end,
    },
  })
end

-- List pods in current namespace
local function kube_list_pods()
  local ns = get_namespace()
  local cmd = "kubectl get pods -n " .. ns .. " -o wide 2>&1"
  local result = vim.fn.system(cmd)

  -- Open in a scratch buffer
  vim.cmd("new")
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.filetype = "kubectl"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(result, "\n"))
  vim.api.nvim_buf_set_name(0, "kubectl-pods-" .. ns)
end

-- Setup commands
function M.setup()
  vim.api.nvim_create_user_command("KubeCpFrom", kube_cp_from, {
    nargs = "*",
    desc = "Copy file from Kubernetes pod to buffer",
    complete = function()
      -- Could add pod completion here
      return {}
    end,
  })

  vim.api.nvim_create_user_command("KubeCpTo", kube_cp_to, {
    nargs = "*",
    desc = "Copy current buffer to Kubernetes pod",
  })

  vim.api.nvim_create_user_command("KubeCpPicker", kube_cp_picker, {
    nargs = 0,
    desc = "Interactive kubectl cp with fzf picker",
  })

  vim.api.nvim_create_user_command("KubePods", kube_list_pods, {
    nargs = 0,
    desc = "List pods in current namespace",
  })

  -- Keymaps (optional, under <leader>k for kubectl)
  vim.keymap.set("n", "<leader>kf", ":KubeCpFrom ", { desc = "kubectl cp from pod" })
  vim.keymap.set("n", "<leader>kt", ":KubeCpTo<CR>", { desc = "kubectl cp to pod" })
  vim.keymap.set("n", "<leader>kp", ":KubeCpPicker<CR>", { desc = "kubectl cp picker" })
  vim.keymap.set("n", "<leader>kl", ":KubePods<CR>", { desc = "kubectl list pods" })
end

-- Auto-setup on load
M.setup()

return {}

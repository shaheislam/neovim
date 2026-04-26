-- kubectl integration for Neovim
-- Exposes a single :Kube command with subcommands for pod file workflows.

local M = {}

local subcommands = { "from", "to", "picker", "pods" }

local function get_namespace()
  local handle = io.popen("kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null")
  if not handle then
    return "default"
  end

  local result = handle:read("*a")
  handle:close()
  return result ~= "" and result or "default"
end

local function kube_cp_from(args)
  local input = args.args
  if input == "" then
    vim.notify("Usage: :Kube from <pod>:<path> or :Kube from <pod> <path>", vim.log.levels.ERROR)
    return
  end

  local pod, remote_path
  if input:match(":") then
    local parts = vim.split(input, ":", { plain = true })
    pod = parts[1]
    remote_path = table.concat({ unpack(parts, 2) }, ":")
  else
    local parts = vim.split(input, " ")
    pod = parts[1]
    remote_path = parts[2]
  end

  if not pod or not remote_path then
    vim.notify("Usage: :Kube from <pod>:<path>", vim.log.levels.ERROR)
    return
  end

  local ns = get_namespace()
  local filename = vim.fn.fnamemodify(remote_path, ":t")
  local local_path = "/tmp/kube-" .. pod .. "-" .. filename

  vim.notify("Copying from " .. ns .. "/" .. pod .. ":" .. remote_path .. "...", vim.log.levels.INFO)

  local cmd = string.format(
    "kubectl cp %s %s 2>&1",
    vim.fn.shellescape(ns .. "/" .. pod .. ":" .. remote_path),
    vim.fn.shellescape(local_path)
  )
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("kubectl cp failed: " .. result, vim.log.levels.ERROR)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(local_path))
  vim.b.kube_pod = pod
  vim.b.kube_namespace = ns
  vim.b.kube_remote_path = remote_path

  vim.notify("Copied to buffer. Use :Kube to to save back.", vim.log.levels.INFO)
end

local function kube_cp_to(args)
  local input = args.args
  local pod, remote_path, ns

  if input ~= "" then
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
    pod = vim.b.kube_pod
    ns = vim.b.kube_namespace
    remote_path = vim.b.kube_remote_path
  end

  if not pod or not remote_path then
    vim.notify("Usage: :Kube to <pod>:<path> or use after :Kube from", vim.log.levels.ERROR)
    return
  end

  ns = ns or get_namespace()
  vim.cmd("write")
  local local_path = vim.fn.expand("%:p")

  vim.notify("Copying to " .. ns .. "/" .. pod .. ":" .. remote_path .. "...", vim.log.levels.INFO)

  local cmd = string.format(
    "kubectl cp %s %s 2>&1",
    vim.fn.shellescape(local_path),
    vim.fn.shellescape(ns .. "/" .. pod .. ":" .. remote_path)
  )
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("kubectl cp failed: " .. result, vim.log.levels.ERROR)
    return
  end

  vim.notify("Copied to " .. pod .. ":" .. remote_path, vim.log.levels.INFO)
end

local function kube_cp_picker()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua required for :Kube picker", vim.log.levels.ERROR)
    return
  end

  local ns = get_namespace()

  fzf.fzf_exec("kubectl get pods -n " .. ns .. " -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null", {
    prompt = "Select pod> ",
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end

        local pod = selected[1]
        fzf.fzf_exec(
          "kubectl exec " .. pod .. " -n " .. ns .. " -- find / -type f 2>/dev/null | head -500",
          {
            prompt = "Select file (" .. pod .. ")> ",
            previewer = false,
            actions = {
              ["default"] = function(file_selected)
                if not file_selected or #file_selected == 0 then
                  return
                end

                kube_cp_from({ args = pod .. ":" .. file_selected[1] })
              end,
            },
          }
        )
      end,
    },
  })
end

local function kube_list_pods()
  local ns = get_namespace()
  local result = vim.fn.system("kubectl get pods -n " .. ns .. " -o wide 2>&1")

  vim.cmd("new")
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.filetype = "kubectl"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(result, "\n"))
  vim.api.nvim_buf_set_name(0, "kubectl-pods-" .. ns)
end

local function kube_usage()
  vim.notify("Usage: :Kube <from|to|picker|pods>", vim.log.levels.INFO)
end

local handlers = {
  from = kube_cp_from,
  to = kube_cp_to,
  picker = kube_cp_picker,
  pods = kube_list_pods,
}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function complete_subcommand(arg_lead, cmd_line)
  if cmd_line:match("^%s*Kube%s+[^%s]*$") then
    local matches = {}
    for _, subcommand in ipairs(subcommands) do
      if starts_with(subcommand, arg_lead) then
        table.insert(matches, subcommand)
      end
    end
    return matches
  end

  return {}
end

local function dispatch(args)
  local subcommand, remainder = args.args:match("^(%S+)%s*(.*)$")
  if not subcommand then
    kube_usage()
    return
  end

  local handler = handlers[subcommand]
  if not handler then
    vim.notify("Unknown Kube subcommand: " .. subcommand, vim.log.levels.ERROR)
    kube_usage()
    return
  end

  handler({ args = remainder or "" })
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  vim.api.nvim_create_user_command("Kube", dispatch, {
    nargs = "*",
    desc = "kubectl helpers",
    complete = complete_subcommand,
  })
end

return M

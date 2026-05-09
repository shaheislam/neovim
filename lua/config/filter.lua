-- Structured text filters for replacing buffers, ranges, or exact selections.

local M = {}

local function normalize_args(args)
  if args == nil then
    return {}
  end
  if type(args) == "string" then
    return { args }
  end
  return args
end

local function command_name(cmd)
  return table.concat(cmd, " ")
end

local function notify_error(cmd, stderr)
  vim.notify(
    string.format("Error running %q: %s", command_name(cmd), vim.trim(stderr or "")),
    vim.log.levels.ERROR,
    { title = "filter" }
  )
end

local function output_lines(stdout)
  local lines = vim.split(stdout or "", "\n")
  if lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

local function run(binary, args, input, on_success)
  local cmd = { binary }
  vim.list_extend(cmd, normalize_args(args))

  local ok, err = pcall(vim.system, cmd, { stdin = input, text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        on_success(output_lines(result.stdout))
      else
        notify_error(cmd, result.stderr)
      end
    end)
  end)

  if not ok then
    notify_error(cmd, err)
  end
end

function M.replace_buffer_with_command_output(binary, args)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  run(binary, args, table.concat(lines, "\n"), function(output)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
  end)
end

function M.replace_range_with_command_output(binary, args, line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  run(binary, args, table.concat(lines, "\n"), function(output)
    vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, output)
  end)
end

function M.replace_text_with_command_output(binary, args, start_row, start_col, end_row, end_col)
  local text = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  run(binary, args, table.concat(text, "\n"), function(output)
    vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, output)
  end)
end

return M

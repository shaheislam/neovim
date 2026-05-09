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

local function leading_indent(line)
  return line:match("^(%s*)") or ""
end

local function first_nonblank_indent(lines)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      return leading_indent(line)
    end
  end
  return ""
end

local function can_dedent(lines, indent)
  if indent == "" then
    return false
  end

  for _, line in ipairs(lines) do
    if line:match("%S") and line:sub(1, #indent) ~= indent then
      return false
    end
  end

  return true
end

local function dedent_lines(lines, indent)
  if not can_dedent(lines, indent) then
    return lines
  end

  return vim.tbl_map(function(line)
    if line:match("%S") then
      return line:sub(#indent + 1)
    end
    return line
  end, lines)
end

local function indent_lines(lines, indent)
  if indent == "" then
    return lines
  end

  return vim.tbl_map(function(line)
    if line == "" then
      return line
    end
    return indent .. line
  end, lines)
end

local function yaml_key_prefix_indent(line, start_col, end_col)
  local prefix = line:sub(1, start_col)
  local suffix = line:sub(end_col + 1)
  if suffix:match("%S") then
    return nil, nil
  end

  local indent = prefix:match("^(%s*)[%w_.-]+:%s*$")
  if not indent then
    return nil, nil
  end

  local trimmed_prefix = prefix:gsub("%s*$", "")
  return indent, #trimmed_prefix
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

function M.replace_range_with_command_output(binary, args, line1, line2, opts)
  opts = opts or {}
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  local base_indent = opts.preserve_indent and first_nonblank_indent(lines) or ""
  local input = opts.preserve_indent and dedent_lines(lines, base_indent) or lines

  run(binary, args, table.concat(input, "\n"), function(output)
    vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, indent_lines(output, base_indent))
  end)
end

function M.replace_text_with_command_output(binary, args, start_row, start_col, end_row, end_col, opts)
  opts = opts or {}
  local text = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  run(binary, args, table.concat(text, "\n"), function(output)
    if opts.yaml_inline_value and start_row == end_row and #output > 1 then
      local line = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1] or ""
      local parent_indent, replacement_start_col = yaml_key_prefix_indent(line, start_col, end_col)
      if parent_indent then
        local replacement = { "" }
        vim.list_extend(replacement, indent_lines(output, parent_indent .. "  "))
        vim.api.nvim_buf_set_text(0, start_row, replacement_start_col, end_row, end_col, replacement)
        return
      end
    end

    vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, output)
  end)
end

return M

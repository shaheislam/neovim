-- User commands for deterministic editor-native transformations.

local M = {}

local function parse_args(args)
  if args == "" then
    return { "." }
  end

  local parsed = {}
  local current = {}
  local quote = nil
  local escaped = false

  for i = 1, #args do
    local char = args:sub(i, i)

    if escaped then
      table.insert(current, char)
      escaped = false
    elseif char == "\\" then
      escaped = true
    elseif quote then
      if char == quote then
        quote = nil
      else
        table.insert(current, char)
      end
    elseif char == "'" or char == '"' then
      quote = char
    elseif char:match("%s") then
      if #current > 0 then
        table.insert(parsed, table.concat(current))
        current = {}
      end
    else
      table.insert(current, char)
    end
  end

  if escaped then
    table.insert(current, "\\")
  end

  if quote then
    vim.notify("Unclosed quote in filter command", vim.log.levels.ERROR, { title = "filter" })
    return nil
  end

  if #current > 0 then
    table.insert(parsed, table.concat(current))
  end

  return #parsed > 0 and parsed or { "." }
end

local function visual_text_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row = start_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_row = end_pos[2] - 1
  local end_col = end_pos[3]

  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ""
  if end_col > #end_line then
    end_col = #end_line
  end

  return start_row, start_col, end_row, end_col
end

local function run_filter_command(binary, cmd)
  local filter = require("config.filter")
  local args = parse_args(cmd.args)
  if not args then
    return
  end
  local opts = binary == "yq" and { preserve_indent = true, yaml_inline_value = true } or nil

  if cmd.range == 2 then
    local visual_start = vim.fn.line("'<")
    local visual_end = vim.fn.line("'>")
    local is_characterwise_visual = vim.fn.visualmode() == "v" and cmd.line1 == visual_start and cmd.line2 == visual_end
    if is_characterwise_visual then
      local start_row, start_col, end_row, end_col = visual_text_range()
      filter.replace_text_with_command_output(binary, args, start_row, start_col, end_row, end_col, opts)
    else
      filter.replace_range_with_command_output(binary, args, cmd.line1, cmd.line2, opts)
    end
    return
  end

  filter.replace_buffer_with_command_output(binary, args)
end

function M.setup()
  vim.api.nvim_create_user_command("JQ", function(cmd)
    run_filter_command("jq", cmd)
  end, {
    nargs = "*",
    range = true,
    complete = "shellcmdline",
    desc = "Run jq on the buffer or selection",
  })

  vim.api.nvim_create_user_command("YQ", function(cmd)
    run_filter_command("yq", cmd)
  end, {
    nargs = "*",
    range = true,
    complete = "shellcmdline",
    desc = "Run yq on the buffer or selection",
  })
end

return M

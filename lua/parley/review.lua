local M = {}

local namespace = vim.api.nvim_create_namespace("parley_review")
local marker_prefix = "㊷["

local function build_message(entry)
  local parts = { entry.text }

  if entry.question then
    table.insert(parts, "Question: " .. entry.question)
  end

  return table.concat(parts, " | ")
end

function M.parse_line(line, lnum)
  local entries = {}
  local start_col = 1

  while start_col <= #line do
    local marker_start = line:find(marker_prefix, start_col, true)
    if not marker_start then
      break
    end

    local text_start = marker_start + #marker_prefix
    local text_end = line:find("]", text_start, true)
    if not text_end then
      break
    end

    local text = vim.trim(line:sub(text_start, text_end - 1))
    local question
    local marker_end = text_end
    local next_col = text_end + 1

    while line:sub(next_col, next_col):match("%s") do
      next_col = next_col + 1
    end

    if line:sub(next_col, next_col) == "{" then
      local question_end = line:find("}", next_col + 1, true)
      if question_end then
        question = vim.trim(line:sub(next_col + 1, question_end - 1))
        marker_end = question_end
      end
    end

    table.insert(entries, {
      bufnr = nil,
      lnum = lnum,
      col = marker_start - 1,
      end_col = marker_end,
      text = text,
      question = question,
    })

    start_col = marker_end + 1
  end

  return entries
end

function M.collect(lines)
  local entries = {}

  for lnum, line in ipairs(lines) do
    vim.list_extend(entries, M.parse_line(line, lnum - 1))
  end

  return entries
end

function M.collect_from_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = M.collect(lines)

  for _, entry in ipairs(entries) do
    entry.bufnr = bufnr
  end

  return entries
end

function M.to_diagnostics(entries)
  local diagnostics = {}

  for _, entry in ipairs(entries) do
    table.insert(diagnostics, {
      lnum = entry.lnum,
      col = entry.col,
      end_col = entry.end_col,
      severity = entry.question and vim.diagnostic.severity.WARN or vim.diagnostic.severity.HINT,
      source = "parley-review",
      message = build_message(entry),
      user_data = {
        parley_review = entry,
      },
    })
  end

  return diagnostics
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local entries = M.collect_from_buf(bufnr)
  vim.diagnostic.set(namespace, bufnr, M.to_diagnostics(entries), {})
  return entries
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(namespace, bufnr)
end

function M.to_qf_items(entries)
  local items = {}

  for _, entry in ipairs(entries) do
    table.insert(items, {
      bufnr = entry.bufnr,
      lnum = entry.lnum + 1,
      col = entry.col + 1,
      text = build_message(entry),
    })
  end

  return items
end

function M.populate_quickfix(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}
  local entries = M.refresh(bufnr)
  local items = M.to_qf_items(entries)

  vim.fn.setqflist({}, " ", {
    title = "Parley Review",
    items = items,
  })

  if opts.open ~= false and #items > 0 then
    vim.cmd("copen")
  end

  return items
end

function M.has_markers(bufnr)
  return #M.collect_from_buf(bufnr) > 0
end

return M

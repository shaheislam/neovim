local M = {}

---@class ParleyReviewEntry
---@field bufnr? integer
---@field lnum integer
---@field col integer
---@field end_col integer
---@field text string
---@field question? string

---@class ParleyQuickfixOpts
---@field open? boolean

local namespace = vim.api.nvim_create_namespace("parley_review")
local marker_prefix = "㊷["
local augroup = vim.api.nvim_create_augroup("nvim_mini_parley_review", { clear = true })

---@param entry ParleyReviewEntry
---@return string
local function build_message(entry)
  local parts = { entry.text }

  if entry.question then
    table.insert(parts, "Question: " .. entry.question)
  end

  return table.concat(parts, " | ")
end

---@param line string
---@param lnum integer
---@return ParleyReviewEntry[]
function M.parse_line(line, lnum)
  ---@type ParleyReviewEntry[]
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

---@param lines string[]
---@return ParleyReviewEntry[]
function M.collect(lines)
  ---@type ParleyReviewEntry[]
  local entries = {}

  for lnum, line in ipairs(lines) do
    vim.list_extend(entries, M.parse_line(line, lnum - 1))
  end

  return entries
end

---@param bufnr? integer
---@return ParleyReviewEntry[]
function M.collect_from_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = M.collect(lines)

  for _, entry in ipairs(entries) do
    entry.bufnr = bufnr
  end

  return entries
end

---@param entries ParleyReviewEntry[]
---@return vim.Diagnostic[]
function M.to_diagnostics(entries)
  ---@type vim.Diagnostic[]
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

---@param bufnr? integer
---@return ParleyReviewEntry[]
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local entries = M.collect_from_buf(bufnr)
  vim.diagnostic.set(namespace, bufnr, M.to_diagnostics(entries), {})
  return entries
end

---@param bufnr? integer
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(namespace, bufnr)
end

---@param entries ParleyReviewEntry[]
---@return vim.quickfix.entry[]
function M.to_qf_items(entries)
  ---@type vim.quickfix.entry[]
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

---@param bufnr? integer
---@param opts? ParleyQuickfixOpts
---@return vim.quickfix.entry[]
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

---@param bufnr? integer
---@return boolean
function M.has_markers(bufnr)
  return #M.collect_from_buf(bufnr) > 0
end

---@param bufnr integer
---@return boolean
local function is_markdown_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "markdown"
end

---@param bufnr integer
local function refresh_buffer(bufnr)
  if not is_markdown_buffer(bufnr) then
    return
  end

  M.refresh(bufnr)
end

---@param bufnr integer
local function add_buffer_commands(bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, "ParleyReviewRefresh", function()
    M.refresh(bufnr)
  end, {
    desc = "Refresh Parley review markers",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "ParleyReviewQuickfix", function()
    M.populate_quickfix(bufnr)
  end, {
    desc = "Send Parley review markers to quickfix",
  })
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "markdown",
    callback = function(event)
      add_buffer_commands(event.buf)
      refresh_buffer(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "InsertLeave" }, {
    group = augroup,
    callback = function(event)
      refresh_buffer(event.buf)
    end,
  })
end

return M

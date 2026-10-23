local M = {}

function M.get(win)
  local saved = vim.w[win].nvim_mini_cursorline
  if saved ~= nil then
    return saved
  end
  return vim.wo[win].cursorline
end

function M.set(win, enabled)
  if win == vim.api.nvim_get_current_win() then
    vim.w[win].nvim_mini_cursorline = nil
    vim.wo[win].cursorline = enabled
  else
    vim.w[win].nvim_mini_cursorline = enabled
    vim.wo[win].cursorline = false
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("nvim_mini_cursorline", { clear = true })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      vim.w.nvim_mini_cursorline = vim.wo.cursorline
      vim.wo.cursorline = false
    end,
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      M.set(win, M.get(win))
    end,
  })
  vim.api.nvim_create_autocmd("TabNew", {
    group = group,
    callback = function()
      -- Tabs inherit window options after WinLeave has hidden the cursorline.
      local previous = vim.api.nvim_list_tabpages()[vim.fn.tabpagenr("#")]
      M.set(vim.api.nvim_get_current_win(), M.get(vim.api.nvim_tabpage_get_win(previous)))
    end,
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.set(win, M.get(win))
  end
end

return M

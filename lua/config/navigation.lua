-- Rex handles editor boundaries; these mappings only navigate editor windows.
local M = {}
function M.setup()
    local group = vim.api.nvim_create_augroup("nvim_mini_terminal_navigation", { clear = true })
    vim.api.nvim_create_autocmd("WinLeave", {
      group = group,
      desc = "Remember terminal-job mode before window navigation",
      callback = function(event)
        if vim.api.nvim_get_current_buf() ~= event.buf then
          return
        end

        if vim.bo[event.buf].buftype == "terminal" and vim.fn.mode() == "t" then
          vim.w.nvim_mini_terminal_navigation_buf = event.buf
        else
          vim.w.nvim_mini_terminal_navigation_buf = nil
        end
      end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
      group = group,
      desc = "Resume terminal-job mode after window navigation",
      callback = function(event)
        local resume_buf = vim.w.nvim_mini_terminal_navigation_buf
        vim.w.nvim_mini_terminal_navigation_buf = nil
        if
          vim.api.nvim_get_current_buf() == event.buf
          and vim.bo[event.buf].buftype == "terminal"
        then
          local ok, opencode = pcall(require, "config.opencode_terminal")
          -- OpenCode is a composer: entering it must accept typing even after Normal mode.
          if resume_buf == event.buf or (ok and opencode.is_buffer(event.buf)) then
            vim.cmd("startinsert")
          end
        end
      end,
    })
    for _, mapping in ipairs(M.keys) do
      vim.keymap.set(mapping.mode or "n", mapping[1], mapping[2], { desc = mapping.desc })
    end
end
M.keys = {
    -- Normal mode
    { "<c-h>", "<cmd>wincmd h<cr>", desc = "Navigate left" },
    { "<c-j>", "<cmd>wincmd j<cr>", desc = "Navigate down" },
    { "<c-k>", "<cmd>wincmd k<cr>", desc = "Navigate up" },
    { "<c-l>", "<cmd>wincmd l<cr>", desc = "Navigate right" },
    { "<c-\\>", "<cmd>wincmd p<cr>", desc = "Navigate to previous window" },
    -- <Cmd> executes without sending command text to the terminal job.
    { "<c-h>", "<cmd>wincmd h<cr>", mode = "t", desc = "Navigate left" },
    { "<c-j>", "<cmd>wincmd j<cr>", mode = "t", desc = "Navigate down" },
    { "<c-k>", "<cmd>wincmd k<cr>", mode = "t", desc = "Navigate up" },
    { "<c-l>", "<cmd>wincmd l<cr>", mode = "t", desc = "Navigate right" },
    { "<c-\\>", "<cmd>wincmd p<cr>", mode = "t", desc = "Navigate to previous window" },
}
return M

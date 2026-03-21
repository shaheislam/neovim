-- LSP Call Hierarchy Tree Viewer
--
-- Displays incoming or outgoing call chains as an interactive tree.
-- Equivalent to telescope-hierarchy.nvim but works without telescope.
--
-- Usage:
--   :LspIncomingCallsTree   - Show who calls the function under cursor
--   :LspOutgoingCallsTree   - Show what the function under cursor calls
--
-- Buffer keymaps:
--   <CR>  Jump to definition (in previous window)
--   o     Toggle expand/collapse node
--   q     Close the hierarchy buffer

local M = {}

local function get_short_path(uri)
  local path = vim.uri_to_fname(uri)
  local cwd = vim.fn.getcwd() .. "/"
  if path:sub(1, #cwd) == cwd then
    path = path:sub(#cwd + 1)
  end
  return path
end

local function make_node(item, from_ranges, depth)
  local range = item.selectionRange or item.range
  return {
    name = item.name,
    detail = item.detail or "",
    kind = item.kind,
    uri = item.uri,
    range = range,
    from_ranges = from_ranges,
    children = {},
    expanded = false,
    depth = depth or 0,
    -- Keep the original item for subsequent LSP requests
    _item = item,
  }
end

local function render_tree(nodes, lines, line_map, depth)
  depth = depth or 0
  lines = lines or {}
  line_map = line_map or {}

  for _, node in ipairs(nodes) do
    local indent = string.rep("  ", depth)
    local icon
    if #node.children > 0 or not node._resolved then
      icon = node.expanded and "▼" or "►"
    else
      icon = "·"
    end

    local location = ""
    if node.uri then
      local path = get_short_path(node.uri)
      local lnum = node.range and (node.range.start.line + 1) or ""
      location = string.format(" [%s:%s]", path, lnum)
    end

    local line = string.format("%s%s %s()%s", indent, icon, node.name, location)
    table.insert(lines, line)
    table.insert(line_map, node)

    if node.expanded and #node.children > 0 then
      render_tree(node.children, lines, line_map, depth + 1)
    end
  end

  return lines, line_map
end

local function refresh_buffer(buf, root_nodes, state)
  local lines, line_map = render_tree(root_nodes)
  state.line_map = line_map

  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Restore cursor if valid
  local max_line = #lines
  if cursor[1] > max_line then
    cursor[1] = max_line
  end
  if max_line > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
end

local function resolve_children(client, node, direction, bufnr, callback)
  local method = direction == "incoming"
    and "callHierarchy/incomingCalls"
    or "callHierarchy/outgoingCalls"

  local item = node._item
  client:request(method, { item = item }, function(err, result)
    if err or not result then
      callback({})
      return
    end

    local children = {}
    for _, call in ipairs(result) do
      local source = direction == "incoming" and call.from or call.to
      local from_ranges = call.fromRanges
      local child = make_node(source, from_ranges, node.depth + 1)
      table.insert(children, child)
    end
    callback(children)
  end, bufnr)
end

function M.show(direction)
  direction = direction or "incoming"

  local source_buf = vim.api.nvim_get_current_buf()
  local params = vim.lsp.util.make_position_params(0, "utf-16")

  local clients = vim.lsp.get_clients({
    bufnr = source_buf,
    method = "textDocument/prepareCallHierarchy",
  })

  if #clients == 0 then
    vim.notify("No LSP client supports call hierarchy", vim.log.levels.WARN)
    return
  end

  local client = clients[1]

  client:request("textDocument/prepareCallHierarchy", params, function(err, result)
    if err or not result or #result == 0 then
      vim.notify("No call hierarchy item found at cursor", vim.log.levels.WARN)
      return
    end

    vim.schedule(function()
      local root_item = result[1]
      local root_node = make_node(root_item, nil, 0)
      root_node.expanded = true

      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].filetype = "lsp-hierarchy"
      vim.bo[buf].modifiable = false

      local title = direction == "incoming" and "Incoming Calls" or "Outgoing Calls"
      vim.api.nvim_buf_set_name(buf, string.format("[%s] %s()", title, root_node.name))

      local state = { line_map = {} }
      local root_nodes = { root_node }

      -- Resolve first level of calls
      resolve_children(client, root_node, direction, source_buf, function(children)
        vim.schedule(function()
          root_node.children = children
          root_node._resolved = true

          -- Mark leaf nodes as resolved (no children to fetch)
          for _, child in ipairs(children) do
            child._resolved = false -- not yet resolved, can expand
          end

          refresh_buffer(buf, root_nodes, state)

          -- Open in a vertical split
          vim.cmd("botright vsplit")
          vim.api.nvim_win_set_buf(0, buf)
          vim.cmd("wincmd J") -- move to bottom for horizontal layout
          vim.cmd("resize 15")
          vim.wo.number = false
          vim.wo.relativenumber = false
          vim.wo.signcolumn = "no"
          vim.wo.cursorline = true
          vim.wo.wrap = false

          -- Jump to definition
          local function jump()
            local lnum = vim.fn.line(".")
            local node = state.line_map[lnum]
            if not node or not node.uri then return end

            local target_buf = vim.uri_to_bufnr(node.uri)
            vim.fn.bufload(target_buf)
            vim.cmd("wincmd p")
            vim.api.nvim_win_set_buf(0, target_buf)
            if node.range then
              vim.api.nvim_win_set_cursor(0, {
                node.range.start.line + 1,
                node.range.start.character,
              })
              vim.cmd("normal! zz")
            end
          end

          -- Toggle expand/collapse
          local function toggle()
            local lnum = vim.fn.line(".")
            local node = state.line_map[lnum]
            if not node then return end

            if node.expanded then
              node.expanded = false
              refresh_buffer(buf, root_nodes, state)
            elseif node._resolved then
              node.expanded = true
              refresh_buffer(buf, root_nodes, state)
            else
              -- Resolve children on first expand
              resolve_children(client, node, direction, source_buf, function(children)
                vim.schedule(function()
                  node.children = children
                  node._resolved = true
                  node.expanded = true
                  for _, child in ipairs(children) do
                    child._resolved = false
                  end
                  refresh_buffer(buf, root_nodes, state)
                end)
              end)
            end
          end

          local bopts = { buffer = buf, nowait = true, silent = true }
          vim.keymap.set("n", "<CR>", jump, bopts)
          vim.keymap.set("n", "o", toggle, bopts)
          vim.keymap.set("n", "q", "<cmd>close<cr>", bopts)
          vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", bopts)
        end)
      end)
    end)
  end, source_buf)
end

function M.incoming() M.show("incoming") end
function M.outgoing() M.show("outgoing") end

return M

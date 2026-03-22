-- LSP Call Hierarchy Tree Viewer
--
-- Displays incoming or outgoing call chains as an interactive tree.
-- Equivalent to telescope-hierarchy.nvim but works without telescope.
--
-- Usage:
--   :LspIncomingCallsTree [depth]  - Show who calls the function under cursor
--   :LspOutgoingCallsTree [depth]  - Show what the function under cursor calls
--
-- Buffer keymaps:
--   <CR>  Jump to call site (in source window)
--   o     Toggle expand/collapse node
--   q     Close the hierarchy buffer

local M = {}

-- ── Constants ────────────────────────────────────────────────────────
local ns = vim.api.nvim_create_namespace("lsp_hierarchy_hl")

---@type table<integer, {[1]: string, [2]: string}>
local KIND_ICONS = {
  [1]  = { "󰈔 ", "Structure" },            -- File
  [2]  = { "󰆧 ", "Structure" },            -- Module
  [3]  = { "󰅪 ", "Structure" },            -- Namespace
  [4]  = { "󰏗 ", "Structure" },            -- Package
  [5]  = { " ", "@lsp.type.class" },       -- Class
  [6]  = { " ", "@lsp.type.method" },      -- Method
  [7]  = { " ", "Identifier" },            -- Property
  [8]  = { "󰜢 ", "Identifier" },            -- Field
  [9]  = { " ", "@constructor" },          -- Constructor
  [10] = { " ", "@lsp.type.enum" },        -- Enum
  [11] = { " ", "Type" },                  -- Interface
  [12] = { "󰊕 ", "Function" },              -- Function
  [13] = { " ", "@variable" },             -- Variable
  [14] = { "󰏿 ", "@constant" },             -- Constant
  [15] = { " ", "String" },                -- String
  [16] = { "󰎠 ", "Number" },                -- Number
  [17] = { "◩ ", "Boolean" },               -- Boolean
  [18] = { " ", "Type" },                  -- Array
  [19] = { " ", "Type" },                  -- Object
  [20] = { "󰌋 ", "Identifier" },            -- Key
  [21] = { "󰟢 ", "Comment" },               -- Null
  [22] = { " ", "@lsp.type.enumMember" },  -- EnumMember
  [23] = { "󰙅 ", "Structure" },             -- Struct
  [24] = { " ", "Special" },               -- Event
  [25] = { "󰆕 ", "Operator" },              -- Operator
  [26] = { " ", "Type" },                  -- TypeParameter
}
local KIND_FALLBACK = { "? ", "NonText" }

local GUIDE_MID    = "├─ "
local GUIDE_LAST   = "└─ "
local GUIDE_NESTED = "│  "
local GUIDE_SPACE  = "   "

-- ── Helpers ──────────────────────────────────────────────────────────
local function get_short_path(uri)
  local path = vim.uri_to_fname(uri)
  local cwd = vim.fn.getcwd() .. "/"
  if path:sub(1, #cwd) == cwd then
    path = path:sub(#cwd + 1)
  end
  return path
end

--- Returns the best navigation position for a node: call site (from_ranges)
--- first, falling back to the symbol's selection/definition range.
local function get_nav_position(node)
  if node.from_ranges and node.from_ranges[1] then
    return node.from_ranges[1].start
  end
  if node.range then
    return node.range.start
  end
  return nil
end

--- Converts an LSP position to a Neovim cursor tuple {1-indexed line, byte col},
--- respecting the client's offset encoding (utf-8/utf-16/utf-32).
local function lsp_pos_to_cursor(target_buf, pos, offset_encoding)
  local row = pos.line + 1
  if pos.character == 0 then
    return { row, 0 }
  end
  -- _get_line_byte_from_position handles encoding conversion internally
  local ok, byte_col = pcall(
    vim.lsp.util._get_line_byte_from_position,
    target_buf, pos, offset_encoding
  )
  if ok then
    return { row, byte_col }
  end
  return { row, pos.character }
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

-- ── Tree rendering ───────────────────────────────────────────────────

--- Renders the tree into lines with extmark highlight data.
---@param nodes table[]
---@param lines string[]
---@param line_map table[]
---@param extmarks table[][] array of {col_start, col_end, hl_group} per line
---@param last_flags table<integer, boolean> tracks which ancestor depths were last-child
local function render_tree(nodes, lines, line_map, extmarks, last_flags)
  last_flags = last_flags or {}
  lines = lines or {}
  line_map = line_map or {}
  extmarks = extmarks or {}

  for i, node in ipairs(nodes) do
    local depth = node.depth
    local is_last = (i == #nodes)
    local line_extmarks = {}
    local col = 0

    -- Build guide prefix for ancestor levels
    local prefix = ""
    for d = 1, depth - 1 do
      local guide = last_flags[d] and GUIDE_SPACE or GUIDE_NESTED
      prefix = prefix .. guide
    end

    -- Connector (root nodes have none)
    local connector = ""
    if depth > 0 then
      connector = is_last and GUIDE_LAST or GUIDE_MID
    end

    local guide_str = prefix .. connector
    if #guide_str > 0 then
      table.insert(line_extmarks, { col, col + #guide_str, "NonText" })
      col = col + #guide_str
    end

    local line

    if node._loading then
      -- Synthetic loading placeholder
      local text = "⟳ loading..."
      table.insert(line_extmarks, { col, col + #text, "Comment" })
      line = guide_str .. text

    elseif node._error then
      -- Synthetic error placeholder
      local text = "✗ " .. (node._error_msg or "error resolving calls")
      table.insert(line_extmarks, { col, col + #text, "DiagnosticError" })
      line = guide_str .. text

    else
      -- Toggle icon
      local toggle_icon
      if #node.children > 0 or not node._resolved then
        toggle_icon = node.expanded and "▼ " or "► "
      else
        toggle_icon = "· "
      end
      local toggle_hl = toggle_icon == "· " and "NonText" or "Special"
      table.insert(line_extmarks, { col, col + #toggle_icon, toggle_hl })
      col = col + #toggle_icon

      -- Kind icon
      local kind_entry = KIND_ICONS[node.kind] or KIND_FALLBACK
      local kind_str = kind_entry[1]
      table.insert(line_extmarks, { col, col + #kind_str, kind_entry[2] })
      col = col + #kind_str

      -- Function name
      local name_str = node.name .. "()"
      table.insert(line_extmarks, { col, col + #name_str, "Function" })
      col = col + #name_str

      -- Location: show call site line (from_ranges) when available
      local location = ""
      if node.uri then
        local path = get_short_path(node.uri)
        local nav_pos = get_nav_position(node)
        local lnum = nav_pos and (nav_pos.line + 1) or ""
        location = string.format(" [%s:%s]", path, lnum)
        table.insert(line_extmarks, { col, col + #location, "Comment" })
      end

      line = guide_str .. toggle_icon .. kind_str .. name_str .. location
    end

    table.insert(lines, line)
    table.insert(line_map, node)
    table.insert(extmarks, line_extmarks)

    -- Recurse into expanded children
    if node.expanded and #node.children > 0 then
      local old = last_flags[depth]
      last_flags[depth] = is_last
      render_tree(node.children, lines, line_map, extmarks, last_flags)
      last_flags[depth] = old
    end
  end

  return lines, line_map, extmarks
end

-- ── Buffer management ────────────────────────────────────────────────
local function refresh_buffer(buf, root_nodes, state)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines, line_map, ext = render_tree(root_nodes)
  state.line_map = line_map

  -- Save cursor from the hierarchy window (not window 0)
  local win = state.hier_win
  local cursor = { 1, 0 }
  if win and vim.api.nvim_win_is_valid(win) then
    local ok, pos = pcall(vim.api.nvim_win_get_cursor, win)
    if ok then cursor = pos end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply extmark highlights
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for line_idx, line_ext in ipairs(ext) do
    for _, e in ipairs(line_ext) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, line_idx - 1, e[1], {
        end_col = e[2],
        hl_group = e[3],
      })
    end
  end

  -- Restore cursor in the hierarchy window only
  local max_line = #lines
  if cursor[1] > max_line then
    cursor[1] = max_line
  end
  if max_line > 0 and win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
  end
end

-- ── LSP resolution ───────────────────────────────────────────────────
local function resolve_children(client, node, direction, bufnr, callback)
  local method = direction == "incoming"
    and "callHierarchy/incomingCalls"
    or "callHierarchy/outgoingCalls"

  local item = node._item
  client:request(method, { item = item }, function(err, result)
    if err then
      callback(nil, err)
      return
    end
    if not result then
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

--- Recursively resolves children up to max_depth levels using async fan-out.
local function resolve_to_depth(client, node, direction, bufnr, max_depth, callback)
  if node.depth >= max_depth then
    callback()
    return
  end

  resolve_children(client, node, direction, bufnr, function(children, err)
    if err or not children then
      node.children = {}
      node._resolved = true
      callback()
      return
    end

    node.children = children
    node._resolved = true
    node.expanded = true

    -- Count children that need further resolution
    local pending = 0
    for _, child in ipairs(children) do
      child._resolved = false
      if node.depth + 1 < max_depth then
        pending = pending + 1
      end
    end

    if pending == 0 then
      callback()
      return
    end

    local completed = 0
    for _, child in ipairs(children) do
      if node.depth + 1 < max_depth then
        resolve_to_depth(client, child, direction, bufnr, max_depth, function()
          completed = completed + 1
          if completed == pending then
            callback()
          end
        end)
      end
    end
  end)
end

-- ── Main entry ───────────────────────────────────────────────────────
function M.show(direction, opts)
  direction = direction or "incoming"
  opts = opts or {}
  local max_depth = opts.depth or 2

  local source_buf = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
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
  local offset_encoding = client.offset_encoding or "utf-16"

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

      local state = { line_map = {}, last_preview = nil }
      local root_nodes = { root_node }

      --- Navigate source_win to a node's call site (or definition fallback).
      local function navigate_to_node(node, focus)
        if not node or not node.uri then return end
        if not vim.api.nvim_win_is_valid(source_win) then return end

        local nav_pos = get_nav_position(node)
        if not nav_pos then return end

        local target_buf = vim.uri_to_bufnr(node.uri)
        vim.fn.bufload(target_buf)

        if focus then
          vim.api.nvim_set_current_win(source_win)
        end

        vim.api.nvim_win_call(source_win, function()
          vim.api.nvim_win_set_buf(source_win, target_buf)
          local cursor = lsp_pos_to_cursor(target_buf, nav_pos, offset_encoding)
          vim.api.nvim_win_set_cursor(source_win, cursor)
          vim.cmd("normal! zz")
        end)
      end

      -- Resolve to configured depth, then display
      resolve_to_depth(client, root_node, direction, source_buf, max_depth, function()
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end

          refresh_buffer(buf, root_nodes, state)

          -- Open in a horizontal split at bottom
          vim.cmd("botright vsplit")
          vim.api.nvim_win_set_buf(0, buf)
          vim.cmd("wincmd J")
          vim.cmd("resize 15")
          vim.wo.number = false
          vim.wo.relativenumber = false
          vim.wo.signcolumn = "no"
          vim.wo.cursorline = true
          vim.wo.wrap = false

          -- Store hierarchy window for targeted cursor operations
          state.hier_win = vim.api.nvim_get_current_win()

          -- Auto-preview: show call site in source window on cursor move.
          -- Debounced (30ms) so holding j/k doesn't thrash the source window.
          local preview_timer = vim.uv.new_timer()

          vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            once = true,
            callback = function()
              preview_timer:stop()
              preview_timer:close()
            end,
          })

          vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = buf,
            callback = function()
              preview_timer:stop()
              if not vim.api.nvim_win_is_valid(source_win) then return end

              preview_timer:start(30, 0, vim.schedule_wrap(function()
                if not vim.api.nvim_buf_is_valid(buf) then return end
                if not vim.api.nvim_win_is_valid(source_win) then return end

                local lnum = vim.fn.line(".")
                local node = state.line_map[lnum]
                if not node or not node.uri or node._loading or node._error then return end

                -- Dedup: skip if exact same target (uri + line + character)
                local nav_pos = get_nav_position(node)
                local preview_key = node.uri
                  .. ":" .. (nav_pos and nav_pos.line or -1)
                  .. ":" .. (nav_pos and nav_pos.character or -1)
                if state.last_preview == preview_key then return end
                state.last_preview = preview_key

                pcall(navigate_to_node, node, false)
              end))
            end,
          })

          -- Jump to call site (focuses source window)
          local function jump()
            local lnum = vim.fn.line(".")
            local node = state.line_map[lnum]
            navigate_to_node(node, true)
          end

          -- Toggle expand/collapse
          local function toggle()
            local lnum = vim.fn.line(".")
            local node = state.line_map[lnum]
            if not node or node._loading or node._error then return end

            if node.expanded then
              node.expanded = false
              refresh_buffer(buf, root_nodes, state)
            elseif node._resolved then
              node.expanded = true
              refresh_buffer(buf, root_nodes, state)
            else
              -- Show loading indicator immediately
              node.children = { {
                _loading = true,
                name = "loading...",
                depth = node.depth + 1,
                children = {},
              } }
              node.expanded = true
              refresh_buffer(buf, root_nodes, state)

              -- Tag this resolve so stale responses are ignored
              node._resolve_gen = (node._resolve_gen or 0) + 1
              local my_gen = node._resolve_gen

              -- Resolve children asynchronously
              resolve_children(client, node, direction, source_buf, function(children, resolve_err)
                vim.schedule(function()
                  if not vim.api.nvim_buf_is_valid(buf) then return end
                  if node._resolve_gen ~= my_gen then return end

                  if resolve_err then
                    node.children = { {
                      _error = true,
                      _error_msg = tostring(resolve_err),
                      name = "error",
                      depth = node.depth + 1,
                      children = {},
                    } }
                  else
                    node.children = children or {}
                    for _, child in ipairs(node.children) do
                      child._resolved = false
                    end
                  end
                  node._resolved = true
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

function M.incoming(opts) M.show("incoming", opts) end
function M.outgoing(opts) M.show("outgoing", opts) end

return M

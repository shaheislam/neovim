local M = {}

local review_context = require("config.review_context")

local ns = vim.api.nvim_create_namespace("repo_annotations")
local icon = "󰅺"
local max_ghost_length = 80
local post_instruction =
	"after resolving each annotation, edit the item from annotation file and prepend the annotation with 'RESOLVED: '"
local root_cache = {}
local annotation_cache = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Annotate" })
end

local function active_annotations(items)
	return vim.tbl_filter(function(item)
		return type(item.text) == "string" and not item.text:match("^RESOLVED:")
	end, items)
end

local function current_buffer_path(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr or 0)
	if path == "" or path:match("^annotate://") then
		return nil
	end

	local diffview_path = path:match("^diffview://(/.*)$")
	if diffview_path then
		return vim.fn.fnamemodify(diffview_path, ":p"), true
	end

	return vim.fn.fnamemodify(path, ":p"), false
end

local function should_skip_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return true
	end

	if vim.b[bufnr].nvim_mini_large_file then
		return true
	end

	local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
	if buftype ~= "" then
		return true
	end

	return current_buffer_path(bufnr) == nil
end

local function repo_root(path)
	path = path or current_buffer_path() or vim.fn.getcwd()

	local start = vim.fn.fnamemodify(path, ":p")
	if vim.fn.isdirectory(start) ~= 1 then
		start = vim.fn.fnamemodify(start, ":h")
	end

	local cached = root_cache[start]
	if cached ~= nil then
		return cached or nil
	end

	local git_dir = vim.fs.find(".git", { path = start, upward = true })[1]
	if git_dir then
		local root = vim.fn.fnamemodify(git_dir, ":h")
		root_cache[start] = root
		return root
	end

	local root = vim.fn.system({ "git", "-C", start, "rev-parse", "--show-toplevel" })
	if vim.v.shell_error == 0 then
		root_cache[start] = vim.trim(root)
		return root_cache[start]
	end
	return nil
end

local function annotations_path(root)
	return root .. "/.tmp/annotations.json"
end

local function relative_path(path, root)
	local absolute = vim.fn.fnamemodify(path, ":p")
	local normalized_root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")

	if absolute:sub(1, #normalized_root + 1) == normalized_root .. "/" then
		return absolute:sub(#normalized_root + 2)
	end

	return absolute
end

local function annotation_filename(path, root, is_diffview)
	local filename = relative_path(path, vim.fn.getcwd())
	if filename == vim.fn.fnamemodify(path, ":p") then
		filename = relative_path(path, root)
	end

	if is_diffview then
		local worktree_filename = filename:match("^%.git/worktrees/[^/]+/[^/]+/(.+)$")
		if worktree_filename then
			return worktree_filename
		end

		local git_filename = filename:match("^%.git/[^/]+/(.+)$")
		if git_filename then
			return git_filename
		end

		filename = filename:gsub("^[^/]+/", "", 1)
	end

	return filename
end

local function current_file(root, bufnr)
	bufnr = bufnr or 0
	local path, is_diffview = current_buffer_path(bufnr)
	if not path then
		return nil
	end
	return annotation_filename(path, root, is_diffview), is_diffview
end

function M.diff_side(bufnr, winid)
	bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
	winid = winid or vim.api.nvim_get_current_win()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return nil
	end

	local views = {}
	local current = lib.get_current_view()
	if current then
		table.insert(views, current)
	end
	for _, view in pairs(lib.views or {}) do
		if view ~= current then
			table.insert(views, view)
		end
	end

	for _, view in ipairs(views) do
		local windows = view.cur_layout and view.cur_layout.windows or {}
		for _, window in ipairs(windows) do
			local file = window.file
			if (window.id == winid or (file and file.bufnr == bufnr)) and file then
				if file.symbol == "a" then
					return "old"
				elseif file.symbol == "b" then
					return "new"
				end
			end
		end
	end
	return nil
end

local function read_annotations(root)
	local path = annotations_path(root)
	if vim.fn.filereadable(path) == 0 then
		annotation_cache[root] = nil
		return {}
	end

	local stat = vim.uv.fs_stat(path)
	local mtime = stat and stat.mtime and string.format("%s:%s", stat.mtime.sec, stat.mtime.nsec) or "0:0"
	local size = stat and stat.size or 0
	local cached = annotation_cache[root]
	if cached and cached.mtime == mtime and cached.size == size then
		return vim.deepcopy(cached.items)
	end

	local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(decoded) ~= "table" then
		return {}
	end
	annotation_cache[root] = { mtime = mtime, size = size, items = decoded }
	return vim.deepcopy(decoded)
end

local function write_annotations(root, annotations)
	local dir = root .. "/.tmp"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	vim.fn.writefile(vim.split(vim.json.encode(annotations), "\n"), annotations_path(root))
	annotation_cache[root] = nil
end

local function diff_for_file(root, file)
	local result = vim.system({ "git", "-C", root, "diff", "--no-color", "--unified=3", "HEAD", "--", file }, {
		text = true,
	}):wait()
	local diff = result.stdout or ""
	if diff ~= "" then
		return diff
	end

	local absolute = root .. "/" .. file
	if vim.fn.filereadable(absolute) ~= 1 then
		return ""
	end
	local untracked = vim.system({ "git", "-C", root, "ls-files", "--error-unmatch", "--", file }, { text = true }):wait()
	if untracked.code == 0 then
		return ""
	end

	local new_file = vim.system({
		"git",
		"-C",
		root,
		"diff",
		"--no-index",
		"--no-color",
		"--unified=3",
		"/dev/null",
		absolute,
	}, { text = true }):wait()
	return new_file.stdout or ""
end

local function hunk_for_range(root, file, start_line, end_line, side)
	return review_context.hunk_for_range(diff_for_file(root, file), start_line, end_line, side)
end

local function truncate(text)
	text = text:gsub("%s+", " ")
	if #text <= max_ghost_length then
		return text
	end
	return text:sub(1, max_ghost_length - 1) .. "…"
end

function M.refresh_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if should_skip_buffer(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local root = repo_root(vim.api.nvim_buf_get_name(bufnr))
	if not root then
		return
	end
	local file, is_diffview = current_file(root, bufnr)
	if not file then
		return
	end
	local side = M.diff_side(bufnr) or (is_diffview and "old" or "new")

	for _, item in ipairs(read_annotations(root)) do
		if
			review_context.item_matches(item, file, item.line, side)
			and type(item.text) == "string"
			and not item.text:match("^RESOLVED:")
		then
			local line = math.max((item.line or 1) - 1, 0)
			vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
				sign_text = icon,
				sign_hl_group = "DiagnosticSignInfo",
				virt_text = { { icon .. " " .. truncate(item.text), "DiagnosticVirtualTextInfo" } },
				virt_text_pos = "eol",
			})
		end
	end
end

function M.refresh_all()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			M.refresh_buffer(bufnr)
		end
	end
end

local function add_range(start_line, end_line)
	local root = repo_root()
	if not root then
		vim.notify("Annotations require a git repository", vim.log.levels.WARN)
		return
	end

	local file, is_diffview = current_file(root)
	if not file then
		vim.notify("Annotations require a repo-local file", vim.log.levels.WARN)
		return
	end

	local side = M.diff_side(0) or (is_diffview and "old" or "new")
	local annotations = read_annotations(root)
	local existing
	for _, item in ipairs(annotations) do
		if review_context.item_matches(item, file, start_line, side) then
			existing = item
			break
		end
	end

	vim.ui.input({ prompt = "Annotation: ", default = existing and existing.text or "" }, function(text)
		if not text or text == "" then
			return
		end
		if existing then
			existing.text = text
			existing.line = start_line
			existing.end_line = end_line
			existing.side = side
			existing.hunk = hunk_for_range(root, file, start_line, end_line, side)
		else
			table.insert(annotations, {
				file = file,
				line = start_line,
				end_line = end_line,
				text = text,
				side = side,
				hunk = hunk_for_range(root, file, start_line, end_line, side),
			})
		end
		write_annotations(root, annotations)
		M.refresh_all()
	end)
end

function M.add_current()
	local line = math.max(vim.api.nvim_win_get_cursor(0)[1], 1)
	add_range(line, line)
end

function M.add_visual()
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	add_range(start_line, end_line)
end

function M.delete_current()
	local root = repo_root()
	if not root then
		return
	end
	local file, is_diffview = current_file(root)
	if not file then
		return
	end
	local line = math.max(vim.api.nvim_win_get_cursor(0)[1], 1)
	local side = M.diff_side(0) or (is_diffview and "old" or "new")
	local annotations = vim.tbl_filter(function(item)
		return not review_context.item_matches(item, file, line, side)
	end, read_annotations(root))
	write_annotations(root, annotations)
	M.refresh_all()
end

function M.delete_all()
	local root = repo_root()
	if not root then
		return
	end
	write_annotations(root, {})
	M.refresh_all()
end

local function format_item(item)
	return review_context.format_item(item)
end

local function copy_items(items)
	local text = M.prompt_for_items(items)
	if not text then
		return
	end

	vim.fn.setreg("+", text)
	notify("Copied " .. #items .. " annotation(s)")
end

function M.prompt_for_items(items)
	if #items == 0 then
		notify("No annotations to copy", vim.log.levels.INFO)
		return nil
	end

	return review_context.prompt_for_items(items, post_instruction)
end

local function ask_items(items, root)
	local prompt = M.prompt_for_items(items)
	if not prompt then
		return
	end

	require("config.opencode_http").append_prompt(prompt, {
		title = "Annotate",
		success = "Sent " .. #items .. " annotation(s) to OpenCode",
		fallback_clipboard = true,
		dir = root or (items[1] and items[1].root),
	})
end

function M.copy_current()
	local root = repo_root()
	if not root then
		return
	end
	local file, is_diffview = current_file(root)
	if not file then
		return
	end
	local line = math.max(vim.api.nvim_win_get_cursor(0)[1], 1)
	local side = M.diff_side(0) or (is_diffview and "old" or "new")
	local items = vim.tbl_filter(function(item)
		return review_context.item_matches(item, file, line, side)
	end, active_annotations(read_annotations(root)))
	copy_items(items)
end

function M.copy_all()
	local root = repo_root()
	if not root then
		return
	end
	copy_items(active_annotations(read_annotations(root)))
end

function M.ask_current()
	local root = repo_root()
	if not root then
		return
	end
	local file, is_diffview = current_file(root)
	if not file then
		return
	end
	local line = math.max(vim.api.nvim_win_get_cursor(0)[1], 1)
	local side = M.diff_side(0) or (is_diffview and "old" or "new")
	local items = vim.tbl_filter(function(item)
		return review_context.item_matches(item, file, line, side)
	end, active_annotations(read_annotations(root)))
	ask_items(items, root)
end

function M.ask_all()
	local root = repo_root()
	if not root then
		return
	end
	ask_items(active_annotations(read_annotations(root)), root)
end

function M.qflist()
	local root = repo_root()
	if not root then
		return
	end
	local annotations = active_annotations(read_annotations(root))
	local items = {}
	for _, item in ipairs(annotations) do
		table.insert(items, {
			filename = root .. "/" .. item.file,
			lnum = item.line,
			end_lnum = item.end_line,
			text = item.text,
		})
	end
	vim.fn.setqflist({}, " ", { title = "Annotations", items = items })
	vim.cmd.copen()
end

local function selected_panel_item(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	return vim.b[bufnr].annotation_items and vim.b[bufnr].annotation_items[line]
end

local function close_panel_window()
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

local function jump_to_item(item)
	if not item then
		return
	end
	close_panel_window()
	vim.cmd.edit(vim.fn.fnameescape(item.root .. "/" .. item.file))
	vim.api.nvim_win_set_cursor(0, { item.line, 0 })
end

local function delete_item(item)
	if not item then
		return
	end
	local annotations = vim.tbl_filter(function(candidate)
		return not (candidate.file == item.file and candidate.line == item.line and candidate.text == item.text)
	end, read_annotations(item.root))
	write_annotations(item.root, annotations)
	M.refresh_all()
	M.list()
end

local function edit_item(item)
	if not item then
		return
	end
	vim.ui.input({ prompt = "Annotation: ", default = item.text }, function(text)
		if not text or text == "" then
			return
		end
		local annotations = read_annotations(item.root)
		for _, candidate in ipairs(annotations) do
			if candidate.file == item.file and candidate.line == item.line and candidate.text == item.text then
				candidate.text = text
				break
			end
		end
		write_annotations(item.root, annotations)
		M.refresh_all()
		M.list()
	end)
end

function M.list()
	local root = repo_root()
	if not root then
		return
	end

	local annotations = active_annotations(read_annotations(root))
	if #annotations == 0 then
		notify("No annotations", vim.log.levels.INFO)
		return
	end

	local width = math.min(math.max(math.floor(vim.o.columns * 0.75), 60), vim.o.columns - 4)
	local height = math.min(math.max(#annotations + 2, 8), math.max(vim.o.lines - 6, 8))
	local row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0)
	local col = math.max(math.floor((vim.o.columns - width) / 2), 0)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local lines = {}
	local items = {}

	for _, item in ipairs(annotations) do
		local panel_item = vim.tbl_extend("force", { root = root }, item)
		table.insert(items, panel_item)
		table.insert(lines, format_item(item))
	end

	vim.api.nvim_buf_set_name(bufnr, "annotate://list")
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].filetype = "annotate"
	vim.b[bufnr].annotation_items = items

	local win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		border = "rounded",
		title = " Annotations ",
		title_pos = "center",
		style = "minimal",
	})
	vim.wo[win].cursorline = true

	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end

	map("q", close_panel_window, "Close annotations")
	map("<Esc>", close_panel_window, "Close annotations")
	map("<CR>", function()
		jump_to_item(selected_panel_item(bufnr))
	end, "Open annotation")
	map("o", function()
		jump_to_item(selected_panel_item(bufnr))
	end, "Open annotation")
	map("e", function()
		edit_item(selected_panel_item(bufnr))
	end, "Edit annotation")
	map("d", function()
		delete_item(selected_panel_item(bufnr))
	end, "Delete annotation")
	map("c", function()
		local item = selected_panel_item(bufnr)
		if item then
			copy_items({ item })
		end
	end, "Copy annotation")
	map("a", function()
		local item = selected_panel_item(bufnr)
		if item then
			ask_items({ item }, item.root)
		end
	end, "Ask OpenCode")
	map("A", function()
		ask_items(items, root)
	end, "Ask OpenCode about all")
	map("?", function()
		notify("Keys: <CR>/o open, e edit, d delete, c copy, a ask, A ask all, q close")
	end, "Annotation help")
end

local function jump(direction)
	local root = repo_root()
	if not root then
		return
	end
	local file, is_diffview = current_file(root)
	if not file then
		return
	end
	local line = math.max(vim.api.nvim_win_get_cursor(0)[1], 1)
	local side = M.diff_side(0) or (is_diffview and "old" or "new")
	local matches = vim.tbl_filter(function(item)
		return item.file == file and (not item.side or item.side == side)
	end, read_annotations(root))
	table.sort(matches, function(a, b)
		return (a.line or 1) < (b.line or 1)
	end)
	if #matches == 0 then
		return
	end

	local target = matches[1]
	if direction < 0 then
		target = matches[#matches]
	end
	for _, item in ipairs(matches) do
		if direction > 0 and item.line > line then
			target = item
			break
		elseif direction < 0 and item.line < line then
			target = item
		end
	end
	vim.api.nvim_win_set_cursor(0, { target.line, 0 })
end

function M.next()
	jump(1)
end

function M.prev()
	jump(-1)
end

function M.setup()
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
		group = vim.api.nvim_create_augroup("repo_annotations", { clear = true }),
		callback = function(args)
			M.refresh_buffer(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("repo_annotations_external", { clear = true }),
		pattern = "NvimMiniExternalFilesChanged",
		callback = M.refresh_all,
		desc = "Refresh annotations after external agent edits",
	})

	vim.api.nvim_create_user_command("Annotate", function(opts)
		local action = opts.fargs[1] or "add"
		if action == "add" then
			M.add_current()
		elseif action == "copy" then
			M.copy_current()
		elseif action == "copyall" then
			M.copy_all()
		elseif action == "ask" then
			M.ask_current()
		elseif action == "askall" then
			M.ask_all()
		elseif action == "list" then
			M.list()
		elseif action == "qflist" then
			M.qflist()
		elseif action == "delete" then
			M.delete_current()
		elseif action == "deleteall" then
			M.delete_all()
		else
			vim.notify("Unknown Annotate action: " .. action, vim.log.levels.ERROR)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "add", "copy", "copyall", "ask", "askall", "list", "qflist", "delete", "deleteall" }
		end,
	})

	vim.keymap.set("n", "<leader>ana", M.add_current, { desc = "Add annotation" })
	vim.keymap.set("x", "<leader>ana", M.add_visual, { desc = "Add annotation" })
	vim.keymap.set("n", "<leader>anc", M.copy_current, { desc = "Copy annotation" })
	vim.keymap.set("n", "<leader>anC", M.copy_all, { desc = "Copy all annotations" })
	vim.keymap.set("n", "<leader>ano", M.ask_current, { desc = "Ask OpenCode about annotation" })
	vim.keymap.set("n", "<leader>anO", M.ask_all, { desc = "Ask OpenCode about all annotations" })
	vim.keymap.set("n", "<leader>anl", M.list, { desc = "List annotations" })
	vim.keymap.set("n", "<leader>and", M.delete_current, { desc = "Delete annotation" })
	vim.keymap.set("n", "<leader>anD", M.delete_all, { desc = "Delete all annotations" })
	vim.keymap.set("n", "]a", M.next, { desc = "Next annotation" })
	vim.keymap.set("n", "[a", M.prev, { desc = "Previous annotation" })
end

return M

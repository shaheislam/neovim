local M = {}

local review_context = require("config.review_context")

local ns = vim.api.nvim_create_namespace("repo_annotations")
local icon = "󰅺"
local max_ghost_length = 80
local post_instruction =
	"After resolving each annotation, edit its item in .tmp/annotations.json and prepend item.text with 'RESOLVED: '. Preserve the other items and fields."
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
	if buftype ~= "" and not vim.api.nvim_buf_get_name(bufnr):match("^diffview://") then
		return true
	end

	return current_buffer_path(bufnr) == nil
end

local function diff_file(bufnr)
	bufnr = (not bufnr or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end
	for _, view in pairs(lib.views or {}) do
		for _, window in ipairs(view.cur_layout and view.cur_layout.windows or {}) do
			if window.file and window.file.bufnr == bufnr then
				return window.file, view
			end
		end
	end
end

local function repo_root(path)
	local file = diff_file(path and vim.fn.bufnr(path) or 0)
	if file and file.adapter and file.adapter.ctx then
		return file.adapter.ctx.toplevel
	end
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
	local file = diff_file(bufnr)
	if file and file.path then
		return file.path, file.symbol == "a"
	end
	local path, is_diffview = current_buffer_path(bufnr)
	if not path then
		return nil
	end
	return annotation_filename(path, root, is_diffview), is_diffview
end

function M.diff_side(bufnr)
	local file = diff_file(bufnr)
	if file then
		return ({ a = "old", b = "new", c = "theirs", d = "base" })[file.symbol]
	end
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

local function diff_for_file(root, file, base, comparison, side)
	local args = { "git", "-C", root, "diff", "--no-color", "--unified=3" }
	local a = comparison and comparison[side == "theirs" and "c" or side == "base" and "d" or "a"]
	local b = comparison and comparison.b
	if a and b then
		if a.type == 2 and b.type == 2 then
			vim.list_extend(args, { a.commit, b.commit })
		elseif a.type == 2 and b.type == 3 and b.stage == 0 then
			vim.list_extend(args, { "--cached", a.commit })
		elseif a.type == 2 and b.type == 1 then
			args[#args + 1] = a.commit
		elseif a.type == 3 and b.type == 1 then
			local flag = ({ [1] = "--base", [2] = "--ours", [3] = "--theirs" })[a.stage]
			if flag then
				args[#args + 1] = flag
			end
		elseif a.type == 1 and b.type == 2 then
			vim.list_extend(args, { "--reverse", b.commit })
		elseif a.type == 3 and a.stage == 0 and b.type == 2 then
			vim.list_extend(args, { "--cached", "--reverse", b.commit })
		elseif a.type == 1 and b.type == 3 and b.stage == 0 then
			args[#args + 1] = "--reverse"
		else
			return ""
		end
	else
		args[#args + 1] = base or "HEAD"
	end
	vim.list_extend(args, { "--", file })
	local result = vim.system(args, {
		text = true,
	}):wait()
	local diff = result.stdout or ""
	if diff ~= "" then
		return diff
	end
	if b and b.type ~= 1 then
		return ""
	end

	local absolute = root .. "/" .. file
	if vim.fn.filereadable(absolute) ~= 1 then
		return ""
	end
	local untracked = vim.system({ "git", "-C", root, "ls-files", "--error-unmatch", "--", file }, { text = true })
		:wait()
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

local function hunk_for_range(root, file, start_line, end_line, side, base, comparison)
	return review_context.hunk_for_range(
		diff_for_file(root, file, base, comparison, side),
		start_line,
		end_line,
		side == "new" and "new" or "old"
	)
end

local function truncate(text)
	text = text:gsub("%s+", " ")
	if #text <= max_ghost_length then
		return text
	end
	return text:sub(1, max_ghost_length - 1) .. "…"
end

local function freshness(item, root, bufnr, view)
	local source
	if not bufnr and view then
		for _, window in ipairs(view.cur_layout and view.cur_layout.windows or {}) do
			local file = window.file
			if
				file
				and file.path == item.file
				and file.symbol == (({ old = "a", new = "b", theirs = "c", base = "d" })[item.side] or "b")
				and file.bufnr
				and vim.api.nvim_buf_is_loaded(file.bufnr)
			then
				bufnr = file.bufnr
				break
			end
		end
	end
	if bufnr then
		source = table.concat(vim.api.nvim_buf_get_lines(bufnr, item.line - 1, item.end_line or item.line, false), "\n")
	elseif (not item.side or item.side == "new") and (not view or view.right and view.right.type == 1) then
		local path = root .. "/" .. item.file
		local buf = vim.fn.bufnr(path)
		if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
			source =
				table.concat(vim.api.nvim_buf_get_lines(buf, item.line - 1, item.end_line or item.line, false), "\n")
		elseif vim.fn.filereadable(path) == 1 then
			source = table.concat(vim.list_slice(vim.fn.readfile(path), item.line, item.end_line or item.line), "\n")
		end
	end
	return review_context.freshness(item, view and review_context.comparison(view), source)
end

local function item_status(item, state)
	local labels = {}
	if item.text:match("^RESOLVED:") then
		labels[#labels + 1] = "handled"
	elseif item.draft then
		labels[#labels + 1] = "draft"
	elseif item.delivery then
		labels[#labels + 1] = item.delivery.state
	end
	if state ~= "current" then
		labels[#labels + 1] = state
	end
	return #labels > 0 and ("[" .. table.concat(labels, "; ") .. "] ") or ""
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
	local _, view = diff_file(bufnr)

	for _, item in ipairs(read_annotations(root)) do
		if
			review_context.item_matches(item, file, item.line, side)
			and type(item.text) == "string"
			and not item.text:match("^RESOLVED:")
		then
			local line = math.min(math.max((item.line or 1) - 1, 0), vim.api.nvim_buf_line_count(bufnr) - 1)
			vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
				sign_text = icon,
				sign_hl_group = "DiagnosticSignInfo",
				virt_text = {
					{
						icon .. " " .. item_status(item, freshness(item, root, bufnr, view)) .. truncate(item.text),
						"DiagnosticVirtualTextInfo",
					},
				},
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

function M.update_delivery(root, items, state, err)
	local annotations = read_annotations(root)
	for _, item in ipairs(annotations) do
		for _, sent in ipairs(items) do
			if
				item.file == sent.file
				and item.line == sent.line
				and item.side == sent.side
				and item.text == sent.text
				and item.id == sent.id
				and vim.deep_equal(item.review, sent.review)
			then
				item.delivery = { state = state, error = err }
				if
					vim.tbl_contains({ "queued", "submitted", "working", "awaiting_permission", "turn_ended" }, state)
				then
					if item.draft then
						item.draft = false
					end
				end
			end
		end
	end
	write_annotations(root, annotations)
	M.refresh_all()
end

function M.transfer(root, source, target)
	local annotations, transferred = read_annotations(root), {}
	for _, item in ipairs(active_annotations(annotations)) do
		if item.review and vim.deep_equal(item.review.provenance, source) then
			item.review.provenance = vim.deepcopy(target)
			item.delivery = nil
			transferred[#transferred + 1] = item
		end
	end
	write_annotations(root, annotations)
	M.refresh_all()
	return transferred
end

function M.prompt_label(provenance, draft)
	local action = draft and "save draft"
		or provenance and ("save + send to " .. provenance.sessionID)
		or "save locally"
	return "Annotation (Enter: " .. action .. "; Esc: cancel): "
end

local function add_range(start_line, end_line, opts)
	local draft = type(opts) == "table" and opts.draft == true
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
	local review_module = require("config.opencode_review")
	local review, view = review_module.current(root)
	if view and review and not review.automatic and (view.left.commit ~= review.base or view.right.type ~= 1) then
		notify("Review revisions changed; close Diffview and start a new review", vim.log.levels.WARN)
		return
	end
	if not view then
		review = review or review_module.active(root)
	end
	local comparison = view and review_context.comparison(view)
	if review and view then
		review = vim.deepcopy(review)
		review.comparison = comparison
		if review.automatic then
			review.base = review_context.revision_label(review.comparison.a)
		end
	end
	local annotations = read_annotations(root)
	local function matches(item)
		return review_context.item_matches(item, file, start_line, side)
			and (item.draft == true) == draft
			and (
				not view
				or (vim.deep_equal(item.review, review) and (review or vim.deep_equal(item.comparison, comparison)))
			)
	end
	local existing
	for _, item in ipairs(annotations) do
		if matches(item) then
			existing = item
			break
		end
	end
	review = vim.deepcopy((existing and existing.review) or review)
	local hunk = hunk_for_range(
		root,
		file,
		start_line,
		end_line,
		side,
		review and review.base,
		review and review.comparison or comparison
	)
	local context = table.concat(vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false), "\n")

	vim.ui.input(
		{ prompt = M.prompt_label(review and review.provenance, draft), default = existing and existing.text or "" },
		function(text)
			if not text or vim.trim(text) == "" then
				return
			end
			annotations = read_annotations(root)
			local saved = {
				file = file,
				line = start_line,
				end_line = end_line,
				text = text,
				side = side,
				hunk = hunk,
				context = context,
				review = review,
				comparison = not review and comparison or nil,
				id = existing and existing.id
					or (draft and vim.fn.sha256(root .. tostring(vim.uv.hrtime())):sub(1, 16) or nil),
				draft = draft or nil,
				round = existing and existing.round,
				point = existing and existing.point,
			}
			local replaced = false
			for index, item in ipairs(annotations) do
				if matches(item) then
					annotations[index], replaced = saved, true
					break
				end
			end
			if not replaced then
				table.insert(annotations, saved)
			end
			write_annotations(root, annotations)
			M.refresh_all()
			if review and not draft then
				require("config.opencode_review").submit({ saved }, root)
			elseif view and not review then
				notify(
					view.annotation_review_error or "Annotation saved locally; no agent session was captured",
					vim.log.levels.WARN
				)
			end
		end
	)
end

function M.add_current(opts)
	local line = math.max(vim.api.nvim_win_get_cursor(0)[1], 1)
	add_range(line, line, opts)
end

function M.add_visual(opts)
	local visual = ({ v = true, V = true, ["\22"] = true })[vim.fn.mode()]
	local start_line = vim.fn.line(visual and "v" or "'<")
	local end_line = visual and vim.api.nvim_win_get_cursor(0)[1] or vim.fn.line("'>")
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	add_range(start_line, end_line, opts)
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
	local review = require("config.opencode_review")
	if review.active(root) or vim.iter(items):any(function(item)
		return item.review ~= nil
	end) then
		review.submit(items, root)
		return
	end
	local prompt = M.prompt_for_items(items)
	if not prompt then
		return
	end

	require("config.opencode_prompt").append(prompt, {
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
	ask_items(
		vim.tbl_filter(function(item)
			return not item.draft
		end, active_annotations(read_annotations(root))),
		root
	)
end

function M.send_drafts(root)
	root = root or repo_root()
	if not root then
		return
	end
	local function pending(items)
		return vim.tbl_filter(function(item)
			return item.draft == true
		end, active_annotations(items))
	end
	local drafts = pending(read_annotations(root))
	if #drafts == 0 then
		notify("No draft annotations")
		return
	end
	local provenance = drafts[1].review and drafts[1].review.provenance
	if
		not provenance
		or vim.iter(drafts):any(function(item)
			return not item.review or not vim.deep_equal(item.review.provenance, provenance)
		end)
	then
		notify("Drafts need one captured review session; send individually or copy them", vim.log.levels.WARN)
		return
	end
	vim.ui.select({ "Send", "Cancel" }, {
		prompt = string.format("Send %d draft(s) to %s?", #drafts, provenance.sessionID),
	}, function(choice)
		if choice ~= "Send" then
			return
		end
		local annotations = read_annotations(root)
		local items = pending(annotations)
		if not vim.deep_equal(items, drafts) then
			notify("Drafts changed during confirmation; review and send again", vim.log.levels.WARN)
			return
		end
		local round = 0
		for _, item in ipairs(annotations) do
			round = math.max(round, item.round or 0)
		end
		local retry_round, points = items[1].round, {}
		local retry = retry_round ~= nil
		for _, item in ipairs(items) do
			if item.round ~= retry_round or not item.point or points[item.point] then
				retry = false
			end
			if item.point then
				points[item.point] = true
			end
		end
		for point, item in ipairs(items) do
			if not retry then
				item.round, item.point = round + 1, point
			end
		end
		write_annotations(root, annotations)
		require("config.opencode_review").submit(items, root)
		M.refresh_all()
	end)
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
	local review, view = require("config.opencode_review").current(item.root)
	if review then
		local entries = {}
		if view.files then
			for _, entry in view.files:iter() do
				entries[#entries + 1] = entry
			end
		else
			for _, log in ipairs(view.panel.entries or {}) do
				vim.list_extend(entries, log.files or {})
			end
		end
		for _, entry in ipairs(entries) do
			if entry.path == item.file or entry.oldpath == item.file then
				local async = require("diffview.async")
				async.void(function()
					async.await(view:set_file(entry, false))
					if vim.api.nvim_get_current_tabpage() ~= view.tabpage then
						return
					end
					for _, window in ipairs(view.cur_layout.windows) do
						if
							window.file.symbol
							== (({ old = "a", new = "b", theirs = "c", base = "d" })[item.side] or "b")
						then
							vim.api.nvim_set_current_win(window.id)
							local line = math.min(item.line, vim.api.nvim_buf_line_count(window.file.bufnr))
							vim.api.nvim_win_set_cursor(window.id, { math.max(line, 1), 0 })
							return
						end
					end
				end)()
				return
			end
		end
		notify("Commented file is no longer in this diff", vim.log.levels.WARN)
		return
	end
	require("config.bufutil").open_file_in_editor(item.root .. "/" .. item.file, item.line)
end

local function delete_item(item)
	if not item then
		return
	end
	local annotations = vim.tbl_filter(function(candidate)
		return not (
			candidate.file == item.file
			and candidate.line == item.line
			and candidate.side == item.side
			and candidate.text == item.text
			and candidate.id == item.id
		)
	end, read_annotations(item.root))
	write_annotations(item.root, annotations)
	M.refresh_all()
	M.list(item.root)
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
		local saved
		for _, candidate in ipairs(annotations) do
			if
				candidate.file == item.file
				and candidate.line == item.line
				and candidate.side == item.side
				and candidate.text == item.text
				and candidate.id == item.id
			then
				candidate.text = text
				saved = candidate
				break
			end
		end
		write_annotations(item.root, annotations)
		M.refresh_all()
		if saved and saved.review and not saved.draft and not saved.text:match("^RESOLVED:") then
			require("config.opencode_review").submit({ saved }, item.root)
		end
		M.list(item.root)
	end)
end

function M.list(root, filter)
	root = root or repo_root()
	if not root then
		return
	end
	local panel = vim.fn.bufnr("annotate://list")
	if panel ~= -1 then
		vim.api.nvim_buf_delete(panel, { force = true })
	end

	filter = filter or "active"
	local annotations = read_annotations(root)
	if filter ~= "all" then
		annotations = active_annotations(annotations)
	end
	if filter == "drafts" then
		annotations = vim.tbl_filter(function(item)
			return item.draft == true
		end, annotations)
	end

	local width = math.min(math.max(math.floor(vim.o.columns * 0.75), 60), vim.o.columns - 4)
	local height = math.min(math.max(#annotations + 2, 8), math.max(vim.o.lines - 6, 8))
	local row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0)
	local col = math.max(math.floor((vim.o.columns - width) / 2), 0)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local lines = {}
	local items = {}
	local _, view = require("config.opencode_review").current(root)

	for _, item in ipairs(annotations) do
		local panel_item = vim.tbl_extend("force", { root = root }, item)
		table.insert(items, panel_item)
		table.insert(lines, item_status(item, freshness(item, root, nil, view)) .. format_item(item))
	end
	if #lines == 0 then
		lines = { "No annotations · f changes filter" }
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
		title = " Annotations · " .. filter .. " ",
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
		ask_items(
			vim.tbl_filter(function(item)
				return not item.draft
			end, active_annotations(items)),
			root
		)
	end, "Ask OpenCode about all")
	map("s", function()
		M.send_drafts(root)
	end, "Send confirmed draft round")
	map("f", function()
		M.list(root, ({ active = "drafts", drafts = "all", all = "active" })[filter])
	end, "Filter active/drafts/all annotations")
	map("r", function()
		local item = selected_panel_item(bufnr)
		if not item then
			return
		end
		local saved = read_annotations(root)
		for _, candidate in ipairs(saved) do
			if
				candidate.file == item.file
				and candidate.line == item.line
				and candidate.side == item.side
				and candidate.text == item.text
				and candidate.id == item.id
			then
				candidate.text = candidate.text:match("^RESOLVED:") and candidate.text:gsub("^RESOLVED: ?", "", 1)
					or "RESOLVED: " .. candidate.text
				break
			end
		end
		write_annotations(root, saved)
		M.refresh_all()
		M.list(root, filter)
	end, "Toggle handled annotation")
	map("?", function()
		notify(
			"Keys: <CR>/o open, e edit, d delete, c copy, a ask, A ask all, s send drafts, f active/drafts/all, r handled/reopen, q close"
		)
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
		pattern = { "NvimMiniExternalFilesChanged", "DiffviewDiffBufRead", "DiffviewDiffBufWinEnter" },
		callback = M.refresh_all,
		desc = "Refresh annotations after external agent edits",
	})

	vim.api.nvim_create_user_command("Annotate", function(opts)
		local action = opts.fargs[1] or "add"
		if action == "add" then
			M.add_current()
		elseif action == "draft" then
			M.add_current({ draft = true })
		elseif action == "senddrafts" then
			M.send_drafts()
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
			return {
				"add",
				"draft",
				"senddrafts",
				"copy",
				"copyall",
				"ask",
				"askall",
				"list",
				"qflist",
				"delete",
				"deleteall",
			}
		end,
	})

	vim.keymap.set("n", "<leader>ana", M.add_current, { desc = "Add annotation" })
	vim.keymap.set("x", "<leader>ana", M.add_visual, { desc = "Add annotation" })
	vim.keymap.set("n", "gA", M.add_current, { desc = "Annotate current line" })
	vim.keymap.set("x", "gA", M.add_visual, { desc = "Annotate selection" })
	vim.keymap.set("n", "<leader>anb", function()
		M.add_current({ draft = true })
	end, { desc = "Draft annotation" })
	vim.keymap.set("x", "<leader>anb", function()
		M.add_visual({ draft = true })
	end, { desc = "Draft selected annotation" })
	vim.keymap.set("n", "<leader>ans", M.send_drafts, { desc = "Send draft review round" })
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

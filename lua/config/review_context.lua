local M = {}

function M.comparison(view)
	local revs = view.cur_entry and view.cur_entry.revs or { a = view.left, b = view.right }
	local comparison = {}
	for symbol, rev in pairs(revs or {}) do
		comparison[symbol] = { type = rev.type, commit = rev.commit, stage = rev.stage }
	end
	return comparison
end

function M.revision_label(rev)
	if not rev then
		return "selected comparison"
	end
	return rev.commit or (rev.stage and ("index:" .. rev.stage)) or (rev.type == 1 and "working tree" or "custom")
end

local function hunk_range(header, side)
	local old_start, old_count, new_start, new_count = header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
	if not old_start then
		return nil
	end

	local start = tonumber(side == "old" and old_start or new_start)
	local count_text = side == "old" and old_count or new_count
	local count = count_text == "" and 1 or tonumber(count_text)
	return start, start + math.max(count, 1) - 1
end

-- The diff must describe one file; line numbers are file-relative.
function M.hunk_for_range(diff, start_line, end_line, side)
	if not diff or diff == "" then
		return nil
	end

	local lines = vim.split(diff, "\n", { plain = true })
	local hunk_start
	local hunk_end

	for index, line in ipairs(lines) do
		if line:match("^@@ ") then
			if hunk_start then
				local first, last = hunk_range(lines[hunk_start], side)
				if first and end_line >= first and start_line <= last then
					hunk_end = index - 1
					break
				end
			end
			hunk_start = index
		elseif hunk_start and line:match("^diff %-%-git ") then
			local first, last = hunk_range(lines[hunk_start], side)
			if first and end_line >= first and start_line <= last then
				hunk_end = index - 1
				break
			end
			hunk_start = nil
		end
	end

	if hunk_start and not hunk_end then
		local first, last = hunk_range(lines[hunk_start], side)
		if first and end_line >= first and start_line <= last then
			hunk_end = #lines
		end
	end

	if not hunk_start or not hunk_end then
		return nil
	end

	return table.concat(vim.list_slice(lines, hunk_start, hunk_end), "\n")
end

function M.format_item(item)
	local end_line = item.end_line or item.line
	local range = item.line == end_line and tostring(item.line) or string.format("%d-%d", item.line, end_line)
	return string.format("%s:%s: %s", item.file, range, item.text)
end

function M.item_matches(item, file, line, side)
	local same_side = not side or not item.side or item.side == side
	return same_side and item.file == file and line >= item.line and line <= (item.end_line or item.line)
end

function M.prompt_for_items(items, post_instruction)
	local lines = { "Annotations:", "" }
	for _, item in ipairs(items) do
		table.insert(lines, "- " .. M.format_item(item))
		if item.review then
			table.insert(lines, "  " .. (item.side or "new") .. " side; review base " .. item.review.base)
		end
		local comparison = item.comparison or (item.review and item.review.comparison)
		for _, symbol in ipairs({ "a", "b", "c", "d" }) do
			local rev = comparison and comparison[symbol]
			if rev then
				table.insert(lines, "  " .. symbol .. ": " .. M.revision_label(rev))
			end
		end
		if item.context and item.context ~= "" then
			table.insert(lines, "  Selected code at comment time:\n  ```")
			for _, line in ipairs(vim.split(item.context, "\n", { plain = true })) do
				table.insert(lines, "  " .. line)
			end
			table.insert(lines, "  ```")
		end
		if item.hunk and item.hunk ~= "" then
			table.insert(lines, "  ```diff")
			for _, line in ipairs(vim.split(item.hunk, "\n", { plain = true })) do
				table.insert(lines, "  " .. line)
			end
			table.insert(lines, "  ```")
		end
	end
	table.insert(lines, "")
	table.insert(lines, post_instruction)
	return table.concat(lines, "\n")
end

return M

local workspace_layout = require("features.workspace_layout")
local M = {}

local function add_candidate(candidates, seen, value)
	if type(value) ~= "string" then
		return
	end

	value = vim.trim(value)
	value = value:gsub("^file://", "")
	value = value:gsub("^[`'\"%[]+", "")
	value = value:gsub("[`'\"%],;%.]+$", "")

	if value == "" or value:match("^https?://") or seen[value] then
		return
	end

	seen[value] = true
	table.insert(candidates, value)
end

local function collect_from_text(candidates, seen, text)
	if type(text) ~= "string" or text == "" then
		return
	end

	for value in text:gmatch("%(([^()]+)%)") do
		add_candidate(candidates, seen, value)
	end

	for value in text:gmatch("`([^`]+)`") do
		add_candidate(candidates, seen, value)
	end

	for value in text:gmatch("[~/%w_%.%-]+:?%d*") do
		if value:find("/", 1, true) or value:match("%.[%w_%-]+:?%d*$") then
			add_candidate(candidates, seen, value)
		end
	end
end

local function surrounding_text()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line_count = vim.api.nvim_buf_line_count(buf)
	local first = math.max(0, row - 3)
	local last = math.min(line_count, row + 2)
	local lines = vim.api.nvim_buf_get_lines(buf, first, last, false)
	local current = row - first
	local texts = {}

	local function add(value)
		if value and value ~= "" then
			table.insert(texts, value)
		end
	end

	add(lines[current])

	for distance = 1, 2 do
		local previous = lines[current - distance]
		local following = lines[current + distance]

		if following then
			add(lines[current] .. vim.trim(following))
			add(lines[current] .. " " .. vim.trim(following))
		end

		if previous then
			add(previous .. vim.trim(lines[current]))
			add(previous .. " " .. vim.trim(lines[current]))
		end
	end

	if lines[current - 1] and lines[current + 1] then
		add(
			lines[current - 1]
				.. vim.trim(lines[current])
				.. vim.trim(lines[current + 1])
		)
	end

	return texts
end

local function strip_codex_margin(line)
	if line:sub(1, 2) == "  " then
		return line:sub(3), 2
	end

	local bullet_margin = "• "
	if line:sub(1, #bullet_margin) == bullet_margin then
		return line:sub(#bullet_margin + 1), #bullet_margin
	end

	return line, 0
end

local function terminal_row_wraps(line)
	return vim.fn.strdisplaywidth(line) >= vim.api.nvim_win_get_width(0)
end

local function crosses_boundary(first, last, boundaries)
	for _, boundary in ipairs(boundaries) do
		if first <= boundary and last > boundary then
			return true
		end
	end

	return false
end

function M.wrapped_url_under_cursor()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1]
	local line_count = vim.api.nvim_buf_line_count(buf)
	local minimum = math.max(1, row - 4)
	local maximum = math.min(line_count, row + 4)
	local lines = vim.api.nvim_buf_get_lines(buf, minimum - 1, maximum, false)

	local function line_at(line_number)
		return lines[line_number - minimum + 1]
	end

	local first = row
	while first > minimum and terminal_row_wraps(line_at(first - 1)) do
		first = first - 1
	end

	local last = row
	while last < maximum and terminal_row_wraps(line_at(last)) do
		last = last + 1
	end

	-- Leave ordinary, single-row URLs to Neovim's built-in gx handler.
	if first == last then
		return nil
	end

	local joined = ""
	local boundaries = {}
	local cursor_offset

	for line_number = first, last do
		local content, margin = strip_codex_margin(line_at(line_number))
		if line_number == row then
			cursor_offset = #joined + cursor[2] + 1 - margin
		end

		joined = joined .. content
		if line_number < last then
			table.insert(boundaries, #joined)
		end
	end

	if not cursor_offset or cursor_offset < 1 then
		return nil
	end

	local search_from = 1
	while true do
		local url_start, raw_end = joined:find("https?://[^%s<>'\"`]+", search_from)
		if not url_start then
			return nil
		end

		local url = joined:sub(url_start, raw_end):gsub("[%)%]};,%.:!?]+$", "")
		local url_end = url_start + #url - 1
		if cursor_offset >= url_start
			and cursor_offset <= url_end
			and crosses_boundary(url_start, url_end, boundaries)
			-- Codex renders Markdown destinations as `(URL)`. Requiring both
			-- delimiters avoids guessing whether unrelated terminal rows join.
			and joined:sub(url_start - 1, url_start - 1) == "("
			and joined:sub(url_end + 1, url_end + 1) == ")"
		then
			return url
		end

		search_from = raw_end + 1
	end
end

local function split_line_number(value)
	local path, line = value:match("^(.-):(%d+)$")
	if path and path ~= "" then
		return path, tonumber(line)
	end
	return value, nil
end

local function roots()
	local result = {}
	local seen = {}
	local candidates = {}

	if type(vim.b.panel_cwd) == "string" then
		table.insert(candidates, vim.b.panel_cwd)
	end
	table.insert(candidates, vim.fn.getcwd())
	table.insert(candidates, vim.env.HOME)

	for _, root in ipairs(candidates) do
		if type(root) == "string" and root ~= "" and not seen[root] then
			seen[root] = true
			table.insert(result, root)
		end
	end

	return result
end

local function resolve_candidate(value)
	local path, line = split_line_number(value)
	path = vim.fn.expand(path)

	local attempts = {}
	if path:sub(1, 1) == "/" then
		table.insert(attempts, path)
	else
		for _, root in ipairs(roots()) do
			table.insert(attempts, vim.fs.joinpath(root, path))
		end
	end

	for _, attempt in ipairs(attempts) do
		attempt = vim.fs.normalize(attempt)
		local stat = vim.uv.fs_stat(attempt)
		if stat and stat.type == "file" then
			return attempt, line
		end
	end
end

function M.path_under_cursor()
	local candidates = {}
	local seen = {}
	local cfile = vim.fn.expand("<cfile>")
	local cword = vim.fn.expand("<cWORD>")

	-- On Unix, ':' is not part of 'isfname', so <cfile> drops the line
	-- suffix from links such as /path/to/file.lua:48. Recover only an
	-- immediately adjacent numeric suffix from the same cursor word. This
	-- keeps the precise cursor target ahead of broader surrounding-text
	-- candidates, which may contain other links.
	if cfile ~= "" then
		local file_start = cword:find(cfile, 1, true)
		if file_start then
			local suffix = cword:sub(file_start + #cfile)
			local line = suffix:match("^:(%d+)")
			if line then
				add_candidate(candidates, seen, cfile .. ":" .. line)
			end
		end
	end

	add_candidate(candidates, seen, cfile)
	add_candidate(candidates, seen, cword)

	for _, text in ipairs(surrounding_text()) do
		collect_from_text(candidates, seen, text)
	end

	for _, candidate in ipairs(candidates) do
		local path, line = resolve_candidate(candidate)
		if path then
			return path, line
		end
	end
end

local function use_default(default_callback)
	if type(default_callback) == "function" then
		default_callback()
		return
	end

	local target = vim.fn.expand("<cfile>")
	if target ~= "" then
		vim.ui.open(target)
	end
end

function M.open(default_callback)
	local buf = vim.api.nvim_get_current_buf()
	local is_codex_terminal = vim.bo[buf].buftype == "terminal"
		and vim.b[buf].panel_kind == "codex"

	if not is_codex_terminal then
		use_default(default_callback)
		return
	end

	local url = M.wrapped_url_under_cursor()
	if url then
		vim.ui.open(url)
		return
	end

	local path, line = M.path_under_cursor()
	if not path then
		use_default(default_callback)
		return
	end

	if not workspace_layout.edit_file(path, false) then
		return
	end

	if line then
		local last_line = vim.api.nvim_buf_line_count(0)
		vim.api.nvim_win_set_cursor(0, { math.min(line, last_line), 0 })
	end
end

return M

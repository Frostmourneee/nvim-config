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

	add_candidate(candidates, seen, vim.fn.expand("<cfile>"))
	add_candidate(candidates, seen, vim.fn.expand("<cWORD>"))

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

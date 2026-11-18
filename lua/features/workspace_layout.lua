local M = {}

M.defaults = {
	tree_width = 30,
	terminal_height = 10,
	codex_width = 75,
}

local state_key = "__workspace_layout_state"
local state = rawget(vim, state_key)

if not state then
	state = {
		terminal_height = M.defaults.terminal_height,
		codex_width = M.defaults.codex_width,
		code_windows = {},
		front_panel = {},
	}
	rawset(vim, state_key, state)
else
	state.terminal_height = state.terminal_height or M.defaults.terminal_height
	state.codex_width = state.codex_width or M.defaults.codex_width
	state.code_windows = state.code_windows or {}
	state.front_panel = state.front_panel or {}
end

local reflow_scheduled = false
local reflowing = false
local route_repair_scheduled = false
local repairing_routes = false
local panel_style_version = 3

local function current_tab(tab)
	if tab and tab ~= 0 then
		return tab
	end

	return vim.api.nvim_get_current_tabpage()
end

local function is_floating(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end

	return vim.api.nvim_win_get_config(win).relative ~= ""
end

local function panel_kind(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	return vim.b[buf].panel_kind
end

local function has_tree_buffer(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end

	local buf = vim.api.nvim_win_get_buf(win)
	return vim.bo[buf].filetype == "NvimTree"
end

local function stored_window_group(win)
	local ok, group = pcall(vim.api.nvim_win_get_var, win, "workspace_group")
	if ok and (
		group == "tree"
		or group == "code"
		or group == "terminal"
		or group == "codex"
	) then
		return group
	end
end

local function set_window_group(win, group)
	pcall(vim.api.nvim_win_set_var, win, "workspace_group", group)
end

function M.buffer_group(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	local kind = panel_kind(buf)
	if kind == "terminal" or kind == "codex" then
		return kind
	end

	if vim.bo[buf].filetype == "NvimTree" then
		return "tree"
	end

	if vim.bo[buf].buftype == "" then
		return "code"
	end
end

function M.is_empty_code_buffer(buf)
	if M.buffer_group(buf) ~= "code"
		or vim.api.nvim_buf_get_name(buf) ~= ""
		or vim.bo[buf].modified
	then
		return false
	end

	local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, 2, false)
	return ok and #lines == 1 and lines[1] == ""
end

function M.window_group(win)
	if not vim.api.nvim_win_is_valid(win) then
		return nil
	end

	local group = stored_window_group(win)
	if group then
		return group
	end

	if is_floating(win) then
		group = panel_kind(vim.api.nvim_win_get_buf(win))
		if group ~= "terminal" and group ~= "codex" then
			return nil
		end
	elseif has_tree_buffer(win) then
		group = "tree"
	else
		group = "code"
	end

	set_window_group(win, group)
	return group
end

local function is_code_window(win, tab)
	if not vim.api.nvim_win_is_valid(win)
		or vim.api.nvim_win_get_tabpage(win) ~= tab
		or is_floating(win)
	then
		return false
	end

	return M.window_group(win) == "code"
end

local function clamp(value, minimum, maximum)
	minimum = math.min(minimum, maximum)
	return math.max(minimum, math.min(value, maximum))
end

function M.find_tree_window(tab)
	tab = current_tab(tab)

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if not is_floating(win)
			and stored_window_group(win) == "tree"
		then
			return win
		end
	end

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if not is_floating(win)
			and has_tree_buffer(win)
			and stored_window_group(win) == nil
		then
			set_window_group(win, "tree")
			return win
		end
	end
end

function M.list_group_buffers(group, listed_only, excluded_buf)
	local result = {}

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= excluded_buf
			and vim.api.nvim_buf_is_valid(buf)
			and M.buffer_group(buf) == group
			and (not listed_only or vim.bo[buf].buflisted)
		then
			table.insert(result, buf)
		end
	end

	table.sort(result)
	return result
end

function M.list_navigable_group_buffers(group)
	local result = {}

	for _, buf in ipairs(M.list_group_buffers(group, true)) do
		if not M.is_empty_code_buffer(buf) then
			table.insert(result, buf)
		end
	end

	return result
end

function M.group_buffer_position(buf)
	local group = M.buffer_group(buf)
	if not group then
		return nil, 0
	end

	local buffers = M.list_navigable_group_buffers(group)
	for index, candidate in ipairs(buffers) do
		if candidate == buf then
			return index, #buffers
		end
	end

	return nil, #buffers
end

function M.find_group_buffer(group, excluded_buf, listed_only)
	local best
	local best_lastused = -1

	for _, buf in ipairs(M.list_group_buffers(group, listed_only, excluded_buf)) do
		local info = vim.fn.getbufinfo(buf)[1]
		local lastused = info and info.lastused or 0

		if lastused > best_lastused
			or (lastused == best_lastused and (not best or buf > best))
		then
			best = buf
			best_lastused = lastused
		end
	end

	return best
end

local function ensure_code_buffer(excluded_buf)
	return M.find_group_buffer("code", excluded_buf, true)
		or vim.api.nvim_create_buf(true, false)
end

local function set_window_buffer(win, buf)
	vim.api.nvim_win_set_buf(win, buf)

	local cwd = vim.b[buf].panel_cwd
	if cwd and vim.fn.isdirectory(cwd) == 1 then
		vim.api.nvim_win_call(win, function()
			vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
		end)
	end
end

local function replacement_for_window(win, excluded_buf)
	local group = M.window_group(win)
	if group == "code" then
		return ensure_code_buffer(excluded_buf)
	end

	if group then
		return M.find_group_buffer(group, excluded_buf, false)
	end
end

function M.detach_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local changed = false
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_is_valid(win) then
			local replacement = replacement_for_window(win, buf)
			if replacement then
				set_window_buffer(win, replacement)
				changed = true
			else
				local group = M.window_group(win)
				if group == "tree" or group == "terminal" or group == "codex" then
				vim.api.nvim_win_hide(win)
				changed = true
				end
			end
		end
	end

	return changed
end

function M.find_code_window(tab)
	tab = current_tab(tab)
	local remembered = state.code_windows[tab]

	if remembered and is_code_window(remembered, tab) then
		return remembered
	end

	local best
	local best_score = -1

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if is_code_window(win, tab) then
			local buf = vim.api.nvim_win_get_buf(win)
			local normal_buffer = M.buffer_group(buf) == "code" and 1000000 or 0
			local area = vim.api.nvim_win_get_width(win) * vim.api.nvim_win_get_height(win)
			local score = normal_buffer + area

			if score > best_score then
				best = win
				best_score = score
			end
		end
	end

	if best then
		state.code_windows[tab] = best
	end

	return best
end

function M.ensure_code_window(tab)
	tab = current_tab(tab)
	local code_win = M.find_code_window(tab)

	if code_win then
		local buf = vim.api.nvim_win_get_buf(code_win)
		local group = M.buffer_group(buf)
		if group and group ~= "code" then
			set_window_buffer(code_win, ensure_code_buffer(buf))
		end
		return code_win
	end

	if tab ~= vim.api.nvim_get_current_tabpage() then
		return nil
	end

	local tree_win = M.find_tree_window(tab)
	if tree_win then
		vim.api.nvim_set_current_win(tree_win)
	end

	vim.cmd("rightbelow vnew")
	code_win = vim.api.nvim_get_current_win()
	set_window_group(code_win, "code")
	state.code_windows[tab] = code_win
	return code_win
end

function M.show_code_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) or M.buffer_group(buf) ~= "code" then
		return false
	end

	local code_win = M.ensure_code_window()
	if not code_win then
		return false
	end

	local ok, err = pcall(function()
		vim.api.nvim_set_current_win(code_win)
		set_window_buffer(code_win, buf)
	end)

	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return false
	end

	state.code_windows[current_tab()] = code_win
	return true
end

function M.edit_file(path, keep_tree_focus)
	local origin = vim.api.nvim_get_current_win()
	local code_win = M.ensure_code_window()
	if not code_win then
		return false
	end

	local ok, err = pcall(function()
		vim.api.nvim_set_current_win(code_win)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
	end)

	if keep_tree_focus and vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	elseif not ok and vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	end

	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return false
	end

	state.code_windows[current_tab()] = code_win
	return true
end

local function panel_title(kind, buf)
	local labels = {
		terminal = "TERMINAL",
		codex = "AI",
	}
	local index, total = M.group_buffer_position(buf)

	return (" %s %d / %d "):format(labels[kind], index or 0, total)
end

local function panel_config(kind, code_win, opening, buf)
	local code_width = vim.api.nvim_win_get_width(code_win)
	local code_height = vim.api.nvim_win_get_height(code_win)
	local tab = vim.api.nvim_win_get_tabpage(code_win)
	local is_front = state.front_panel[tab] == kind
	local bordered = code_width >= 3 and code_height >= 3
	local border_size = bordered and 2 or 0
	local config = {
		relative = "win",
		win = code_win,
		row = 0,
		col = 0,
		width = math.max(1, code_width - border_size),
		height = math.max(1, code_height - border_size),
		focusable = true,
		zindex = is_front and 60 or 50,
	}

	if bordered then
		config.border = "rounded"
		config.title = panel_title(kind, buf)
		config.title_pos = "center"
	end

	if kind == "terminal" then
		local outer_height = clamp(
			state.terminal_height,
			bordered and 3 or 1,
			code_height
		)
		config.height = math.max(1, outer_height - border_size)
		config.row = code_height - outer_height
	elseif kind == "codex" then
		local outer_width = clamp(
			state.codex_width,
			bordered and 3 or 1,
			code_width
		)
		config.width = math.max(1, outer_width - border_size)
		config.col = code_width - outer_width
	else
		error("Unknown workspace panel: " .. tostring(kind))
	end

	if opening then
		config.style = "minimal"
	end

	return config
end

function M.mark_panel(kind, buf, cwd)
	vim.b[buf].panel_kind = kind
	vim.b[buf].panel_cwd = cwd
	vim.bo[buf].bufhidden = "hide"
end

function M.find_panel_window(kind, tab)
	tab = current_tab(tab)

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if is_floating(win) and M.window_group(win) == kind then
			return win
		end
	end
end

function M.open_panel(kind, buf, enter, cwd)
	local code_win = M.ensure_code_window()
	if not code_win then
		return nil
	end

	local tab = vim.api.nvim_win_get_tabpage(code_win)
	state.front_panel[tab] = kind
	M.mark_panel(kind, buf, cwd or vim.b[buf].panel_cwd)

	local win = vim.api.nvim_open_win(
		buf,
		enter ~= false,
		panel_config(kind, code_win, true, buf)
	)
	set_window_group(win, kind)
	vim.api.nvim_win_set_var(win, "workspace_panel_style", panel_style_version)
	vim.api.nvim_win_set_var(
		win,
		"workspace_panel_title",
		panel_title(kind, buf)
	)
	vim.wo[win].winblend = 0

	local panel_cwd = vim.b[buf].panel_cwd
	if panel_cwd and vim.fn.isdirectory(panel_cwd) == 1 then
		vim.api.nvim_win_call(win, function()
			vim.cmd("lcd " .. vim.fn.fnameescape(panel_cwd))
		end)
	end

	state.front_panel[tab] = kind
	M.reflow()

	return win
end

function M.focus_panel(kind)
	local win = M.find_panel_window(kind)
	if not win then
		return false
	end

	local tab = vim.api.nvim_win_get_tabpage(win)
	state.front_panel[tab] = kind
	vim.api.nvim_set_current_win(win)
	M.reflow()
	return true
end

function M.hide_panel(kind)
	local win = M.find_panel_window(kind)
	if not win then
		return false
	end

	vim.api.nvim_win_hide(win)
	return true
end

local function focus_managed_window(win)
	if not win
		or not vim.api.nvim_win_is_valid(win)
		or win == vim.api.nvim_get_current_win()
	then
		return
	end

	local kind = M.window_group(win)

	if kind == "terminal" or kind == "codex" then
		state.front_panel[vim.api.nvim_win_get_tabpage(win)] = kind
	end

	vim.api.nvim_set_current_win(win)

	if kind == "terminal" or kind == "codex" then
		M.reflow()
	end
end

function M.focus_area(kind)
	local win

	if kind == "code" then
		win = M.ensure_code_window()
	elseif kind == "tree" then
		win = M.ensure_tree()
	elseif kind == "terminal" or kind == "codex" then
		win = M.find_panel_window(kind)
	end

	focus_managed_window(win)
	return win ~= nil
end

function M.toggle_tree_focus()
	M.repair_buffer_routes()
	local tree_win = M.find_tree_window()

	if tree_win and tree_win == vim.api.nvim_get_current_win() then
		local ok, api = pcall(require, "nvim-tree.api")
		if ok then
			api.tree.close()
		else
			pcall(vim.api.nvim_win_close, tree_win, true)
		end
		return true
	end

	tree_win = tree_win or M.ensure_tree()
	focus_managed_window(tree_win)
	return tree_win ~= nil
end

local function config_changed(win, current, wanted)
	local ok, style = pcall(
		vim.api.nvim_win_get_var,
		win,
		"workspace_panel_style"
	)
	if not ok or style ~= panel_style_version then
		return true
	end

	local title_ok, title = pcall(
		vim.api.nvim_win_get_var,
		win,
		"workspace_panel_title"
	)
	if not title_ok or title ~= (wanted.title or "") then
		return true
	end

	for _, key in ipairs({
		"relative",
		"win",
		"row",
		"col",
		"width",
		"height",
		"focusable",
		"zindex",
	}) do
		if current[key] ~= wanted[key] then
			return true
		end
	end

	return false
end

function M.reflow()
	if reflowing then
		return
	end

	reflowing = true
	local ok, err = pcall(function()
		for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
			local code_win = M.find_code_window(tab)

			if code_win then
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
					local kind = M.window_group(win)

					if is_floating(win)
						and (kind == "terminal" or kind == "codex")
					then
						local wanted = panel_config(
							kind,
							code_win,
							false,
							vim.api.nvim_win_get_buf(win)
						)
						local current = vim.api.nvim_win_get_config(win)

						if config_changed(win, current, wanted) then
							local configured = pcall(
								vim.api.nvim_win_set_config,
								win,
								wanted
							)
							if configured then
								vim.api.nvim_win_set_var(
									win,
									"workspace_panel_style",
									panel_style_version
								)
								vim.api.nvim_win_set_var(
									win,
									"workspace_panel_title",
									wanted.title or ""
								)
							end
						end
					end
				end
			end
		end
	end)

	reflowing = false

	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

function M.schedule_reflow()
	if reflow_scheduled then
		return
	end

	reflow_scheduled = true
	vim.schedule(function()
		reflow_scheduled = false
		M.reflow()
	end)
end

function M.repair_buffer_routes()
	if repairing_routes then
		return
	end

	repairing_routes = true
	local ok, err = pcall(function()
		for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				local wanted_group = M.window_group(win)
				local buf = vim.api.nvim_win_get_buf(win)
				local actual_group = M.buffer_group(buf)

				if wanted_group and actual_group and wanted_group ~= actual_group then
					local replacement = replacement_for_window(win, buf)
					if replacement then
						set_window_buffer(win, replacement)
					elseif wanted_group == "tree"
						or wanted_group == "terminal"
						or wanted_group == "codex"
					then
						vim.api.nvim_win_hide(win)
					end
				end
			end
		end
	end)

	repairing_routes = false
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

function M.schedule_route_repair()
	if route_repair_scheduled then
		return
	end

	route_repair_scheduled = true
	vim.schedule(function()
		route_repair_scheduled = false
		M.repair_buffer_routes()
	end)
end

function M.resize_managed_float(direction, amount)
	local kind = M.window_group(vim.api.nvim_get_current_win())

	if kind ~= "terminal" and kind ~= "codex" then
		return false
	end

	local tab = vim.api.nvim_get_current_tabpage()
	local code_win = M.find_code_window(tab)
	amount = amount or 3
	state.front_panel[tab] = kind

	if kind == "terminal" then
		if direction == "up" then
			state.terminal_height = state.terminal_height + amount
		elseif direction == "down" then
			state.terminal_height = state.terminal_height - amount
		end

		local maximum = code_win and vim.api.nvim_win_get_height(code_win) or state.terminal_height
		local minimum = maximum >= 3 and 3 or 1
		state.terminal_height = clamp(state.terminal_height, minimum, maximum)
	else
		if direction == "left" then
			state.codex_width = state.codex_width + amount
		elseif direction == "right" then
			state.codex_width = state.codex_width - amount
		end

		local maximum = code_win and vim.api.nvim_win_get_width(code_win) or state.codex_width
		local minimum = maximum >= 3 and 3 or 1
		state.codex_width = clamp(state.codex_width, minimum, maximum)
	end

	M.reflow()
	return true
end

function M.ensure_tree()
	local tree_win = M.find_tree_window()
	if tree_win then
		return tree_win
	end

	local code_win = M.find_code_window()
	if code_win then
		vim.api.nvim_set_current_win(code_win)
	end

	local ok, api = pcall(require, "nvim-tree.api")
	if not ok then
		return nil
	end

	api.tree.open()
	return M.find_tree_window()
end

function M.reset()
	local origin = vim.api.nvim_get_current_win()
	local tree_win = M.ensure_tree()
	M.ensure_code_window()

	if tree_win then
		pcall(vim.api.nvim_win_set_width, tree_win, M.defaults.tree_width)
	end

	state.terminal_height = M.defaults.terminal_height
	state.codex_width = M.defaults.codex_width
	M.reflow()

	if vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	end
end

local layout_group = vim.api.nvim_create_augroup("WorkspaceLayout", {
	clear = true,
})

vim.api.nvim_create_autocmd({
	"BufWinEnter",
	"TabEnter",
	"VimResized",
	"WinClosed",
	"WinNew",
	"WinResized",
}, {
	group = layout_group,
	callback = function()
		M.schedule_route_repair()
		M.schedule_reflow()
	end,
})

vim.api.nvim_create_autocmd("WinEnter", {
	group = layout_group,
	callback = function()
		local win = vim.api.nvim_get_current_win()
		local kind = stored_window_group(win)
		if not kind and is_floating(win) then
			kind = M.window_group(win)
		end
		if kind == "terminal" or kind == "codex" then
			state.front_panel[vim.api.nvim_get_current_tabpage()] = kind
		end

		M.schedule_route_repair()
		M.schedule_reflow()
	end,
})

return M

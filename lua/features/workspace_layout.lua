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

local function is_tree_window(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end

	local buf = vim.api.nvim_win_get_buf(win)
	return vim.bo[buf].filetype == "NvimTree"
end

local function is_code_window(win, tab)
	if not vim.api.nvim_win_is_valid(win)
		or vim.api.nvim_win_get_tabpage(win) ~= tab
		or is_floating(win)
		or is_tree_window(win)
	then
		return false
	end

	return panel_kind(vim.api.nvim_win_get_buf(win)) == nil
end

local function clamp(value, minimum, maximum)
	minimum = math.min(minimum, maximum)
	return math.max(minimum, math.min(value, maximum))
end

function M.find_tree_window(tab)
	tab = current_tab(tab)

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if not is_floating(win) and is_tree_window(win) then
			return win
		end
	end
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
			local normal_buffer = vim.bo[buf].buftype == "" and 1000000 or 0
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
	state.code_windows[tab] = code_win
	return code_win
end

function M.show_code_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local code_win = M.ensure_code_window()
	if not code_win then
		return false
	end

	local ok, err = pcall(function()
		vim.api.nvim_set_current_win(code_win)
		vim.api.nvim_win_set_buf(code_win, buf)
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

local function panel_config(kind, code_win, opening)
	local code_width = vim.api.nvim_win_get_width(code_win)
	local code_height = vim.api.nvim_win_get_height(code_win)
	local tab = vim.api.nvim_win_get_tabpage(code_win)
	local is_front = state.front_panel[tab] == kind
	local config = {
		relative = "win",
		win = code_win,
		row = 0,
		col = 0,
		width = code_width,
		height = code_height,
		focusable = true,
		zindex = is_front and 60 or 50,
	}

	if kind == "terminal" then
		config.height = clamp(state.terminal_height, 1, code_height)
		config.row = code_height - config.height
	elseif kind == "codex" then
		config.width = clamp(state.codex_width, 1, code_width)
		config.col = code_width - config.width
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
		local buf = vim.api.nvim_win_get_buf(win)
		if panel_kind(buf) == kind then
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

	local win = vim.api.nvim_open_win(buf, enter ~= false, panel_config(kind, code_win, true))
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

	local buf = vim.api.nvim_win_get_buf(win)
	local kind = panel_kind(buf)

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

local function config_changed(current, wanted)
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
					local kind = panel_kind(vim.api.nvim_win_get_buf(win))

					if kind == "terminal" or kind == "codex" then
						local wanted = panel_config(kind, code_win, false)
						local current = vim.api.nvim_win_get_config(win)

						if config_changed(current, wanted) then
							pcall(vim.api.nvim_win_set_config, win, wanted)
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

function M.resize_managed_float(direction, amount)
	local buf = vim.api.nvim_get_current_buf()
	local kind = panel_kind(buf)

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
		state.terminal_height = clamp(state.terminal_height, 1, maximum)
	else
		if direction == "left" then
			state.codex_width = state.codex_width + amount
		elseif direction == "right" then
			state.codex_width = state.codex_width - amount
		end

		local maximum = code_win and vim.api.nvim_win_get_width(code_win) or state.codex_width
		state.codex_width = clamp(state.codex_width, 1, maximum)
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
	callback = M.schedule_reflow,
})

vim.api.nvim_create_autocmd("WinEnter", {
	group = layout_group,
	callback = function()
		local kind = panel_kind(vim.api.nvim_get_current_buf())
		if kind == "terminal" or kind == "codex" then
			state.front_panel[vim.api.nvim_get_current_tabpage()] = kind
			M.schedule_reflow()
		end
	end,
})

return M

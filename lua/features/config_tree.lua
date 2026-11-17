local M = {}

local state_key = "__config_tree_workspace_state"

local function get_state()
	return rawget(vim, state_key)
end

local function set_state(state)
	rawset(vim, state_key, state)
end

local function same_path(left, right)
	if not left or not right then
		return false
	end

	left = vim.uv.fs_realpath(left) or vim.fs.normalize(left)
	right = vim.uv.fs_realpath(right) or vim.fs.normalize(right)
	return left == right
end

local function collect_open_directories(nodes, result)
	for _, node in ipairs(nodes or {}) do
		if node.open then
			table.insert(result, node.absolute_path)
			collect_open_directories(node.nodes, result)
		end
	end
end

local function tree_width()
	local view = require("nvim-tree.view")
	local win = view.get_winnr()

	if win and vim.api.nvim_win_is_valid(win) then
		return vim.api.nvim_win_get_width(win)
	end
end

local function snapshot()
	local api = require("nvim-tree.api")
	local core = require("nvim-tree.core")
	local visible = api.tree.is_visible()
	local open_directories = {}
	local nodes = api.tree.get_nodes()

	collect_open_directories(nodes, open_directories)

	local selected = visible and api.tree.get_node_under_cursor() or nil

	return {
		root = core.get_cwd() or vim.fn.getcwd(),
		cwd = vim.fn.getcwd(),
		visible = visible,
		width = tree_width(),
		open_directories = open_directories,
		selected_path = selected and selected.absolute_path or nil,
		origin_tab = vim.api.nvim_get_current_tabpage(),
		origin_win = vim.api.nvim_get_current_win(),
	}
end

local function open_settings_workspace()
	local api = require("nvim-tree.api")
	local state = snapshot()
	local config_dir = vim.fn.stdpath("config")

	vim.cmd("tabnew")
	state.settings_tab = vim.api.nvim_get_current_tabpage()
	set_state(state)

	api.tree.open({ path = config_dir })
	api.tree.collapse_all()

	if state.width then
		api.tree.resize({ absolute = state.width })
	end
end

local function close_settings_tab(state)
	if not state.settings_tab
		or not vim.api.nvim_tabpage_is_valid(state.settings_tab) then
		return true
	end

	if #vim.api.nvim_list_tabpages() == 1 then
		return true
	end

	vim.api.nvim_set_current_tabpage(state.settings_tab)

	local ok, err = pcall(vim.cmd, "tabclose")
	if not ok then
		vim.notify(
			"Save or discard settings changes before leaving:\n" .. tostring(err),
			vim.log.levels.ERROR
		)
		return false
	end

	return true
end

local function restore_open_directories(api, paths)
	table.sort(paths, function(left, right)
		return #left < #right
	end)

	for _, path in ipairs(paths) do
		if vim.fn.isdirectory(path) == 1 then
			api.tree.find_file({
				buf = path,
				focus = true,
			})

			local node = api.tree.get_node_under_cursor()
			if node and same_path(node.absolute_path, path) and not node.open then
				api.node.open.edit(node)
			end
		end
	end
end

local function restore_workspace(state)
	local api = require("nvim-tree.api")
	local root = state.root

	if state.origin_tab and vim.api.nvim_tabpage_is_valid(state.origin_tab) then
		vim.api.nvim_set_current_tabpage(state.origin_tab)
	end

	if vim.fn.isdirectory(root) ~= 1 then
		root = state.cwd
	end

	api.tree.open({ path = root })
	api.tree.change_root(root)
	api.tree.collapse_all()
	restore_open_directories(api, state.open_directories)

	if state.selected_path then
		api.tree.find_file({
			buf = state.selected_path,
			focus = true,
		})
	end

	if state.width then
		api.tree.resize({ absolute = state.width })
	end

	if state.cwd and vim.fn.isdirectory(state.cwd) == 1 then
		vim.cmd("cd " .. vim.fn.fnameescape(state.cwd))
	end

	if not state.visible then
		api.tree.close()
	end

	if state.origin_win and vim.api.nvim_win_is_valid(state.origin_win) then
		vim.api.nvim_set_current_win(state.origin_win)
	end
end

function M.toggle()
	local state = get_state()

	if not state then
		open_settings_workspace()
		return
	end

	if not close_settings_tab(state) then
		return
	end

	set_state(nil)
	restore_workspace(state)
end

return M

local M = {}
local panels = require("features.panels")
local workspace_layout = require("features.workspace_layout")

local state_key = "__config_tree_workspace_state"
local panel_kinds = { "terminal", "codex" }
local restore_panels

local function get_state()
	return rawget(vim, state_key)
end

local function set_state(state)
	rawset(vim, state_key, state)
end

local function code_buffer_snapshot()
	local result = {}

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf)
			and vim.bo[buf].buflisted
			and workspace_layout.buffer_group(buf) == "code"
		then
			result[buf] = true
		end
	end

	return result
end

local function track_workspace_buffer(buf)
	local state = get_state()
	if not state
		or not state.workspace_tab
		or not vim.api.nvim_tabpage_is_valid(state.workspace_tab)
		or vim.api.nvim_get_current_tabpage() ~= state.workspace_tab
	then
		return
	end

	state.workspace_buffers = state.workspace_buffers or {}
	state.workspace_buffers[buf] = true
end

local tracking_group = vim.api.nvim_create_augroup("ConfigTreeWorkspaceBuffers", {
	clear = true,
})

vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter", "BufWinEnter" }, {
	group = tracking_group,
	callback = function(args)
		track_workspace_buffer(args.buf)
	end,
})

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

local function panel_snapshot(tab, current_win)
	local result = {}
	local front_zindex = -1

	for _, kind in ipairs(panel_kinds) do
		local win = workspace_layout.find_panel_window(kind, tab)
		if win then
			local config = vim.api.nvim_win_get_config(win)
			local zindex = config.zindex or 0
			result[kind] = {
				visible = true,
				buffer = vim.api.nvim_win_get_buf(win),
			}

			if zindex > front_zindex then
				front_zindex = zindex
				result.front = kind
			end

			if win == current_win then
				result.focused = kind
			end
		else
			result[kind] = { visible = false }
		end
	end

	return result
end

local function snapshot()
	local api = require("nvim-tree.api")
	local core = require("nvim-tree.core")
	local visible = api.tree.is_visible()
	local open_directories = {}
	local nodes = api.tree.get_nodes()

	collect_open_directories(nodes, open_directories)

	local selected = visible and api.tree.get_node_under_cursor() or nil

	local origin_tab = vim.api.nvim_get_current_tabpage()
	local origin_win = vim.api.nvim_get_current_win()

	return {
		root = core.get_cwd() or vim.fn.getcwd(),
		cwd = vim.fn.getcwd(),
		visible = visible,
		width = tree_width(),
		open_directories = open_directories,
		selected_path = selected and selected.absolute_path or nil,
		origin_tab = origin_tab,
		origin_win = origin_win,
		panels = panel_snapshot(origin_tab, origin_win),
	}
end

local function open_workspace(options)
	local api = require("nvim-tree.api")
	local state = snapshot()
	state.initial_code_buffers = code_buffer_snapshot()

	vim.cmd("tabnew")
	state.workspace_tab = vim.api.nvim_get_current_tabpage()
	state.workspace_id = options.id
	state.workspace_buffers = {
		[vim.api.nvim_get_current_buf()] = true,
	}
	set_state(state)

	api.tree.open({ path = options.root })
	api.tree.collapse_all()

	if options.selected_path then
		api.tree.find_file({
			buf = options.selected_path,
			focus = true,
		})

		local node = api.tree.get_node_under_cursor()
		if node and same_path(node.absolute_path, options.selected_path) and not node.open then
			api.node.open.edit(node)
		end
	end

	if state.width then
		api.tree.resize({ absolute = state.width })
	end

	local workspace_win = vim.api.nvim_get_current_win()
	restore_panels(state, state.workspace_tab)
	if vim.api.nvim_win_is_valid(workspace_win) then
		vim.api.nvim_set_current_win(workspace_win)
	end
end

local function close_workspace_tab(state)
	local workspace_tab = state.workspace_tab or state.settings_tab

	if not workspace_tab
		or not vim.api.nvim_tabpage_is_valid(workspace_tab) then
		return true
	end

	if #vim.api.nvim_list_tabpages() == 1 then
		return true
	end

	vim.api.nvim_set_current_tabpage(workspace_tab)

	local ok, err = pcall(vim.cmd, "tabclose")
	if not ok then
		vim.notify(
			"Save or discard workspace changes before leaving:\n" .. tostring(err),
			vim.log.levels.ERROR
		)
		return false
	end

	return true
end

local function close_workspace_code_buffers(state)
	if type(state.workspace_buffers) ~= "table"
		or type(state.initial_code_buffers) ~= "table"
	then
		return
	end

	local preserved = {}

	for buf in pairs(state.workspace_buffers) do
		if not state.initial_code_buffers[buf]
			and vim.api.nvim_buf_is_valid(buf)
			and workspace_layout.buffer_group(buf) == "code"
		then
			local name = vim.api.nvim_buf_get_name(buf)
			if name == "" then
				name = "[No Name]"
			end

			local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = false })
			if not ok and vim.api.nvim_buf_is_valid(buf) then
				table.insert(preserved, name .. ": " .. tostring(err))
			end
		end
	end

	if #preserved > 0 then
		vim.notify(
			"Some temporary code buffers were preserved:\n" .. table.concat(preserved, "\n"),
			vim.log.levels.WARN
		)
	end
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

restore_panels = function(state, tab)
	if type(state.panels) ~= "table" then
		return
	end
	tab = tab or state.origin_tab

	for _, kind in ipairs(panel_kinds) do
		local saved = state.panels[kind]
		local win = workspace_layout.find_panel_window(kind, tab)

		if saved and saved.visible
			and saved.buffer
			and vim.api.nvim_buf_is_valid(saved.buffer)
		then
			panels.show_buffer(saved.buffer)
		elseif saved and not saved.visible and win then
			workspace_layout.hide_panel(kind)
		end
	end

	local front = state.panels.front
	if front and workspace_layout.find_panel_window(front, tab) then
		workspace_layout.focus_panel(front)
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

	restore_panels(state)

	local focused_panel = state.panels and state.panels.focused
	if focused_panel
		and workspace_layout.find_panel_window(focused_panel, state.origin_tab)
	then
		workspace_layout.focus_panel(focused_panel)
	elseif state.origin_win and vim.api.nvim_win_is_valid(state.origin_win) then
		vim.api.nvim_set_current_win(state.origin_win)
	end
end

local function toggle(options)
	local state = get_state()

	if not state then
		open_workspace(options)
		return
	end

	if not close_workspace_tab(state) then
		return
	end

	close_workspace_code_buffers(state)
	set_state(nil)
	restore_workspace(state)

	local workspace_id = state.workspace_id or "settings"
	if workspace_id ~= options.id then
		open_workspace(options)
	end
end

function M.toggle()
	toggle({
		id = "settings",
		root = vim.fn.stdpath("config"),
	})
end

function M.toggle_skills()
	local skills_dir = vim.fs.normalize(vim.fn.expand("~/.codex/skills"))

	if vim.fn.isdirectory(skills_dir) ~= 1 then
		vim.notify("Codex skills directory not found: " .. skills_dir, vim.log.levels.ERROR)
		return
	end

	toggle({
		id = "skills",
		root = vim.fn.expand("~"),
		selected_path = skills_dir,
	})
end

return M

local MiniBufremove = require("mini.bufremove")
local bufferline_groups = require("bufferline.groups")
local workspace_layout = require("features.workspace_layout")
local panels = require("features.panels")

MiniBufremove.setup()

local function close_buffer(buf)
	if vim.b[buf].panel_kind then
		panels.close_buffer(buf)
		return
	end

	workspace_layout.detach_buffer(buf)
	local ok, err = pcall(MiniBufremove.delete, buf, false)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

local function close_other_code_buffers()
	local code_win = workspace_layout.find_code_window()
	if not code_win then
		vim.notify("No code editor window is visible", vim.log.levels.INFO)
		return
	end

	local visible_buf = vim.api.nvim_win_get_buf(code_win)
	if workspace_layout.buffer_group(visible_buf) ~= "code" then
		vim.notify("No code buffer is visible", vim.log.levels.INFO)
		return
	end

	for _, buf in ipairs(
		workspace_layout.list_group_buffers("code", true, visible_buf)
	) do
		close_buffer(buf)
	end
end

local function show_group_buffer(buf)
	local group = workspace_layout.buffer_group(buf)
	if group == "code" then
		return workspace_layout.show_code_buffer(buf)
	end

	if group == "terminal" or group == "codex" then
		return panels.show_buffer(buf)
	end

	return false
end

local function cycle_group_buffer(step)
	local current = vim.api.nvim_get_current_buf()
	local group = workspace_layout.buffer_group(current)
	if not group or group == "tree" then
		return
	end

	local buffers = workspace_layout.list_navigable_group_buffers(group)
	if #buffers == 0 then
		return
	end

	local current_index
	for index, buf in ipairs(buffers) do
		if buf == current then
			current_index = index
			break
		end
	end

	local target_index
	if current_index then
		target_index = (current_index - 1 + step) % #buffers + 1
	else
		target_index = step > 0 and 1 or #buffers
	end

	show_group_buffer(buffers[target_index])
end

local function jump_to_group_buffer(index)
	local current = vim.api.nvim_get_current_buf()
	local group = workspace_layout.buffer_group(current)
	if group == "tree" then
		group = "code"
	end

	if not group then
		return false
	end

	local target = workspace_layout.list_navigable_group_buffers(group)[index]
	if not target then
		vim.notify(
			("No %s buffer %d"):format(group, index),
			vim.log.levels.INFO
		)
		return false
	end

	return show_group_buffer(target)
end

local function create_temporary_text_buffer()
	local used_names = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
			used_names[name] = true
		end
	end

	local index = 1
	while used_names[("tmp%d.txt"):format(index)] do
		index = index + 1
	end

	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, ("tmp%d.txt"):format(index))
	vim.b[buf].temporary_text_buffer = true
	vim.bo[buf].filetype = "text"
	vim.bo[buf].swapfile = false
	workspace_layout.show_code_buffer(buf)
end

-- Remove the old cycle bindings when reloading an existing session.
for _, key in ipairs({ "]b", "[b" }) do
	pcall(vim.keymap.del, "n", key)
end

vim.keymap.set("n", "<leader>n", function()
	cycle_group_buffer(1)
end, {
	desc = "Next buffer in current workspace group",
})

vim.keymap.set("n", "<leader>N", function()
	cycle_group_buffer(-1)
end, {
	desc = "Previous buffer in current workspace group",
})

vim.keymap.set("n", "<leader>C", close_other_code_buffers, {
	desc = "Close other code buffers",
})

vim.keymap.set("n", "<leader>sn", create_temporary_text_buffer, {
	desc = "Create temporary text buffer",
})

for index = 1, 9 do
	local target_index = index
	local old_key = ("<leader>%d"):format(index)
	local key = ("<A-%d>"):format(index)
	pcall(vim.keymap.del, "n", old_key)
	pcall(vim.keymap.del, "t", old_key)
	vim.keymap.set({ "n", "t" }, key, function()
		jump_to_group_buffer(target_index)
	end, {
		desc = ("Jump to buffer %d in current workspace group"):format(index),
	})
end

require("bufferline").setup({
	options = {
		mode = "buffers",
		always_show_bufferline = true,
		separator_style = "thin",
		close_command = close_buffer,
		right_mouse_command = close_buffer,
		left_mouse_command = function(buf)
			if vim.b[buf].panel_kind then
				panels.show_buffer(buf)
			else
				workspace_layout.show_code_buffer(buf)
			end
		end,
		custom_filter = function(buf)
			if vim.b[buf].panel_kind then
				return false
			end

			return vim.bo[buf].buftype == ""
				and vim.bo[buf].filetype ~= "NvimTree"
				and not workspace_layout.is_empty_code_buffer(buf)
		end,
		name_formatter = function(buf)
			local index = workspace_layout.group_buffer_position(buf.bufnr)
			if not index then
				return nil
			end

			return ("[%d] %s"):format(index, buf.name)
		end,
		groups = {
			items = {
				{
					name = "Files",
					matcher = function(buf)
						return workspace_layout.buffer_group(buf.id) == "code"
					end,
					separator = { style = bufferline_groups.separator.tab },
				},
			},
		},
		offsets = {
			{
				filetype = "NvimTree",
				text = "File Explorer",
				separator = true,
			},
		},
	},
})

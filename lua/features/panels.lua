local map = vim.keymap.set
local workspace_layout = require("features.workspace_layout")
local M = {}

local function find_panel_buffer(kind, excluded_buf)
	local buffers = vim.api.nvim_list_bufs()

	for index = #buffers, 1, -1 do
		local buf = buffers[index]
		if buf ~= excluded_buf
			and vim.api.nvim_buf_is_valid(buf)
			and vim.b[buf].panel_kind == kind
		then
			return buf
		end
	end
end

local function set_panel_cwd(win, buf)
	local cwd = vim.b[buf].panel_cwd
	if not cwd or vim.fn.isdirectory(cwd) ~= 1 then
		return
	end

	vim.api.nvim_win_call(win, function()
		vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
	end)
end

local function open_existing_panel(kind)
	if workspace_layout.focus_panel(kind) then
		return true
	end

	local buf = find_panel_buffer(kind)
	if not buf then
		return false
	end

	return workspace_layout.open_panel(kind, buf, true, vim.b[buf].panel_cwd) ~= nil
end

local function create_new_panel_buffer(kind)
	local cwd = vim.fn.getcwd()
	local scratch = vim.api.nvim_create_buf(false, true)
	local win = workspace_layout.find_panel_window(kind)

	workspace_layout.mark_panel(kind, scratch, cwd)

	if win then
		workspace_layout.focus_panel(kind)
		vim.api.nvim_win_set_buf(win, scratch)
	else
		win = workspace_layout.open_panel(kind, scratch, true, cwd)
	end

	if not win then
		vim.api.nvim_buf_delete(scratch, { force = true })
		return false
	end

	vim.api.nvim_win_call(win, function()
		vim.cmd("lcd " .. vim.fn.fnameescape(cwd))

		if kind == "codex" then
			vim.cmd("terminal codex --approve-for-me --no-alt-screen")
		else
			vim.cmd("terminal")
		end
	end)

	local buf = vim.api.nvim_win_get_buf(win)
	workspace_layout.mark_panel(kind, buf, cwd)
	workspace_layout.focus_panel(kind)
	return true, buf
end

local function create_panel(kind)
	if open_existing_panel(kind) then
		return true
	end

	return create_new_panel_buffer(kind)
end

M.open_existing = open_existing_panel
M.open_or_create = create_panel
M.new_buffer = create_new_panel_buffer

function M.toggle_focus(kind)
	local win = workspace_layout.find_panel_window(kind)
	if win and win == vim.api.nvim_get_current_win() then
		return workspace_layout.hide_panel(kind)
	end

	return create_panel(kind)
end

function M.show_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local kind = vim.b[buf].panel_kind
	if kind ~= "terminal" and kind ~= "codex" then
		return false
	end

	local win = workspace_layout.find_panel_window(kind)
	if win then
		workspace_layout.focus_panel(kind)
		vim.api.nvim_win_set_buf(win, buf)
		set_panel_cwd(win, buf)
		workspace_layout.focus_panel(kind)
		return true
	end

	return workspace_layout.open_panel(kind, buf, true, vim.b[buf].panel_cwd) ~= nil
end

function M.close_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local kind = vim.b[buf].panel_kind
	if kind ~= "terminal" and kind ~= "codex" then
		return false
	end

	workspace_layout.detach_buffer(buf)
	vim.api.nvim_buf_delete(buf, { force = true })
	workspace_layout.reflow()
	return true
end

local function reset_codex_buffer(buf)
	local channel = vim.bo[buf].channel
	if type(channel) ~= "number" or channel <= 0 then
		vim.notify("Codex terminal is not running", vim.log.levels.ERROR)
		return false
	end

	local ok, err = pcall(function()
		-- Codex uses CSI-u keyboard reporting. A raw <CR> is decoded as
		-- Ctrl-M (insert newline), while CSI 13 u is an unmodified Enter.
		vim.api.nvim_chan_send(channel, "/new\27[13u")
	end)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return false
	end

	return true
end

-- Clear obsolete bindings when reloading an existing session.
for _, key in ipairs({
	"<leader>nt",
	"<leader>nc",
	"<leader>oc",
	"<leader>ot",
}) do
	pcall(vim.keymap.del, "n", key)
end

local function close_current_code_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local ok, err = pcall(function()
		if vim.bo[buf].modifiable and vim.bo[buf].modified then
			vim.cmd("write")
		end

		workspace_layout.detach_buffer(buf)
		require("mini.bufremove").delete(buf, false)
	end)

	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

map("n", "<leader>q", function()
	workspace_layout.repair_buffer_routes()
	local group = workspace_layout.window_group(vim.api.nvim_get_current_win())

	if group == "codex" then
		local buf = vim.api.nvim_get_current_buf()
		if #workspace_layout.list_group_buffers("codex", false) > 1 then
			M.close_buffer(buf)
		else
			reset_codex_buffer(buf)
		end
		return
	end

	if group == "terminal" then
		M.close_buffer(vim.api.nvim_get_current_buf())
		return
	end

	if group == "code"
		and workspace_layout.buffer_group(vim.api.nvim_get_current_buf()) == "code"
	then
		close_current_code_buffer()
		return
	end

	vim.cmd("close")
end, {
	desc = "Close buffer/window or reset last Codex buffer",
})

map("n", "<leader>hc", function()
	workspace_layout.hide_panel("codex")
end, {
	desc = "Hide Codex panel",
})

map("n", "<leader>ht", function()
	workspace_layout.hide_panel("terminal")
end, {
	desc = "Hide terminal panel",
})

map("n", "<leader>st", function()
	create_new_panel_buffer("terminal")
end, {
	desc = "Create new terminal buffer",
})

map("n", "<leader>sc", function()
	create_new_panel_buffer("codex")
end, {
	desc = "Create new Codex buffer",
})

map("n", "<leader><leader>r", function()
	workspace_layout.reset()
	create_panel("codex")
end, {
	desc = "Reset workspace layout and open Codex",
})

return M

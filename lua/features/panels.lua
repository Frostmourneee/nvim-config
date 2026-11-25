local map = vim.keymap.set
local codex_status = require("features.codex_status")
local workspace_layout = require("features.workspace_layout")
local M = {}

local bridge_warning_shown = false

local function strip_codex_ui_margin(line)
	if line:sub(1, 2) == "  " then
		return line:sub(3)
	end

	local bullet_margin = "• "
	if line:sub(1, #bullet_margin) == bullet_margin then
		return line:sub(#bullet_margin + 1)
	end

	return line
end

local function warn_bridge(message)
	if bridge_warning_shown then
		return
	end

	bridge_warning_shown = true
	vim.notify(message, vim.log.levels.WARN)
end

local function rpc_server()
	if type(vim.v.servername) == "string" and vim.v.servername ~= "" then
		return vim.v.servername
	end

	local ok, address = pcall(vim.fn.serverstart)
	if ok and type(address) == "string" and address ~= "" then
		return address
	end

	warn_bridge("Codex status bridge unavailable: Neovim RPC server failed")
end

local function nvim_client()
	for _, candidate in ipairs({
		vim.v.progpath,
		vim.fn.exepath("nvim"),
	}) do
		if type(candidate) == "string"
			and candidate ~= ""
			and vim.fn.executable(candidate) == 1
		then
			return candidate
		end
	end

	warn_bridge("Codex status bridge unavailable: Neovim client not found")
end

local function new_codex_instance(buf)
	local uv = vim.uv or vim.loop
	return ("%d:%d:%s"):format(
		vim.fn.getpid(),
		buf,
		tostring(uv.hrtime())
	)
end

local function codex_bridge_env(buf, instance)
	local server = rpc_server()
	local client = nvim_client()
	if not server or not client then
		return nil
	end

	return {
		NVIM_CODEX_STATUS_BRIDGE = "1",
		NVIM_CODEX_SERVER = server,
		NVIM_CODEX_BUFFER = tostring(buf),
		NVIM_CODEX_INSTANCE = instance,
		NVIM_CODEX_CLIENT = client,
	}
end

local function start_codex(buf, cwd)
	vim.bo[buf].buflisted = true
	map("n", "yy", function()
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local lines = vim.api.nvim_buf_get_lines(buf, row - 1, row - 1 + vim.v.count1, false)
		for index, line in ipairs(lines) do
			lines[index] = strip_codex_ui_margin(line)
		end
		for _, register in ipairs({ '"', "0", "+" }) do
			vim.fn.setreg(register, lines, "V")
		end
	end, { buffer = buf, desc = "Yank Codex lines without UI margin" })

	local instance = new_codex_instance(buf)
	if not codex_status.bind(buf, instance) then
		vim.notify("Failed to initialize Codex status", vim.log.levels.ERROR)
		return false
	end

	local options = {
		cwd = cwd,
		term = true,
		on_exit = function()
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf)
					and vim.b[buf].codex_status_instance == instance
				then
					codex_status.set(buf, "idle")
				end
			end)
		end,
	}
	local env = codex_bridge_env(buf, instance)
	if env then
		options.env = env
	end

	local ok, job = pcall(
		vim.fn.jobstart,
		{
			"codex",
			"--profile",
			"nvim",
			"--approve-for-me",
			"--no-alt-screen",
		},
		options
	)

	if not ok or type(job) ~= "number" or job <= 0 then
		vim.notify("Failed to start Codex terminal", vim.log.levels.ERROR)
		return false
	end

	return true
end

local function find_panel_buffer(kind, excluded_buf)
	local remembered = workspace_layout.remembered_panel_buffer(kind)
	if remembered and remembered ~= excluded_buf then
		return remembered
	end

	return workspace_layout.find_group_buffer(kind, excluded_buf, false)
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

local function tree_cwd()
	local ok, core = pcall(require, "nvim-tree.core")
	local cwd = ok and core.get_cwd() or nil

	if cwd and vim.fn.isdirectory(cwd) == 1 then
		return cwd
	end

	return vim.fn.getcwd(-1, -1)
end

local function create_new_panel_buffer(kind)
	local cwd = tree_cwd()
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

	local started = true
	vim.api.nvim_win_call(win, function()
		vim.cmd("lcd " .. vim.fn.fnameescape(cwd))

		if kind == "codex" then
			started = start_codex(scratch, cwd)
		else
			vim.cmd("terminal")
		end
	end)
	if not started then
		workspace_layout.detach_buffer(scratch)
		if vim.api.nvim_buf_is_valid(scratch) then
			pcall(vim.api.nvim_buf_delete, scratch, { force = true })
		end
		workspace_layout.reflow()
		return false
	end

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
		-- Mark /new as an explicit paste so Codex does not classify the rapid
		-- input as a paste burst, where the following Enter inserts a newline.
		-- CSI 13 u is then decoded as an unmodified Enter and submits it.
		vim.api.nvim_chan_send(channel, "\27[200~/new\27[201~\27[13u")
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
	local is_temporary = vim.b[buf].temporary_text_buffer == true
	local ok, err = pcall(function()
		if not is_temporary
			and vim.bo[buf].modifiable
			and vim.bo[buf].modified
		then
			vim.cmd("write")
		end

		workspace_layout.detach_buffer(buf)
		require("mini.bufremove").delete(buf, is_temporary)
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

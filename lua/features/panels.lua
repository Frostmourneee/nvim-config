local map = vim.keymap.set

local function mark_panel(kind, cwd)
	local buf = vim.api.nvim_get_current_buf()

	vim.b[buf].panel_kind = kind
	vim.b[buf].panel_cwd = cwd
	vim.bo[buf].bufhidden = "hide"
end

local function find_panels(kind)
	local result = {}

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].panel_kind == kind then
			table.insert(result, buf)
		end
	end

	return result
end

local function hide_single_panel(kind)
	local buffers = find_panels(kind)
	if #buffers ~= 1 then
		return
	end

	local buf = buffers[1]
	local windows = vim.fn.win_findbuf(buf)
	if #windows ~= 1 then
		return
	end

	local win = windows[1]
	vim.b[buf].panel_width = vim.api.nvim_win_get_width(win)
	vim.b[buf].panel_height = vim.api.nvim_win_get_height(win)
	vim.api.nvim_win_hide(win)
end

local function open_single_panel(kind)
	local buffers = find_panels(kind)
	if #buffers ~= 1 then
		return
	end

	local buf = buffers[1]
	if #vim.fn.win_findbuf(buf) > 0 then
		return
	end

	if kind == "codex" then
		vim.cmd("belowright vsplit")
	else
		vim.cmd("belowright split")
	end

	local cwd = vim.b[buf].panel_cwd
	if cwd then
		vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
	end

	vim.api.nvim_win_set_buf(0, buf)

	if kind == "codex" then
		vim.api.nvim_win_set_width(0, vim.b[buf].panel_width or 80)
	else
		vim.api.nvim_win_set_height(0, vim.b[buf].panel_height or 5)
	end
end

map("n", "<leader>q", function()
	if vim.b.panel_kind then
		vim.api.nvim_buf_delete(0, { force = true })
		return
	end

	local buftype = vim.bo.buftype
	local modifiable = vim.bo.modifiable
	local modified = vim.bo.modified

	if buftype == "" and modifiable and modified then
		vim.cmd("wq")
	else
		vim.cmd("q")
	end
end, {
	desc = "Close buffer/window",
})

map("n", "<leader>st", function()
	local cwd = vim.fn.getcwd()

	vim.cmd("belowright split")
	vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
	vim.cmd("terminal")

	mark_panel("terminal", cwd)
	vim.api.nvim_win_set_height(0, 10)
end, {
	desc = "Create terminal",
})

map("n", "<leader>sc", function()
	local cwd = vim.fn.getcwd()

	vim.cmd("belowright vsplit")
	vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
	vim.cmd("terminal codex --approve-for-me --no-alt-screen")

	mark_panel("codex", cwd)
	vim.api.nvim_win_set_width(0, 80)
end, {
	desc = "Create Codex terminal",
})

map("n", "<leader>hc", function()
	hide_single_panel("codex")
end, {
	desc = "Hide the single Codex panel",
})

map("n", "<leader>oc", function()
	open_single_panel("codex")
end, {
	desc = "Open the single Codex panel",
})

map("n", "<leader>ht", function()
	hide_single_panel("terminal")
end, {
	desc = "Hide the single terminal panel",
})

map("n", "<leader>ot", function()
	open_single_panel("terminal")
end, {
	desc = "Open the single terminal panel",
})

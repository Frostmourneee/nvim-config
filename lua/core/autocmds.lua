local number_statuscolumn = "%s %{v:lnum} %{v:relnum} "

local prose_filetypes = {
	markdown = true,
	text = true,
}

local function configure_wrapping(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local buf = vim.api.nvim_win_get_buf(win)
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
	local enabled = prose_filetypes[filetype] == true

	for _, option in ipairs({ "wrap", "linebreak", "breakindent" }) do
		vim.api.nvim_set_option_value(option, enabled, {
			scope = "local",
			win = win,
		})
	end
end

local function configure_window(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local buf = vim.api.nvim_win_get_buf(win)
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
	local is_normal_buffer = buftype == "" and filetype ~= "NvimTree"

	vim.api.nvim_set_option_value("number", is_normal_buffer, {
		scope = "local",
		win = win,
	})
	vim.api.nvim_set_option_value("relativenumber", is_normal_buffer, {
		scope = "local",
		win = win,
	})
	vim.api.nvim_set_option_value(
		"statuscolumn",
		is_normal_buffer and number_statuscolumn or "",
		{
			scope = "local",
			win = win,
		}
	)
end

local window_group = vim.api.nvim_create_augroup("UserWindowAppearance", {
	clear = true,
})

vim.api.nvim_create_autocmd({
	"BufWinEnter",
	"FileType",
	"TermOpen",
	"WinEnter",
}, {
	group = window_group,
	callback = function()
		configure_window(vim.api.nvim_get_current_win())
	end,
})

local wrapping_group = vim.api.nvim_create_augroup("UserFiletypeWrapping", {
	clear = true,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType" }, {
	group = wrapping_group,
	callback = function()
		configure_wrapping(vim.api.nvim_get_current_win())
	end,
})

for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	configure_window(win)
	configure_wrapping(win)
end

vim.cmd.colorscheme("catppuccin")

local function brighten_inactive_statusline()
	local active = vim.api.nvim_get_hl(0, {
		name = "StatusLine",
		link = false,
	})
	local inactive = vim.api.nvim_get_hl(0, {
		name = "StatusLineNC",
		link = false,
	})

	inactive.fg = active.fg
	inactive.ctermfg = active.ctermfg
	vim.api.nvim_set_hl(0, "StatusLineNC", inactive)
end

brighten_inactive_statusline()

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("UserStatuslineColors", {
		clear = true,
	}),
	callback = brighten_inactive_statusline,
})

-- ANSI blue used by shell prompts inside Neovim terminals.
vim.g.terminal_color_4 = "#89b4fa"
vim.g.terminal_color_12 = "#89b4fa"

vim.api.nvim_set_hl(0, "LineNr", {
	fg = "#6c7086",
	bold = false,
})

vim.api.nvim_set_hl(0, "CursorLineNr", {
	fg = "#f9e2af",
	bold = true,
})

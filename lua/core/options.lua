vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.confirm = true
vim.opt.swapfile = true

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.statuscolumn = "%s %{v:lnum} %{v:relnum} "
vim.opt.signcolumn = "yes"

vim.opt.shiftwidth = 4
vim.opt.tabstop = 4

vim.opt.termguicolors = true
vim.opt.guicursor:append("t:ver25-blinkon0")
vim.opt.clipboard = "unnamedplus"

vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.list = true
vim.opt.listchars = {
	tab = "  ",
	nbsp = "␣",
	trail = "+",
}

vim.opt.wrap = false
vim.opt.scrolloff = 8

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldcolumn = "1"

local cargo_bin = vim.fn.expand("~/.cargo/bin")
local path_entries = vim.split(vim.env.PATH or "", ":", { plain = true })

if not vim.tbl_contains(path_entries, cargo_bin) then
	vim.env.PATH = cargo_bin .. ":" .. (vim.env.PATH or "")
end

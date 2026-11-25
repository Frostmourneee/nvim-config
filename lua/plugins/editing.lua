local treesitter_group = vim.api.nvim_create_augroup("UserTreesitterStart", {
	clear = true,
})

vim.api.nvim_create_autocmd("FileType", {
	group = treesitter_group,
	pattern = {
		"rust",
		"c",
		"cpp",
		"go",
		"gomod",
		"gosum",
		"gowork",
		"python",
		"markdown",
	},
	callback = function()
		vim.treesitter.start()
	end,
})

require("nvim-autopairs").setup({
	map_cr = true,
})

local flash = require("flash")
flash.setup({})

vim.keymap.set({ "n", "v", "o" }, "s", flash.jump, {
	desc = "Flash jump",
})

vim.keymap.set({ "n", "v", "o" }, "S", flash.treesitter, {
	desc = "Flash Treesitter",
})

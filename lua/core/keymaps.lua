local map = vim.keymap.set

map("n", "<Esc>", function()
	vim.cmd("nohlsearch")
	vim.lsp.buf.clear_references()
end, {
	silent = true,
	desc = "Clear search and LSP highlights",
})

map("n", "<leader>sy", function()
	local text = vim.fn.getreg("0"):gsub("\n+$", "")

	if text == "" then
		vim.notify("Yank register is empty", vim.log.levels.INFO)
		return
	end

	vim.fn.setreg("/", "\\V" .. vim.fn.escape(text, "\\"))

	local ok = pcall(vim.cmd, "normal! n")
	if not ok then
		vim.notify("Yanked text not found", vim.log.levels.INFO)
	end
end, {
	desc = "Search for yanked text",
})

map("n", "<leader>a", "<cmd>%y<CR>", {
	desc = "Copy whole file",
})

map("n", "<C-A-s>", function()
	require("features.config_tree").toggle()
end, {
	desc = "Toggle Neovim settings workspace",
})

map("t", "<Esc>", "<C-\\><C-n>", {
	desc = "Exit terminal mode",
})

map("n", "<leader>w", "<cmd>write<CR>", {
	desc = "Write buffer",
})

map("n", "<leader>ur", "<cmd>edit<CR>", {
	desc = "Reload current buffer from disk",
})

map("n", "<leader>sd", "<cmd>belowright split<CR>", {
	desc = "Copy current window down",
})

map("n", "<leader>sr", "<cmd>belowright vsplit<CR>", {
	desc = "Copy current window right",
})

map("n", "<leader>su", "<cmd>aboveleft split<CR>", {
	desc = "Copy current window up",
})

map("n", "<leader>sl", "<cmd>aboveleft vsplit<CR>", {
	desc = "Copy current window left",
})

map({ "n", "v" }, "p", "p=']", {
	desc = "Paste and auto-indent",
})

map("n", "<leader>cd", "<cmd>belowright horizontal terminal<CR>", {
	desc = "New terminal down",
})

map("n", "<leader>cu", "<cmd>aboveleft horizontal terminal<CR>", {
	desc = "New terminal up",
})

map("n", "<leader>cr", "<cmd>belowright vertical terminal<CR>", {
	desc = "New terminal right",
})

map("n", "<leader>cl", "<cmd>aboveleft vertical terminal<CR>", {
	desc = "New terminal left",
})

map({ "i", "t" }, "<A-i>", "<Up>", { desc = "Move up" })
map({ "i", "t" }, "<A-j>", "<Left>", { desc = "Move left" })
map({ "i", "t" }, "<A-k>", "<Down>", { desc = "Move down" })
map({ "i", "t" }, "<A-l>", "<Right>", { desc = "Move right" })

map({ "n", "v" }, "<A-i>", "<C-u>", { desc = "Scroll up half a screen" })
map({ "n", "v" }, "<A-j>", "zH", { desc = "Scroll left half a screen" })
map({ "n", "v" }, "<A-k>", "<C-d>", { desc = "Scroll down half a screen" })
map({ "n", "v" }, "<A-l>", "zL", { desc = "Scroll right half a screen" })

map({ "n", "x" }, "<leader>ca", function()
	require("features.codex_navigation").latest_answer()
end, {
	desc = "Jump to latest Codex answer (10 lines below top)",
})

-- Custom movement layout:
-- i = up, j = left, k = down, l = right.
local move_opts = {
	noremap = true,
	silent = true,
	nowait = true,
}

map({ "n", "v", "o" }, "i", "k", move_opts)
map({ "n", "v", "o" }, "j", "h", move_opts)
map({ "n", "v", "o" }, "k", "j", move_opts)
map({ "n", "v", "o" }, "l", "l", move_opts)

-- h means "inner" in operator-pending/visual mode and enters Insert in Normal mode.
map({ "o", "v" }, "h", "i", {
	noremap = false,
	silent = true,
})
map("n", "h", "i", {
	noremap = true,
	silent = true,
})

map("n", "<leader>z", "zA", {
	desc = "Toggle current fold recursively",
})

map("n", "<leader>Z", function()
	if vim.wo.foldlevel == 0 then
		vim.cmd("normal! zR")
	else
		vim.cmd("normal! zM")
	end
end, {
	desc = "Toggle all folds",
})

local map = vim.keymap.set

-- Preserve Neovim's built-in gx callback across configuration reloads.
if type(_G.__default_gx_callback) ~= "function" then
	local default_gx = vim.fn.maparg("gx", "n", false, true)
	_G.__default_gx_callback = default_gx.callback
end

map("n", "gx", function()
	require("features.smart_open").open(_G.__default_gx_callback)
end, {
	desc = "Open URI normally or Codex file in central code pane",
})

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
	desc = "Toggle temporary Neovim settings workspace and preserve panels",
})

map("t", "<Esc>", "<C-\\><C-n>", {
	desc = "Exit terminal mode",
})

map("n", "<leader>w", "<cmd>write<CR>", {
	desc = "Write buffer",
})

map("n", "<leader>tw", function()
	local enabled = not vim.wo.wrap

	vim.wo.wrap = enabled
	vim.wo.linebreak = enabled
	vim.wo.breakindent = enabled

	vim.notify("Line wrapping " .. (enabled and "enabled" or "disabled"))
end, {
	desc = "Toggle line wrapping in current window",
})

map("n", "<leader>Q", function()
	local modified_temporary_buffers = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf)
			and vim.b[buf].temporary_text_buffer == true
			and vim.bo[buf].modified
		then
			table.insert(modified_temporary_buffers, buf)
			vim.bo[buf].modified = false
		end
	end

	local ok, err = pcall(vim.cmd, "confirm qall")
	for _, buf in ipairs(modified_temporary_buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.bo[buf].modified = true
		end
	end

	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end, {
	desc = "Exit Neovim without saving temporary text buffers",
})

map("n", "<leader>ur", "<cmd>edit<CR>", {
	desc = "Reload current buffer from disk",
})

map("n", "<leader>R", "<cmd>ReloadConfig<CR>", {
	desc = "Reload Neovim configuration",
})

-- Remove the old free-form split mappings when reloading an existing session.
for _, key in ipairs({
	"<leader>sd",
	"<leader>sr",
	"<leader>su",
	"<leader>sl",
	"<leader>cd",
	"<leader>cu",
	"<leader>cr",
	"<leader>cl",
}) do
	pcall(vim.keymap.del, "n", key)
end

map({ "n", "v" }, "p", "p=']", {
	desc = "Paste and auto-indent",
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

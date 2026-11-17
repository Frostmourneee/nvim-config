local smart_splits = require("smart-splits")

smart_splits.setup({
	ignored_buftypes = {
		"nofile",
		"quickfix",
		"prompt",
	},
	ignored_filetypes = { "NvimTree" },
	default_amount = 3,
	at_edge = "wrap",
	float_win_behavior = "previous",
	move_cursor_same_row = false,
	cursor_follows_swapped_bufs = false,
	ignored_events = {
		"BufEnter",
		"WinEnter",
	},
	disable_multiplexer_nav_when_zoomed = true,
	zellij_move_focus_or_tab = false,
	log_level = "info",
})

local map = vim.keymap.set

map("n", "<leader>j", smart_splits.move_cursor_left, {
	desc = "Move to left split",
})
map("n", "<leader>k", smart_splits.move_cursor_down, {
	desc = "Move to lower split",
})
map("n", "<leader>i", smart_splits.move_cursor_up, {
	desc = "Move to upper split",
})
map("n", "<leader>l", smart_splits.move_cursor_right, {
	desc = "Move to right split",
})

-- Clear the previous resize bindings when reloading an existing session.
for _, key in ipairs({ "<S-j>", "<S-k>", "<S-i>", "<S-l>" }) do
	pcall(vim.keymap.del, "n", key)
end

map("n", "<C-j>", smart_splits.resize_left, {
	desc = "Resize split left",
})
map("n", "<C-k>", smart_splits.resize_down, {
	desc = "Resize split down",
})
map("n", "<C-i>", smart_splits.resize_up, {
	desc = "Resize split up",
})
map("n", "<C-l>", smart_splits.resize_right, {
	desc = "Resize split right",
})

map("n", "<leader><leader>j", smart_splits.swap_buf_left, {
	desc = "Swap buffer left",
})
map("n", "<leader><leader>k", smart_splits.swap_buf_down, {
	desc = "Swap buffer down",
})
map("n", "<leader><leader>i", smart_splits.swap_buf_up, {
	desc = "Swap buffer up",
})
map("n", "<leader><leader>l", smart_splits.swap_buf_right, {
	desc = "Swap buffer right",
})

map("n", "<C-\\>", smart_splits.move_cursor_previous, {
	desc = "Move to previous split",
})

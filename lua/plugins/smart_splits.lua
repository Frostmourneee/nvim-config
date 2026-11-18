local smart_splits = require("smart-splits")
local workspace_layout = require("features.workspace_layout")
local panels = require("features.panels")

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

-- Clear the previous double-leader area bindings when reloading a session.
for _, key in ipairs({
	"<leader><leader>i",
	"<leader><leader>j",
	"<leader><leader>k",
	"<leader><leader>l",
}) do
	pcall(vim.keymap.del, "n", key)
end

map("n", "<leader>i", function()
	workspace_layout.focus_area("code")
end, {
	desc = "Jump to code window",
})
map("n", "<leader>j", function()
	workspace_layout.toggle_tree_focus()
end, {
	desc = "Toggle tree focus/open/hide",
})
map("n", "<leader>k", function()
	panels.toggle_focus("terminal")
end, {
	desc = "Toggle terminal focus/open/hide",
})
map("n", "<leader>l", function()
	panels.toggle_focus("codex")
end, {
	desc = "Toggle Codex focus/open/hide",
})

-- Clear the previous resize bindings when reloading an existing session.
for _, key in ipairs({ "<S-j>", "<S-k>", "<S-i>", "<S-l>" }) do
	pcall(vim.keymap.del, "n", key)
end

local function resize(direction, fallback)
	return function()
		local amount = vim.v.count1 * 3

		if workspace_layout.resize_managed_float(direction, amount) then
			return
		end

		fallback(amount)
		workspace_layout.schedule_reflow()
	end
end

map("n", "<C-j>", resize("left", smart_splits.resize_left), {
	desc = "Resize split or float left",
})
map("n", "<C-k>", resize("down", smart_splits.resize_down), {
	desc = "Resize split or float down",
})
map("n", "<C-i>", resize("up", smart_splits.resize_up), {
	desc = "Resize split or float up",
})
map("n", "<C-l>", resize("right", smart_splits.resize_right), {
	desc = "Resize split or float right",
})

map("n", "<C-\\>", smart_splits.move_cursor_previous, {
	desc = "Move to previous split",
})

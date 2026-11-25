require("render-markdown").setup({})

vim.keymap.set("n", "<leader>m", "<cmd>RenderMarkdown buf_toggle<cr>", {
	desc = "Toggle Markdown rendering",
})

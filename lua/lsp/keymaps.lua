local function set_lsp_keymaps(bufnr)
	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, {
			buffer = bufnr,
			silent = true,
			desc = desc,
		})
	end

	map("gd", vim.lsp.buf.definition, "Go to definition")
	map("gi", vim.lsp.buf.implementation, "Go to implementation")
	map("<leader>r", vim.lsp.buf.rename, "Rename symbol")

	map("<leader>d", function()
		vim.lsp.buf.hover({
			border = "rounded",
		})
	end, "Show documentation")

	map("<leader>f", function()
		vim.lsp.buf.clear_references()
		vim.lsp.buf.document_highlight()
	end, "Highlight semantic symbol references")

	map("<leader>e", vim.diagnostic.open_float, "Open diagnostics")

	map("<leader>uf", function()
		vim.lsp.buf.code_action({
			context = {
				only = { "quickfix" },
			},
			apply = true,
		})
	end, "Quick fix")
end

-- Remove the old global LSP mappings when this refactor is sourced in a
-- running instance. Fresh starts do not have these mappings yet.
for _, lhs in ipairs({
	"gd",
	"gi",
	"<leader>r",
	"<leader>d",
	"<leader>f",
	"<leader>e",
	"<leader>uf",
}) do
	pcall(vim.keymap.del, "n", lhs)
end

local lsp_group = vim.api.nvim_create_augroup("UserLspKeymaps", {
	clear = true,
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = lsp_group,
	callback = function(args)
		set_lsp_keymaps(args.buf)
	end,
})

-- Also configure buffers whose clients were already attached before a reload.
for _, client in ipairs(vim.lsp.get_clients()) do
	for bufnr in pairs(client.attached_buffers or {}) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			set_lsp_keymaps(bufnr)
		end
	end
end

local capabilities = require("blink.cmp").get_lsp_capabilities()

vim.lsp.config("gopls", {
	capabilities = capabilities,
})

vim.lsp.config("pyright", {
	capabilities = capabilities,

	before_init = function(_, config)
		if not config.root_dir then
			return
		end

		local python = config.root_dir .. "/.venv/bin/python"
		if vim.uv.fs_stat(python) then
			config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
				python = {
					pythonPath = python,
				},
			})
		end
	end,
})

vim.lsp.config("ruff", {
	capabilities = capabilities,

	-- Let Pyright provide hover documentation.
	on_attach = function(client)
		client.server_capabilities.hoverProvider = false
	end,
})

vim.lsp.config("clangd", {
	capabilities = capabilities,
	cmd = {
		"/home/frostmourneee/.local/bin/clangd/bin/clangd",
		"--background-index",
		"--clang-tidy",
	},
})

vim.lsp.config("rust_analyzer", {
	capabilities = capabilities,
	cmd = {
		"/home/frostmourneee/.cargo/bin/rust-analyzer",
	},
	settings = {
		["rust-analyzer"] = {
			checkOnSave = false,
		},
	},
})

for _, server in ipairs({
	"gopls",
	"pyright",
	"ruff",
	"clangd",
	"rust_analyzer",
}) do
	vim.lsp.enable(server)
end

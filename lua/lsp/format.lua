local format_group = vim.api.nvim_create_augroup("UserLspFormat", {
	clear = true,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	group = format_group,
	pattern = "*.go",
	callback = function(args)
		local client = vim.lsp.get_clients({
			name = "gopls",
			bufnr = args.buf,
		})[1]

		if not client then
			return
		end

		local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
		params.context = {
			only = { "source.organizeImports" },
			diagnostics = {},
		}

		local response = client:request_sync(
			"textDocument/codeAction",
			params,
			3000,
			args.buf
		)

		for _, action in ipairs(response and response.result or {}) do
			if action.edit then
				vim.lsp.util.apply_workspace_edit(
					action.edit,
					client.offset_encoding
				)
			end
		end

		vim.lsp.buf.format({
			bufnr = args.buf,
			id = client.id,
			async = false,
		})
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	group = format_group,
	pattern = "*.py",
	callback = function(args)
		vim.lsp.buf.format({
			bufnr = args.buf,
			name = "ruff",
			async = false,
		})
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	group = format_group,
	pattern = {
		"*.c",
		"*.cc",
		"*.cpp",
		"*.cxx",
		"*.h",
		"*.hh",
		"*.hpp",
		"*.hxx",
	},
	callback = function(args)
		vim.lsp.buf.format({
			bufnr = args.buf,
			name = "clangd",
			async = false,
		})
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	group = format_group,
	pattern = "*.rs",
	callback = function(args)
		vim.lsp.buf.format({
			bufnr = args.buf,
			name = "rust_analyzer",
			async = false,
		})
	end,
})

local config_modules = {
	"core.options",
	"core.keymaps",
	"core.neovide",
	"features.codex_status",
	"features.workspace_layout",
	"features.panels",
	"features.config_tree",
	"features.codex_navigation",
	"features.voice_dictation",
	"packages",
	"plugins.editing",
	"plugins.buffers",
	"plugins.nvim_tree",
	"plugins.smart_splits",
	"plugins.completion",
	"plugins",
	"lsp.keymaps",
	"lsp.format",
	"lsp.servers",
	"lsp",
	"core.autocmds",
	"core.ui",
	"core.reload",
}

vim.api.nvim_create_user_command("ReloadConfig", function()
	for _, module in ipairs(config_modules) do
		package.loaded[module] = nil
	end

	dofile(vim.env.MYVIMRC)
	vim.notify("Neovim configuration reloaded")
end, {
	desc = "Reload the complete Neovim configuration",
	force = true,
})

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("core.options")
require("core.keymaps")
require("core.neovide")
require("features.panels")
require("features.voice_dictation").setup()

require("packages")
require("plugins")
require("lsp")

require("core.autocmds")
require("core.ui")
require("core.reload")

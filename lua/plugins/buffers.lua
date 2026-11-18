local MiniBufremove = require("mini.bufremove")
local workspace_layout = require("features.workspace_layout")
local panels = require("features.panels")

MiniBufremove.setup()

local function close_buffer(buf)
	if vim.b[buf].panel_kind then
		panels.close_buffer(buf)
		return
	end

	local ok, err = pcall(MiniBufremove.delete, buf, false)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

require("bufferline").setup({
	options = {
		mode = "buffers",
		always_show_bufferline = true,
		separator_style = "thin",
		close_command = close_buffer,
		right_mouse_command = close_buffer,
		left_mouse_command = function(buf)
			if vim.b[buf].panel_kind then
				panels.show_buffer(buf)
			else
				workspace_layout.show_code_buffer(buf)
			end
		end,
		custom_filter = function(buf)
			if vim.b[buf].panel_kind then
				return true
			end

			return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree"
		end,
		name_formatter = function(buf)
			local kind = vim.b[buf.bufnr].panel_kind
			if kind == "terminal" then
				return "Terminal " .. buf.bufnr
			end

			if kind == "codex" then
				return "Codex " .. buf.bufnr
			end
		end,
		offsets = {
			{
				filetype = "NvimTree",
				text = "File Explorer",
				separator = true,
			},
		},
	},
})

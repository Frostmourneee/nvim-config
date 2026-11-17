local M = {}

function M.from_nvim_tree(api)
	local node = api.tree.get_node_under_cursor()
	if not node then
		return
	end

	local dir = node.nodes ~= nil and node.absolute_path or vim.fs.dirname(node.absolute_path)
	local command

	if vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-paste") == 1 then
		command = {
			"wl-paste",
			"--no-newline",
			"--type",
			"image/png",
		}
	elseif vim.env.DISPLAY and vim.fn.executable("xclip") == 1 then
		command = {
			"xclip",
			"-selection",
			"clipboard",
			"-target",
			"image/png",
			"-out",
		}
	else
		vim.notify("Install wl-clipboard or xclip", vim.log.levels.ERROR)
		return
	end

	-- Keep output binary: do not set text = true.
	local result = vim.system(command, { text = false }):wait(3000)

	if result.code ~= 0 or not result.stdout or #result.stdout == 0 then
		vim.notify("Clipboard does not contain a PNG image", vim.log.levels.ERROR)
		return
	end

	local base = "screenshot-" .. os.date("%Y%m%d-%H%M%S")
	local path = vim.fs.joinpath(dir, base .. ".png")
	local suffix = 1

	while vim.uv.fs_stat(path) do
		path = vim.fs.joinpath(dir, base .. "-" .. suffix .. ".png")
		suffix = suffix + 1
	end

	local file, err = io.open(path, "wb")
	if not file then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end

	file:write(result.stdout)
	file:close()

	api.tree.reload()
	vim.notify("Saved " .. vim.fn.fnamemodify(path, ":t"))
end

return M

local paste_screenshot = require("features.paste_screenshot")

require("nvim-tree").setup({
	sync_root_with_cwd = true,

	filters = {
		git_ignored = false,
	},

	view = {
		number = false,
		relativenumber = false,
	},

	actions = {
		change_dir = {
			enable = true,
			global = true,
		},

		open_file = {
			resize_window = false,
		},
	},

	on_attach = function(bufnr)
		local api = require("nvim-tree.api")

		api.config.mappings.default_on_attach(bufnr)

		local function opts(desc)
			return {
				desc = "nvim-tree: " .. desc,
				buffer = bufnr,
				noremap = true,
				silent = true,
				nowait = true,
			}
		end

		local function open_and_focus()
			local node = api.tree.get_node_under_cursor()
			if not node then
				return
			end

			if node.nodes ~= nil then
				if not node.open then
					api.node.open.edit()
				end
			else
				api.node.open.vertical()
			end
		end

		local function open_keep_focus()
			local node = api.tree.get_node_under_cursor()
			if not node then
				return
			end

			if node.nodes ~= nil then
				if not node.open then
					api.node.open.edit()
				end
			else
				api.node.open.vertical()
				api.tree.focus()
			end
		end

		local function close_node()
			local node = api.tree.get_node_under_cursor()
			if not node then
				return
			end

			local cwd = vim.fn.getcwd()

			local function is_inside_cwd(path)
				return path == cwd or path:sub(1, #cwd + 1) == cwd .. "/"
			end

			if node.nodes ~= nil then
				if node.open then
					api.node.open.edit()
					return
				end

				local parent_path = vim.fn.fnamemodify(node.absolute_path, ":h")
				if is_inside_cwd(parent_path) and parent_path ~= cwd then
					api.node.navigate.parent()
					local parent = api.tree.get_node_under_cursor()
					if parent and parent.nodes ~= nil and parent.open then
						api.node.open.edit()
					end
				end
				return
			end

			local parent_path = vim.fn.fnamemodify(node.absolute_path, ":h")
			if is_inside_cwd(parent_path) and parent_path ~= cwd then
				api.node.navigate.parent()
				api.node.open.edit()
			end
		end

		vim.keymap.set("n", "<leader>p", function()
			paste_screenshot.from_nvim_tree(api)
		end, opts("Paste screenshot"))

		vim.keymap.set("n", "l", open_and_focus, opts("Open and focus"))
		vim.keymap.set("n", "L", open_keep_focus, opts("Open, keep focus on tree"))
		vim.keymap.set("n", "j", close_node, opts("Close"))
		vim.keymap.set("n", "J", api.tree.collapse_all, opts("Collapse all"))
	end,
})

vim.keymap.set("n", "<leader>t", "<cmd>NvimTreeToggle<CR>", {
	silent = false,
	desc = "Toggle nvim-tree",
})

vim.keymap.set("n", "<leader>os", function()
	require("features.config_tree").toggle_skills()
end, {
	silent = true,
	desc = "Toggle Codex skills workspace",
})

local M = {}

local namespace = vim.api.nvim_create_namespace("terminal.command_boundaries")

local function terminal_state(buf)
	local state = vim.b[buf].terminal_command_state
	if type(state) ~= "table" then
		state = {
			running = false,
		}
		vim.b[buf].terminal_command_state = state
	end

	return state
end

local function marker(buf, row)
	return vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, 0, {
		right_gravity = false,
	})
end

local function marker_row(buf, id)
	if type(id) ~= "number" then
		return nil
	end

	local position = vim.api.nvim_buf_get_extmark_by_id(buf, namespace, id, {})
	if #position == 0 then
		return nil
	end

	return position[1]
end

local group = vim.api.nvim_create_augroup("TerminalCommandBoundaries", {
	clear = true,
})

local function configure_terminal(buf)
	vim.bo[buf].buflisted = true

	vim.keymap.set("n", "<leader>e", function()
		require("features.workspace_layout").toggle_terminal_command_height()
	end, {
		buffer = buf,
		desc = "Toggle terminal height for the last completed command",
	})

	vim.keymap.set("n", "<leader>E", function()
		require("features.workspace_layout").toggle_terminal_full_height()
	end, {
		buffer = buf,
		desc = "Toggle terminal full height",
	})
end

-- Remove the short-lived global versions when reloading this configuration.
pcall(vim.keymap.del, "n", "<leader>e")
pcall(vim.keymap.del, "n", "<leader>E")

vim.api.nvim_create_autocmd("TermOpen", {
	group = group,
	callback = function(event)
		if vim.b[event.buf].panel_kind == "terminal" then
			configure_terminal(event.buf)
		end
	end,
})

vim.api.nvim_create_autocmd("TermRequest", {
	group = group,
	callback = function(event)
		if vim.b[event.buf].panel_kind ~= "terminal" then
			return
		end

		local kind = event.data.sequence:match("^\27]133;([ACD])")
		if not kind then
			return
		end

		local state = terminal_state(event.buf)
		local row = event.data.cursor[1]

		if kind == "A" then
			state.prompt = marker(event.buf, row)
		elseif kind == "C" then
			state.active_command = state.prompt
			state.running = true
		elseif kind == "D" and state.active_command then
			state.completed_command = state.active_command
			state.active_command = nil
			state.running = false
		end

		vim.b[event.buf].terminal_command_state = state
	end,
})

function M.shell_environment()
	if vim.fn.fnamemodify(vim.o.shell, ":t") ~= "bash" then
		return nil
	end

	return {
		PROMPT_COMMAND = [[__nvim_command_status=$?; printf '\033]133;D;%s\007\033]133;A\007' "$__nvim_command_status"]],
		PS0 = "\27]133;C\7",
	}
end

function M.completed_command_rows(buf)
	local state = terminal_state(buf)
	if state.running then
		return nil, "The terminal command is still running"
	end

	local start_row = marker_row(buf, state.completed_command)
	if not start_row then
		return nil, "No completed terminal command found"
	end

	local prompt_row = marker_row(buf, state.prompt)
	if not prompt_row then
		return nil, "Current terminal prompt not found"
	end

	return math.max(1, prompt_row - start_row + 1)
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == "terminal"
		and vim.b[buf].panel_kind == "terminal"
	then
		configure_terminal(buf)
	end
end

return M

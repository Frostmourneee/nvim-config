local M = {}

local function latest_message_line(buf)
	-- Read backwards in batches so long terminal histories stay cheap to scan.
	local last = vim.api.nvim_buf_line_count(buf)
	while last > 0 do
		local first = math.max(0, last - 256)
		local lines = vim.api.nvim_buf_get_lines(buf, first, last, false)
		for i = #lines, 1, -1 do
			-- Codex prefixes messages with a left-margin bullet. Continuation
			-- lines (including Markdown list bullets) have a two-space gutter.
			if lines[i]:match("^•%s") or lines[i] == "•" then
				return first + i
			end
		end
		last = first
	end
end

function M.latest_answer()
	if vim.bo.buftype ~= "terminal" then
		vim.notify("Use this shortcut in a Codex terminal", vim.log.levels.INFO)
		return
	end

	-- Always search from the end, regardless of the current scroll position.
	-- While a turn is running, the latest message may still be commentary.
	local line = latest_message_line(vim.api.nvim_get_current_buf())
	if not line then
		vim.notify("No Codex answer marker found in terminal scrollback", vim.log.levels.INFO)
		return
	end

	local padding = math.min(10, math.floor((vim.api.nvim_win_get_height(0) - 1) / 2))
	-- Terminal rows are already wrapped by Codex; this config uses nowrap.
	vim.fn.winrestview({
		lnum = line,
		col = 0,
		topline = math.max(1, line - padding),
		leftcol = 0,
		skipcol = 0,
	})
end

return M

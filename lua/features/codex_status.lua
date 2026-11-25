local M = {}

local valid_statuses = {
	idle = true,
	waiting = true,
	working = true,
}

local event_states = {
	Interrupt = "idle",
	PermissionRequest = "waiting",
	PostToolUse = "working",
	Stop = "finished",
	UserPromptSubmit = "working",
}

local terminal_events = {
	Interrupt = true,
	Stop = true,
}

local max_terminal_turns = 32
local approval_namespace = vim.api.nvim_create_namespace("CodexStatusApproval")

local highlights = {
	CodexStatusIdle = { fg = "#89b4fa" },
	CodexStatusIdleCurrent = { fg = "#89b4fa" },
	CodexStatusWaiting = { fg = "#f9e2af" },
	CodexStatusWaitingCurrent = { fg = "#f9e2af" },
	CodexStatusWorking = { fg = "#a6e3a1" },
	CodexStatusWorkingCurrent = { fg = "#a6e3a1" },
}

local refresh_title = function() end

local function apply_highlights()
	for name, value in pairs(highlights) do
		vim.api.nvim_set_hl(0, name, value)
	end
end

local function is_codex_buffer(buf)
	return type(buf) == "number"
		and vim.api.nvim_buf_is_valid(buf)
		and vim.b[buf].panel_kind == "codex"
end

local function read_state(buf)
	local saved = vim.b[buf].codex_status
	if type(saved) ~= "table" then
		return {
			status = "idle",
			needs_attention = false,
		}
	end

	return {
		status = valid_statuses[saved.status] and saved.status or "idle",
		needs_attention = saved.needs_attention == true,
	}
end

local function write_state(buf, value)
	vim.b[buf].codex_status = value
	refresh_title()
end

local function valid_identifier(value)
	return type(value) == "string"
		and #value > 0
		and #value <= 256
		and not value:find("%z")
end

local function valid_integer(value)
	return type(value) == "number"
		and value >= 0
		and value < math.huge
		and value == math.floor(value)
end

local function read_event_state(buf)
	local saved = vim.b[buf].codex_status_events
	local result = {
		last_monotonic_ns = 0,
		terminal_turns = {},
	}

	if type(saved) ~= "table" then
		return result
	end

	if valid_integer(saved.last_monotonic_ns) then
		result.last_monotonic_ns = saved.last_monotonic_ns
	end
	if valid_identifier(saved.active_turn_id) then
		result.active_turn_id = saved.active_turn_id
	end

	local seen = {}
	if type(saved.terminal_turns) == "table" then
		for _, turn_id in ipairs(saved.terminal_turns) do
			if valid_identifier(turn_id) and not seen[turn_id] then
				table.insert(result.terminal_turns, turn_id)
				seen[turn_id] = true
			end
		end
	end

	while #result.terminal_turns > max_terminal_turns do
		table.remove(result.terminal_turns, 1)
	end

	return result
end

local function write_event_state(buf, value)
	vim.b[buf].codex_status_events = value
end

local function terminal_turn_seen(value, turn_id)
	for _, candidate in ipairs(value.terminal_turns) do
		if candidate == turn_id then
			return true
		end
	end

	return false
end

local function remember_terminal_turn(value, turn_id)
	if terminal_turn_seen(value, turn_id) then
		return
	end

	table.insert(value.terminal_turns, turn_id)
	if #value.terminal_turns > max_terminal_turns then
		table.remove(value.terminal_turns, 1)
	end
end

local function is_focused(buf)
	return vim.api.nvim_get_current_buf() == buf
end

local function highlight_name(status, current)
	local suffix = current and "Current" or ""
	return ("CodexStatus%s%s"):format(
		status:sub(1, 1):upper() .. status:sub(2),
		suffix
	)
end

local function setup_approval_observer()
	pcall(vim.on_key, nil, approval_namespace)
	local enter = vim.keycode("<CR>")

	vim.on_key(function(key, typed)
		if key ~= enter
			and typed ~= enter
			and key ~= "\r"
			and typed ~= "\r"
			and key ~= "\n"
			and typed ~= "\n"
		then
			return
		end

		local buf = vim.api.nvim_get_current_buf()
		if vim.bo[buf].buftype ~= "terminal" then
			return
		end

		local value = M.get(buf)
		if not value or value.status ~= "waiting" then
			return
		end

		vim.schedule(function()
			if vim.api.nvim_get_current_buf() ~= buf then
				return
			end

			local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
			if mode ~= "t" and mode ~= "i" then
				return
			end

			local current = M.get(buf)
			if current and current.status == "waiting" then
				M.set(buf, "working")
			end
		end)
	end, approval_namespace)
end

function M.setup(options)
	options = options or {}
	refresh_title = options.refresh or function() end
	apply_highlights()

	local group = vim.api.nvim_create_augroup("CodexStatus", {
		clear = true,
	})

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = apply_highlights,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = group,
		callback = function(args)
			local buf = args.buf
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					M.mark_seen(buf)
				end
			end)
		end,
	})

	setup_approval_observer()
end

function M.get(buf)
	if not is_codex_buffer(buf) then
		return nil
	end

	return read_state(buf)
end

function M.set(buf, status)
	if not is_codex_buffer(buf) or not valid_statuses[status] then
		return false
	end

	local value = read_state(buf)
	value.status = status
	write_state(buf, value)
	return true
end

function M.finish(buf)
	if not is_codex_buffer(buf) then
		return false
	end

	local value = read_state(buf)
	value.status = "idle"
	value.needs_attention = not is_focused(buf)
	write_state(buf, value)
	return true
end

function M.mark_seen(buf)
	if not is_codex_buffer(buf) or not is_focused(buf) then
		return false
	end

	local value = read_state(buf)
	if not value.needs_attention then
		return true
	end

	value.needs_attention = false
	write_state(buf, value)
	return true
end

function M.bind(buf, instance)
	if not is_codex_buffer(buf) or not valid_identifier(instance) then
		return false
	end

	vim.b[buf].codex_status_instance = instance
	vim.b[buf].codex_status_events = {
		last_monotonic_ns = 0,
		terminal_turns = {},
	}
	vim.b[buf].codex_status = {
		status = "idle",
		needs_attention = false,
	}
	refresh_title()
	return true
end

function M.receive(message)
	if type(message) ~= "table"
		or message.schema_version ~= 1
		or not valid_integer(message.buffer)
		or message.buffer <= 0
		or not valid_identifier(message.instance)
		or not valid_identifier(message.turn_id)
		or not valid_integer(message.monotonic_ns)
	then
		return false
	end

	if message.session_id ~= nil and not valid_identifier(message.session_id) then
		return false
	end

	local expected_state = event_states[message.source_event]
	if expected_state == nil or message.state ~= expected_state then
		return false
	end

	local buf = message.buffer
	if not is_codex_buffer(buf)
		or vim.b[buf].codex_status_instance ~= message.instance
	then
		return false
	end

	local events = read_event_state(buf)
	if terminal_turn_seen(events, message.turn_id) then
		return false
	end

	if terminal_events[message.source_event] then
		remember_terminal_turn(events, message.turn_id)

		if events.active_turn_id
			and events.active_turn_id ~= message.turn_id
		then
			write_event_state(buf, events)
			return false
		end

		if not events.active_turn_id
			and message.monotonic_ns < events.last_monotonic_ns
		then
			write_event_state(buf, events)
			return false
		end

		events.active_turn_id = nil
		events.last_monotonic_ns = math.max(
			events.last_monotonic_ns,
			message.monotonic_ns
		)
		write_event_state(buf, events)

		if message.source_event == "Stop" then
			return M.finish(buf)
		end

		return M.set(buf, "idle")
	end

	if message.monotonic_ns < events.last_monotonic_ns then
		return false
	end

	if events.active_turn_id
		and events.active_turn_id ~= message.turn_id
		and message.source_event ~= "UserPromptSubmit"
	then
		return false
	end

	events.active_turn_id = message.turn_id
	events.last_monotonic_ns = message.monotonic_ns
	write_event_state(buf, events)
	return M.set(buf, message.state)
end

function M.title(buffers, current_buf)
	local result = {
		{ " ", "FloatTitle" },
	}
	local dictation = rawget(vim, "__voice_dictation_state")
	if type(dictation) == "table"
		and (dictation.phase == "recording" or dictation.phase == "transcribing")
	then
		local highlight = dictation.phase == "recording"
			and "CodexDictationRecording"
			or "CodexDictationTranscribing"
		table.insert(result, {
			dictation.blink_visible and "■" or " ",
			highlight,
		})
		table.insert(result, { " ", "FloatTitle" })
	end

	for index, buf in ipairs(buffers) do
		local value = read_state(buf)
		local text = tostring(index)
		if value.needs_attention then
			text = text .. "!"
		end
		local current = buf == current_buf
		if current then
			text = "[" .. text .. "]"
		end

		if index > 1 then
			table.insert(result, { " ", "FloatTitle" })
		end

		table.insert(result, {
			text,
			highlight_name(value.status, current),
		})
	end

	table.insert(result, { " ", "FloatTitle" })
	return result
end

return M

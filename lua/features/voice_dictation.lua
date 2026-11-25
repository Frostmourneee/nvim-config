local M = {}

local client_prefix = {
	"/home/frostmourneee/Progs/Experiments/whisper-local-ASR/.venv/bin/python",
	"-m",
	"whisper_local_asr.client",
}

local state_key = "__voice_dictation_state"
local state = rawget(vim, state_key)
if type(state) ~= "table" then
	state = {
		phase = "idle",
		blink_visible = false,
		cycle = 0,
	}
	rawset(vim, state_key, state)
end

local function refresh_title()
	local ok, workspace_layout = pcall(require, "features.workspace_layout")
	if ok then
		workspace_layout.schedule_reflow()
	end
end

local function apply_highlights()
	vim.api.nvim_set_hl(0, "CodexDictationRecording", {
		fg = "#f38ba8",
		bold = true,
	})
	vim.api.nvim_set_hl(0, "CodexDictationTranscribing", {
		fg = "#f9e2af",
		bold = true,
	})
end

local function ensure_timer()
	if state.timer and not state.timer:is_closing() then
		return state.timer
	end

	state.timer = (vim.uv or vim.loop).new_timer()
	return state.timer
end

local function set_phase(phase)
	state.phase = phase
	local timer = ensure_timer()
	timer:stop()

	if phase == "recording" or phase == "transcribing" then
		state.blink_visible = true
		timer:start(450, 450, vim.schedule_wrap(function()
			if state.phase ~= "recording" and state.phase ~= "transcribing" then
				return
			end
			state.blink_visible = not state.blink_visible
			refresh_title()
		end))
	else
		state.blink_visible = false
	end

	refresh_title()
end

local function clear_cycle()
	state.recording_id = nil
	state.target = nil
	set_phase("idle")
end

local function client_command(arguments)
	local command = vim.deepcopy(client_prefix)
	vim.list_extend(command, arguments)
	return command
end

local function decode_result(result)
	if result.code ~= 0 then
		local message = vim.trim(result.stderr or "")
		if message == "" then
			message = "Whisper ASR client failed"
		end
		return nil, message
	end

	local output = vim.trim(result.stdout or "")
	if output == "" then
		return nil, "Whisper ASR daemon returned no response"
	end

	local ok, response = pcall(vim.json.decode, output)
	if not ok or type(response) ~= "table" then
		return nil, "Whisper ASR daemon returned invalid JSON"
	end
	return response
end

local function run_client(arguments, callback)
	vim.system(client_command(arguments), { text = true }, function(result)
		vim.schedule(function()
			local response, err = decode_result(result)
			callback(response, err)
		end)
	end)
end

local function is_codex_buffer(buf)
	return type(buf) == "number"
		and vim.api.nvim_buf_is_valid(buf)
		and vim.b[buf].panel_kind == "codex"
		and type(vim.bo[buf].channel) == "number"
		and vim.bo[buf].channel > 0
end

local function find_target()
	local workspace_layout = require("features.workspace_layout")
	local win = workspace_layout.find_panel_window("codex")
	local buf

	if win and vim.api.nvim_win_is_valid(win) then
		buf = vim.api.nvim_win_get_buf(win)
	else
		buf = workspace_layout.find_group_buffer("codex", nil, true)
	end

	if not is_codex_buffer(buf) then
		return nil
	end

	return {
		buf = buf,
		instance = vim.b[buf].codex_status_instance,
	}
end

local function target_is_valid(target)
	return type(target) == "table"
		and is_codex_buffer(target.buf)
		and vim.b[target.buf].codex_status_instance == target.instance
end

local function sanitize_transcript(text)
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	return text:gsub("%c", function(character)
		if character == "\n" or character == "\t" then
			return character
		end
		return ""
	end)
end

local function prompt_is_empty(buf)
	local win = vim.fn.bufwinid(buf)
	if win == -1 or not vim.api.nvim_win_is_valid(win) then
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(win)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
	if type(line) ~= "string" then
		return false
	end

	-- The terminal cursor sits immediately after Codex's prompt marker when
	-- the composer is empty. Ignore placeholder text rendered after it.
	local before_cursor = vim.trim(line:sub(1, cursor[2]))
	return before_cursor == "›" or before_cursor == "❯" or before_cursor == ">"
end

local function append_transcript(target, text)
	if not target_is_valid(target) then
		vim.notify("Codex buffer closed before transcription completed", vim.log.levels.ERROR)
		return false
	end

	local codex_state = require("features.codex_status").get(target.buf)
	if codex_state and codex_state.status == "waiting" then
		vim.fn.setreg('"', "\n\n" .. text)
		vim.notify(
			"Codex is waiting for permission; transcript copied to the unnamed register",
			vim.log.levels.WARN
		)
		return false
	end

	if not require("features.panels").show_buffer(target.buf) then
		vim.notify("Unable to focus the Codex buffer", vim.log.levels.ERROR)
		return false
	end

	local safe_text = sanitize_transcript(text)
	if safe_text ~= "" then
		local channel = vim.bo[target.buf].channel
		local ok, err = pcall(vim.api.nvim_chan_send, channel, "\5")
		if not ok then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return false
		end

		-- Ctrl-E above moves to the end first. Wait for the terminal redraw so
		-- an empty composer can omit the otherwise unwanted leading paragraph.
		vim.defer_fn(function()
			if not target_is_valid(target) then
				return
			end

			local separator = prompt_is_empty(target.buf) and "" or "\n\n"
			local paste_ok, paste_err = pcall(
				vim.api.nvim_chan_send,
				channel,
				"\27[200~" .. separator .. safe_text .. "\27[201~"
			)
			if not paste_ok then
				vim.notify(tostring(paste_err), vim.log.levels.ERROR)
			end
		end, 20)
	end

	vim.cmd("startinsert")
	return true
end

local function quiet_conflict(response)
	return response
		and response.ok == false
		and (response.state == "recording" or response.state == "transcribing")
end

local function start_recording()
	local target = find_target()
	if not target then
		return
	end

	local codex_state = require("features.codex_status").get(target.buf)
	if codex_state and codex_state.status == "waiting" then
		return
	end

	if not require("features.panels").show_buffer(target.buf) then
		return
	end

	state.cycle = state.cycle + 1
	local cycle = state.cycle
	state.target = target
	set_phase("starting")

	run_client({ "start" }, function(response, err)
		if state.cycle ~= cycle then
			return
		end

		if not response then
			clear_cycle()
			vim.notify(err, vim.log.levels.ERROR)
			return
		end
		if response.ok ~= true
			or response.state ~= "recording"
			or type(response.recording_id) ~= "string"
			or response.recording_id == ""
		then
			clear_cycle()
			if not quiet_conflict(response) then
				vim.notify(response.error or "Unable to start recording", vim.log.levels.ERROR)
			end
			return
		end

		state.recording_id = response.recording_id
		set_phase("recording")
	end)
end

local function stop_recording()
	local recording_id = state.recording_id
	local target = state.target
	if type(recording_id) ~= "string" or recording_id == "" then
		clear_cycle()
		return
	end

	local cycle = state.cycle
	set_phase("transcribing")
	run_client({ "stop", recording_id }, function(response, err)
		if state.cycle ~= cycle then
			return
		end

		clear_cycle()
		if not response then
			vim.notify(err, vim.log.levels.ERROR)
			return
		end
		if response.ok ~= true or type(response.text) ~= "string" then
			vim.notify(response.error or "Transcription failed", vim.log.levels.ERROR)
			return
		end

		append_transcript(target, response.text)
	end)
end

local function toggle()
	if state.phase == "idle" then
		start_recording()
	elseif state.phase == "recording" then
		stop_recording()
	end
end

local function cancel_on_exit()
	if state.phase == "recording"
		and type(state.recording_id) == "string"
		and state.recording_id ~= ""
	then
		local process = vim.system(client_command({ "cancel", state.recording_id }), {
			text = true,
		})
		pcall(function()
			process:wait(1500)
		end)
	end

	if state.timer and not state.timer:is_closing() then
		state.timer:stop()
	end
end

function M.setup()
	apply_highlights()
	local group = vim.api.nvim_create_augroup("VoiceDictation", { clear = true })

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = apply_highlights,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = cancel_on_exit,
	})

	-- Remove the previous binding when reloading an existing Neovim session.
	pcall(vim.keymap.del, "n", "<leader>v")
	vim.keymap.set({ "n", "i", "t" }, "<A-v>", toggle, {
		desc = "Toggle voice dictation for the current Codex prompt",
	})

	if state.phase == "recording" or state.phase == "transcribing" then
		set_phase(state.phase)
	else
		set_phase("idle")
	end
end

return M

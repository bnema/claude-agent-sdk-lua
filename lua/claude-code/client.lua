-- luacheck: globals vim

local args_builder = require("claude-code.util.args")
local errors = require("claude-code.errors")
local options = require("claude-code.options")
local result_parser = require("claude-code.result")
local json_stream = require("claude-code.util.json")

---@class ClaudeClient
---@field bin_path string
---@field default_options table
local ClaudeClient = {}
ClaudeClient.__index = ClaudeClient

---@param bin_path? string
---@param default_options? table
---@return ClaudeClient
local function new(bin_path, default_options)
	return setmetatable({
		bin_path = bin_path or "claude",
		default_options = options.normalize(default_options),
	}, ClaudeClient)
end

---@param prompt string
---@param opts? table
---@return table|nil, ClaudeError|nil
function ClaudeClient:run_prompt(prompt, opts)
	local merged_opts = options.merge(self.default_options, opts or {})
	local err = options.validate(merged_opts)
	if err then
		return nil, err
	end

	local cmd_args = vim.list_extend({ self.bin_path }, args_builder.build(prompt or "", merged_opts))
	local result = vim.system(cmd_args, { text = true, timeout = merged_opts.timeout }):wait()

	if result.code ~= 0 then
		return nil, errors.parse(result.stderr or "", result.code)
	end

	local parsed, parse_err = result_parser.parse(result.stdout or "", merged_opts.format)
	if parse_err then
		return nil, parse_err
	end

	return parsed, nil
end

---@param prompt string
---@param opts? table
---@param callback fun(err: ClaudeError|nil, result: table|nil)
function ClaudeClient:run_prompt_async(prompt, opts, callback)
	local merged_opts = options.merge(self.default_options, opts or {})
	local err = options.validate(merged_opts)
	if err then
		callback(err, nil)
		return
	end

	local cmd_args = vim.list_extend({ self.bin_path }, args_builder.build(prompt or "", merged_opts))
	vim.system(
		cmd_args,
		{ text = true, timeout = merged_opts.timeout },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				callback(errors.parse(result.stderr or "", result.code), nil)
				return
			end

			local parsed, parse_err = result_parser.parse(result.stdout or "", merged_opts.format)
			if parse_err then
				callback(parse_err, nil)
				return
			end

			callback(nil, parsed)
		end)
	)
end

---@param prompt string
---@param opts? table
---@param on_message fun(msg: table)
---@param on_error fun(err: ClaudeError)
---@param on_complete fun()
---@return table|nil
function ClaudeClient:stream_prompt(prompt, opts, on_message, on_error, on_complete)
	local stream_opts = options.merge(self.default_options, opts or {})
	stream_opts.format = "stream-json"
	stream_opts.verbose = true
	stream_opts.include_partial_messages = true

	local err = options.validate(stream_opts)
	if err then
		on_error(err)
		return nil
	end

	local cmd_args = vim.list_extend({ self.bin_path }, args_builder.build(prompt or "", stream_opts))
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local stderr_buf = {}
	local parser = json_stream.new_line_parser(on_message, function(line, decode_err)
		on_error(errors.new_validation_error("Failed to parse JSON message", "stdout", {
			line = line,
			error = decode_err,
		}))
	end)

	local function close_pipe(pipe)
		if pipe and not pipe:is_closing() then
			pipe:close()
		end
	end

	local handle
	handle = vim.loop.spawn(
		self.bin_path,
		{
			args = cmd_args,
			stdio = { nil, stdout, stderr },
		},
		vim.schedule_wrap(function(code)
			close_pipe(stdout)
			close_pipe(stderr)

			-- Flush any buffered line
			parser(nil)

			if code ~= 0 then
				on_error(errors.parse(table.concat(stderr_buf, ""), code))
				return
			end

			on_complete()
		end)
	)

	if not handle then
		on_error(errors.new(errors.ErrorType.command, "failed to start claude process"))
		close_pipe(stdout)
		close_pipe(stderr)
		return nil
	end

	stdout:read_start(function(read_err, chunk)
		if read_err then
			on_error(errors.new(errors.ErrorType.network, "failed to read stream", nil, { error = read_err }))
			return
		end

		if chunk then
			parser(chunk)
		else
			parser(nil)
		end
	end)

	stderr:read_start(function(_, chunk)
		if chunk then
			table.insert(stderr_buf, chunk)
		end
	end)

	return {
		stop = function()
			if handle and not handle:is_closing() then
				handle:kill("sigterm")
			end
		end,
	}
end

---@param stdin string
---@param prompt string
---@param opts? table
---@return table|nil, ClaudeError|nil
function ClaudeClient:run_from_stdin(stdin, prompt, opts)
	local merged_opts = options.merge(self.default_options, opts or {})
	local err = options.validate(merged_opts)
	if err then
		return nil, err
	end

	local cmd_args = vim.list_extend({ self.bin_path }, args_builder.build(prompt or "", merged_opts))
	local result = vim.system(cmd_args, {
		text = true,
		timeout = merged_opts.timeout,
		stdin = stdin,
	}):wait()

	if result.code ~= 0 then
		return nil, errors.parse(result.stderr or "", result.code)
	end

	local parsed, parse_err = result_parser.parse(result.stdout or "", merged_opts.format)
	if parse_err then
		return nil, parse_err
	end

	return parsed, nil
end

---@param prompt string
---@param session_id string
---@param opts? table
---@return table|nil, ClaudeError|nil
function ClaudeClient:resume_conversation(prompt, session_id, opts)
	local merged_opts = options.merge(self.default_options, opts or {})
	merged_opts.format = merged_opts.format or "json"
	merged_opts.resume_id = session_id
	merged_opts.continue = false
	return self:run_prompt(prompt, merged_opts)
end

---@param prompt string
---@param opts? table
---@return table|nil, ClaudeError|nil
function ClaudeClient:continue_conversation(prompt, opts)
	local merged_opts = options.merge(self.default_options, opts or {})
	merged_opts.format = merged_opts.format or "json"
	merged_opts.continue = true
	merged_opts.resume_id = nil
	return self:run_prompt(prompt, merged_opts)
end

return {
	ClaudeClient = ClaudeClient,
	new = new,
}

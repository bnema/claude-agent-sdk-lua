-- luacheck: globals vim

local args_builder = require("claude-code.util.args")
local budget = require("claude-code.budget")
local errors = require("claude-code.errors")
local options = require("claude-code.options")
local result_parser = require("claude-code.result")
local json_stream = require("claude-code.util.json")

local DEFAULT_RETRY_POLICY = {
	max_retries = 3,
	base_delay_ms = 100,
	max_delay_ms = 5000,
	backoff_factor = 2.0,
}

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

local function resolve_budget_tracker(opts)
	if opts.budget_tracker then
		return opts.budget_tracker
	end

	if opts.max_budget_usd and opts.max_budget_usd > 0 then
		return budget.new({ max_budget_usd = opts.max_budget_usd })
	end

	return nil
end

local function apply_budget(tracker, res)
	if not tracker or not res then
		return nil
	end

	local cost = res.total_cost_usd or res.cost_usd
	if not cost or cost <= 0 then
		return nil
	end

	local ok, budget_err = tracker:add_spend(res.session_id or "default", cost)
	if not ok then
		return errors.new(errors.ErrorType.validation, budget_err or "Budget exceeded", nil, {
			max_budget_usd = tracker.config.max_budget_usd,
			current_spend = tracker:total(),
		})
	end

	return nil
end

local function calculate_retry_delay(policy, attempt, err)
	if attempt == 0 then
		return 0
	end

	local delay = policy.base_delay_ms * (policy.backoff_factor ^ (attempt - 1))
	if delay > policy.max_delay_ms then
		delay = policy.max_delay_ms
	end

	local retry_after = errors.retry_delay(err)
	if retry_after and retry_after > 0 then
		delay = math.max(delay, retry_after * 1000)
	end

	return delay
end

local function plugin_error(message)
	return errors.new(errors.ErrorType.validation, message or "plugin error")
end

local function parse_tool_input(raw)
	local input = { raw = raw or {} }
	if type(raw) ~= "table" then
		return input
	end

	if type(raw.command) == "string" then
		input.command = raw.command
	end
	if type(raw.file_path) == "string" then
		input.file_path = raw.file_path
	end
	if type(raw.pattern) == "string" then
		input.pattern = raw.pattern
	end
	if type(raw.content) == "string" then
		input.content = raw.content
	end
	if type(raw.old_string) == "string" then
		input.old_string = raw.old_string
	end
	if type(raw.new_string) == "string" then
		input.new_string = raw.new_string
	end

	return input
end

local function handle_hook_event(plugin_manager, msg)
	if not plugin_manager or not msg then
		return true
	end

	local hook_name = msg.hook_event_name or msg.hookEventName
	if not hook_name then
		return true
	end

	local ctx = msg
	if hook_name == "PreToolUse" then
		return plugin_manager:on_pre_tool_use(msg.tool_name or "", msg.tool_input or {}, ctx)
	elseif hook_name == "PostToolUse" then
		return plugin_manager:on_post_tool_use(msg.tool_name or "", msg.tool_input or {}, msg.tool_response, ctx)
	elseif hook_name == "UserPromptSubmit" then
		return plugin_manager:on_user_prompt_submit(msg.prompt or "", ctx)
	elseif hook_name == "Stop" then
		return plugin_manager:on_stop(ctx)
	elseif hook_name == "SubagentStop" then
		return plugin_manager:on_subagent_stop(ctx)
	elseif hook_name == "PreCompact" then
		return plugin_manager:on_message(msg)
	end

	return true
end

local function handle_permission_update(plugin_manager, msg)
	if not plugin_manager or not msg then
		return true
	end

	if msg.permission_update or msg.permissionUpdate then
		return plugin_manager:on_permission_update(msg.permission_update or msg.permissionUpdate)
	end

	if msg.type == "permission" then
		return plugin_manager:on_permission_update(msg)
	end

	return true
end

local function call_plugin_manager(manager, method, ...)
	if not manager or type(manager[method]) ~= "function" then
		return nil
	end

	local ok, success, err = pcall(manager[method], manager, ...)
	if not ok then
		return plugin_error(success)
	end

	if success == false then
		return plugin_error(err)
	end

	return nil
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

	local tracker = resolve_budget_tracker(merged_opts)
	local budget_err = apply_budget(tracker, parsed)
	if budget_err then
		return nil, budget_err
	end

	local plugin_err = call_plugin_manager(merged_opts.plugin_manager, "on_complete", parsed)
	if plugin_err then
		return nil, plugin_err
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

			local tracker = resolve_budget_tracker(merged_opts)
			local budget_err = apply_budget(tracker, parsed)
			if budget_err then
				callback(budget_err, nil)
				return
			end

			local plugin_err = call_plugin_manager(merged_opts.plugin_manager, "on_complete", parsed)
			if plugin_err then
				callback(plugin_err, nil)
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
	local plugin_manager = stream_opts.plugin_manager
	local tracker = resolve_budget_tracker(stream_opts)
	local last_cost = nil
	local last_session_id = nil
	local last_result_msg = nil
	local aborted = false

	local err = options.validate(stream_opts)
	if err then
		on_error(err)
		return nil
	end

	local cmd_args = vim.list_extend({ self.bin_path }, args_builder.build(prompt or "", stream_opts))
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local stderr_buf = {}
	local handle
	local function handle_plugin_error(message)
		aborted = true
		on_error(plugin_error(message))
		if handle and not handle:is_closing() then
			handle:kill("sigterm")
		end
	end

	local function invoke_plugin(method, ...)
		if not plugin_manager then
			return true
		end
		local ok, success, msg = pcall(plugin_manager[method], plugin_manager, ...)
		if not ok then
			handle_plugin_error(success)
			return false
		end
		if success == false then
			handle_plugin_error(msg or "plugin rejected operation")
			return false
		end
		return true
	end

	local parser = json_stream.new_line_parser(function(msg)
		if aborted then
			return
		end

		if tracker then
			last_cost = msg.total_cost_usd or msg.cost_usd or last_cost
			last_session_id = msg.session_id or last_session_id
		end

		if msg.result or msg.total_cost_usd then
			last_result_msg = msg
		end

		if msg.type == "tool_use" and plugin_manager then
			local input = parse_tool_input(msg.tool_input or msg.message or {})
			input.session_id = msg.session_id
			local ok = invoke_plugin("on_tool_call", msg.tool_name or "", input)
			if not ok then
				return
			end
		end

		if plugin_manager then
			local ok = handle_permission_update(plugin_manager, msg)
			if ok == false then
				return
			end

			ok = handle_hook_event(plugin_manager, msg)
			if ok == false then
				return
			end
		end

		if plugin_manager then
			local ok = invoke_plugin("on_message", msg)
			if not ok then
				return
			end
		end

		on_message(msg)
	end, function(line, decode_err)
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

			if tracker and last_cost then
				local budget_err = apply_budget(tracker, {
					total_cost_usd = last_cost,
					session_id = last_session_id or "",
				})
				if budget_err then
					on_error(budget_err)
					return
				end
			end

			if not aborted and plugin_manager then
				local ok, completed, msg = pcall(plugin_manager.on_complete, plugin_manager, last_result_msg)
				if not ok or completed == false then
					on_error(plugin_error(msg or completed))
					return
				end
			end

			if not aborted then
				on_complete()
			end
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

	local tracker = resolve_budget_tracker(merged_opts)
	local budget_err = apply_budget(tracker, parsed)
	if budget_err then
		return nil, budget_err
	end

	local plugin_err = call_plugin_manager(merged_opts.plugin_manager, "on_complete", parsed)
	if plugin_err then
		return nil, plugin_err
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

---@param prompt string
---@param opts? table
---@param retry_policy? table
---@return table|nil, ClaudeError|nil
function ClaudeClient:run_with_retry(prompt, opts, retry_policy)
	local policy = vim.tbl_extend("force", DEFAULT_RETRY_POLICY, retry_policy or {})
	local last_err = nil

	for attempt = 0, policy.max_retries do
		local res, err = self:run_prompt(prompt, opts)
		if not err then
			return res, nil
		end

		last_err = err
		if not errors.is_retryable(err) then
			return nil, err
		end

		if attempt >= policy.max_retries then
			break
		end

		local delay_ms = calculate_retry_delay(policy, attempt + 1, err)
		if delay_ms > 0 then
			vim.wait(delay_ms, function()
				return false
			end)
		end
	end

	return nil, last_err
end

return {
	ClaudeClient = ClaudeClient,
	new = new,
}

-- luacheck: globals vim

local M = {}

---@param prompt string
---@param opts table
---@return string[]
function M.build(prompt, opts)
	opts = opts or {}
	local args = { "-p" }

	if prompt and prompt ~= "" then
		table.insert(args, prompt)
	end

	if opts.format and opts.format ~= "" then
		vim.list_extend(args, { "--output-format", opts.format })
	end

	if opts.system_prompt and opts.system_prompt ~= "" then
		vim.list_extend(args, { "--system-prompt", opts.system_prompt })
	end

	if opts.append_prompt and opts.append_prompt ~= "" then
		vim.list_extend(args, { "--append-system-prompt", opts.append_prompt })
	end

	local mcp_config = opts.mcp_config or opts.mcp_config_path
	if mcp_config and mcp_config ~= "" then
		if type(mcp_config) == "table" then
			vim.list_extend(args, { "--mcp-config", vim.json.encode(mcp_config) })
		else
			vim.list_extend(args, { "--mcp-config", mcp_config })
		end
	end

	if opts.allowed_tools and #opts.allowed_tools > 0 then
		vim.list_extend(args, { "--allowedTools", table.concat(opts.allowed_tools, ",") })
	end

	if opts.disallowed_tools and #opts.disallowed_tools > 0 then
		vim.list_extend(args, { "--disallowedTools", table.concat(opts.disallowed_tools, ",") })
	end

	if opts.permission_tool and opts.permission_tool ~= "" then
		vim.list_extend(args, { "--permission-prompt-tool", opts.permission_tool })
	end

	if opts.permission_mode and opts.permission_mode ~= "" then
		vim.list_extend(args, { "--permission-mode", opts.permission_mode })
	end

	if opts.session_id and opts.session_id ~= "" then
		vim.list_extend(args, { "--session-id", opts.session_id })
	end

	if opts.fork_session then
		table.insert(args, "--fork-session")
	end

	if opts.resume_id and opts.resume_id ~= "" then
		vim.list_extend(args, { "--resume", opts.resume_id })
	elseif opts.continue then
		table.insert(args, "--continue")
	end

	if opts.max_turns and opts.max_turns > 0 then
		vim.list_extend(args, { "--max-turns", tostring(opts.max_turns) })
	end

	if opts.verbose then
		table.insert(args, "--verbose")
	end

	if opts.model_alias and opts.model_alias ~= "" then
		vim.list_extend(args, { "--model", opts.model_alias })
	elseif opts.model and opts.model ~= "" then
		vim.list_extend(args, { "--model", opts.model })
	end

	if opts.fallback_model and opts.fallback_model ~= "" then
		vim.list_extend(args, { "--fallback-model", opts.fallback_model })
	end

	if opts.betas and #opts.betas > 0 then
		vim.list_extend(args, { "--betas", table.concat(opts.betas, ",") })
	end

	if opts.config_file and opts.config_file ~= "" then
		vim.list_extend(args, { "--config", opts.config_file })
	end

	if opts.settings then
		local value = opts.settings
		if type(value) == "table" then
			value = vim.json.encode(value)
		end
		vim.list_extend(args, { "--settings", value })
	end

	if opts.add_dirs and #opts.add_dirs > 0 then
		for _, dir in ipairs(opts.add_dirs) do
			vim.list_extend(args, { "--add-dir", dir })
		end
	end

	if opts.setting_sources and #opts.setting_sources > 0 then
		vim.list_extend(args, { "--setting-sources", table.concat(opts.setting_sources, ",") })
	end

	if opts.plugins and #opts.plugins > 0 then
		for _, plugin_dir in ipairs(opts.plugins) do
			vim.list_extend(args, { "--plugin-dir", plugin_dir })
		end
	end

	if opts.agents and next(opts.agents) ~= nil then
		vim.list_extend(args, { "--agents", vim.json.encode(opts.agents) })
	end

	if opts.max_thinking_tokens then
		vim.list_extend(args, { "--max-thinking-tokens", tostring(opts.max_thinking_tokens) })
	end

	if opts.help then
		table.insert(args, "--help")
	end

	if opts.version then
		table.insert(args, "--version")
	end

	if opts.disable_autoupdate then
		table.insert(args, "--disable-autoupdate")
	end

	if opts.theme and opts.theme ~= "" then
		vim.list_extend(args, { "--theme", opts.theme })
	end

	if opts.include_partial_messages then
		table.insert(args, "--include-partial-messages")
	end

	return args
end

return M

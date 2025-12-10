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

	if opts.mcp_config_path and opts.mcp_config_path ~= "" then
		vim.list_extend(args, { "--mcp-config", opts.mcp_config_path })
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

	if opts.config_file and opts.config_file ~= "" then
		vim.list_extend(args, { "--config", opts.config_file })
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

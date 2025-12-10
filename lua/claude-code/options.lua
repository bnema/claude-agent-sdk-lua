-- luacheck: globals vim

local errors = require("claude-code.errors")

local M = {}

local DEFAULT_OPTIONS = {
	format = "text",
	permission_mode = "default",
	setting_sources = nil,
}

local VALID_MODEL_ALIASES = {
	sonnet = true,
	opus = true,
	haiku = true,
}

local VALID_PERMISSION_MODES = {
	["default"] = true,
	acceptEdits = true,
	bypassPermissions = true,
}

local VALID_SETTING_SOURCES = {
	userSettings = true,
	projectSettings = true,
	localSettings = true,
	session = true,
}

local function validate_mcp_tool_name(tool)
	return tool:sub(1, 5) == "mcp__" and select(2, tool:gsub("__", "")) >= 2
end

local function validate_string_list(values, field)
	if values == nil then
		return nil
	end

	if type(values) ~= "table" then
		return errors.new_validation_error("Value must be an array of strings", field, values)
	end

	for _, value in ipairs(values) do
		if type(value) ~= "string" then
			return errors.new_validation_error("Value must be a string", field, value)
		end
	end

	return nil
end

local function validate_tool_list(tools, field)
	if tools == nil then
		return nil
	end

	if type(tools) ~= "table" then
		return errors.new_validation_error("Tool list must be an array of strings", field, tools)
	end

	for _, tool in ipairs(tools) do
		if type(tool) ~= "string" then
			return errors.new_validation_error("Tool entry must be a string", field, tool)
		end
		if tool:sub(1, 5) == "mcp__" and not validate_mcp_tool_name(tool) then
			return errors.new_validation_error("Invalid MCP tool name (mcp__<serverName>__<toolName>)", field, tool)
		end
	end

	return nil
end

---@param opts? table
---@return table
function M.normalize(opts)
	if opts == nil then
		return vim.deepcopy(DEFAULT_OPTIONS)
	end

	local normalized = vim.deepcopy(DEFAULT_OPTIONS)
	for key, value in pairs(opts) do
		normalized[key] = value
	end

	return normalized
end

---@param base table
---@param overrides? table
---@return table
function M.merge(base, overrides)
	local merged = M.normalize(base)
	if overrides then
		for key, value in pairs(overrides) do
			merged[key] = value
		end
	end
	return merged
end

---@param opts table
---@return ClaudeError|nil
function M.validate(opts)
	if opts.model_alias and opts.model_alias ~= "" and not VALID_MODEL_ALIASES[opts.model_alias] then
		return errors.new_validation_error("Invalid model alias", "model_alias", opts.model_alias)
	end

	if opts.permission_mode and not VALID_PERMISSION_MODES[opts.permission_mode] then
		return errors.new_validation_error("Invalid permission mode", "permission_mode", opts.permission_mode)
	end

	if opts.permission_callback and type(opts.permission_callback) ~= "function" then
		return errors.new_validation_error(
			"Permission callback must be a function",
			"permission_callback",
			opts.permission_callback
		)
	end

	if opts.timeout and opts.timeout < 0 then
		return errors.new_validation_error("Timeout cannot be negative", "timeout", opts.timeout)
	end

	if opts.max_budget_usd and opts.max_budget_usd < 0 then
		return errors.new_validation_error("Max budget cannot be negative", "max_budget_usd", opts.max_budget_usd)
	end

	if opts.budget_tracker and type(opts.budget_tracker) ~= "table" then
		return errors.new_validation_error("Budget tracker must be a table", "budget_tracker", opts.budget_tracker)
	end

	if opts.plugin_manager and type(opts.plugin_manager) ~= "table" then
		return errors.new_validation_error("Plugin manager must be a table", "plugin_manager", opts.plugin_manager)
	end

	if opts.session_id and type(opts.session_id) ~= "string" then
		return errors.new_validation_error("Session ID must be a string", "session_id", opts.session_id)
	end

	if opts.fallback_model and type(opts.fallback_model) ~= "string" then
		return errors.new_validation_error("Fallback model must be a string", "fallback_model", opts.fallback_model)
	end

	local err = validate_string_list(opts.betas, "betas")
	if err then
		return err
	end

	if opts.max_thinking_tokens and opts.max_thinking_tokens < 0 then
		return errors.new_validation_error(
			"Max thinking tokens cannot be negative",
			"max_thinking_tokens",
			opts.max_thinking_tokens
		)
	end

	if opts.settings and type(opts.settings) ~= "string" and type(opts.settings) ~= "table" then
		return errors.new_validation_error("Settings must be a string path or table", "settings", opts.settings)
	end

	if opts.add_dirs then
		err = validate_string_list(opts.add_dirs, "add_dirs")
		if err then
			return err
		end
	end

	if opts.setting_sources then
		err = validate_string_list(opts.setting_sources, "setting_sources")
		if err then
			return err
		end
		for _, source in ipairs(opts.setting_sources) do
			if not VALID_SETTING_SOURCES[source] then
				return errors.new_validation_error("Invalid setting source", "setting_sources", source)
			end
		end
	end

	if opts.plugins then
		err = validate_string_list(opts.plugins, "plugins")
		if err then
			return err
		end
	end

	if opts.agents and type(opts.agents) ~= "table" then
		return errors.new_validation_error("Agents must be a table of agent definitions", "agents", opts.agents)
	end

	if opts.mcp_config and type(opts.mcp_config) ~= "string" and type(opts.mcp_config) ~= "table" then
		return errors.new_validation_error("MCP config must be a path or table", "mcp_config", opts.mcp_config)
	end

	if opts.resume_id and opts.resume_id ~= "" then
		local trimmed = opts.resume_id:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed == "" then
			return errors.new_validation_error("Resume ID cannot be empty", "resume_id", opts.resume_id)
		end
	end

	err = validate_tool_list(opts.allowed_tools, "allowed_tools")
	if err then
		return err
	end

	err = validate_tool_list(opts.disallowed_tools, "disallowed_tools")
	if err then
		return err
	end

	return nil
end

return M

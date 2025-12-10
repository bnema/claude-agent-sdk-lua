-- luacheck: globals vim

local errors = require("claude-code.errors")

local M = {}

local DEFAULT_OPTIONS = {
	format = "text",
}

local VALID_MODEL_ALIASES = {
	sonnet = true,
	opus = true,
	haiku = true,
}

local function validate_mcp_tool_name(tool)
	return tool:sub(1, 5) == "mcp__" and select(2, tool:gsub("__", "")) >= 2
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

	if opts.timeout and opts.timeout < 0 then
		return errors.new_validation_error("Timeout cannot be negative", "timeout", opts.timeout)
	end

	if opts.resume_id and opts.resume_id ~= "" then
		local trimmed = opts.resume_id:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed == "" then
			return errors.new_validation_error("Resume ID cannot be empty", "resume_id", opts.resume_id)
		end
	end

	local err = validate_tool_list(opts.allowed_tools, "allowed_tools")
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

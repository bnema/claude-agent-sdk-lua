-- luacheck: globals vim

local errors = require("claude-code.errors")

local M = {}

---@class ClaudeResult
---@field type? string
---@field subtype? string
---@field result? string
---@field total_cost_usd? number
---@field duration_ms? integer
---@field duration_api_ms? integer
---@field is_error? boolean
---@field num_turns? integer
---@field session_id? string

---@class Message
---@field type string
---@field subtype? string
---@field message? table
---@field session_id? string

---@param stdout string
---@param format string
---@return ClaudeResult|nil, ClaudeError|nil
function M.parse(stdout, format)
	format = format or "text"

	if format == "json" then
		local ok, decoded = pcall(vim.json.decode, stdout or "")
		if not ok or type(decoded) ~= "table" then
			return nil,
				errors.new(errors.ErrorType.validation, "failed to parse JSON response", nil, {
					stdout = stdout,
				})
		end
		return decoded, nil
	end

	return {
		result = stdout or "",
		is_error = false,
	}, nil
end

return M

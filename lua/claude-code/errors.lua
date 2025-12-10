-- luacheck: globals vim

local M = {}

local ERROR_TYPES = {
	unknown = "unknown",
	authentication = "authentication",
	rate_limit = "rate_limit",
	permission = "permission",
	command = "command",
	network = "network",
	mcp = "mcp",
	validation = "validation",
	timeout = "timeout",
	session = "session",
}

local function contains_any(haystack, needles)
	for _, needle in ipairs(needles) do
		if haystack:find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function is_mcp_connection_error(message)
	local lower_msg = message:lower()
	local connection_keywords = {
		"connection",
		"connect",
		"timeout",
		"refused",
		"unreachable",
		"network",
		"socket",
		"pipe",
		"broken pipe",
	}

	for _, keyword in ipairs(connection_keywords) do
		if lower_msg:find(keyword, 1, true) then
			return true
		end
	end

	local config_keywords = {
		"configuration",
		"config",
		"invalid",
		"not found",
		"permission",
		"authentication",
		"unauthorized",
		"forbidden",
	}

	for _, keyword in ipairs(config_keywords) do
		if lower_msg:find(keyword, 1, true) then
			return false
		end
	end

	return true
end

---@class ClaudeError
---@field type string
---@field message string
---@field code? integer
---@field details? table
---@field original? any

---@param err_type string
---@param message string
---@param code? integer
---@param details? table
---@param original? any
---@return ClaudeError
function M.new(err_type, message, code, details, original)
	return {
		type = err_type or ERROR_TYPES.unknown,
		message = message or "",
		code = code,
		details = details or {},
		original = original,
	}
end

---@param message string
---@param field string
---@param value any
---@return ClaudeError
function M.new_validation_error(message, field, value)
	return M.new(ERROR_TYPES.validation, message, nil, {
		field = field,
		value = value,
	})
end

---@param err ClaudeError
---@return boolean
function M.is_retryable(err)
	if not err or type(err) ~= "table" then
		return false
	end

	if err.type == ERROR_TYPES.rate_limit or err.type == ERROR_TYPES.network or err.type == ERROR_TYPES.timeout then
		return true
	end

	if err.type == ERROR_TYPES.mcp then
		return is_mcp_connection_error(err.message or "")
	end

	return false
end

---@param err ClaudeError
---@return integer
function M.retry_delay(err)
	if not err then
		return 0
	end

	if err.type == ERROR_TYPES.rate_limit then
		local retry_after = err.details and err.details.retry_after
		if type(retry_after) == "number" and retry_after > 0 then
			return retry_after
		end
		return 60
	end

	if err.type == ERROR_TYPES.network or err.type == ERROR_TYPES.timeout then
		return 5
	end

	if err.type == ERROR_TYPES.mcp and is_mcp_connection_error(err.message or "") then
		return 3
	end

	return 0
end

---@param stderr string
---@param exit_code integer
---@return ClaudeError
function M.parse(stderr, exit_code)
	stderr = (stderr or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local lower_stderr = stderr:lower()

	if
		contains_any(lower_stderr, {
			"authentication",
			"api key",
			"unauthorized",
			"401",
			"forbidden",
			"403",
			"invalid api key",
			"missing api key",
			"anthropic_api_key",
		})
	then
		return M.new(ERROR_TYPES.authentication, "Authentication failed - check ANTHROPIC_API_KEY", exit_code, {
			suggestion = "Verify your API key is valid and has necessary permissions",
			stderr = stderr,
		})
	end

	if
		contains_any(lower_stderr, {
			"rate limit",
			"too many requests",
			"429",
			"quota exceeded",
			"request limit",
			"usage limit",
		})
	then
		local retry_after = lower_stderr:match("retry%-after: ?(%d+)") or lower_stderr:match("retry after (%d+)")
		local retry_num = retry_after and tonumber(retry_after) or nil
		local details = {
			suggestion = "Wait before retrying or reduce request frequency",
			stderr = stderr,
		}
		if retry_num and retry_num > 0 then
			details.retry_after = retry_num
		end
		return M.new(ERROR_TYPES.rate_limit, "Rate limit exceeded - please wait before retrying", exit_code, details)
	end

	if
		contains_any(lower_stderr, {
			"permission denied",
			"not allowed",
			"tool not permitted",
			"access denied",
			"insufficient permissions",
			"unauthorized tool",
		})
	then
		local message = "Tool usage not permitted - check allowed/disallowed tools configuration"
		return M.new(ERROR_TYPES.permission, message, exit_code, {
			suggestion = "Update --allowedTools or permissions settings",
			stderr = stderr,
		})
	end

	if
		contains_any(lower_stderr, {
			"mcp",
			"model context protocol",
			"mcp server",
			"mcp tool",
			"mcp config",
			"server error",
			"protocol error",
		})
	then
		local suggestion = "Check MCP server configuration and ensure servers are running"
		if
			contains_any(lower_stderr, {
				"connection",
				"connect",
				"unreachable",
				"timeout",
				"refused",
			})
		then
			suggestion = "MCP server connection failed - ensure server is running and accessible"
		elseif
			contains_any(lower_stderr, {
				"config",
				"configuration",
				"invalid",
				"not found",
				"parse",
			})
		then
			suggestion = "MCP configuration error - check your MCP config file"
		end

		return M.new(ERROR_TYPES.mcp, "MCP server error", exit_code, {
			suggestion = suggestion,
			stderr = stderr,
		})
	end

	if
		contains_any(lower_stderr, {
			"network",
			"connection",
			"timeout",
			"dns",
			"unreachable",
			"connection refused",
			"connection reset",
			"socket",
			"no internet",
		})
	then
		return M.new(ERROR_TYPES.network, "Network connectivity issue", exit_code, {
			suggestion = "Check internet connection and try again",
			stderr = stderr,
		})
	end

	if contains_any(lower_stderr, {
		"timeout",
		"timed out",
		"deadline exceeded",
		"context deadline",
	}) then
		return M.new(ERROR_TYPES.timeout, "Operation timed out", exit_code, {
			suggestion = "Increase timeout or try a simpler operation",
			stderr = stderr,
		})
	end

	if
		contains_any(lower_stderr, {
			"session",
			"session not found",
			"invalid session",
			"session expired",
			"resume",
			"conversation not found",
		})
	then
		return M.new(ERROR_TYPES.session, "Session management error", exit_code, {
			suggestion = "Check session ID or start a new conversation",
			stderr = stderr,
		})
	end

	if
		contains_any(lower_stderr, {
			"invalid",
			"validation",
			"malformed",
			"bad request",
			"400",
			"invalid argument",
			"invalid option",
			"invalid flag",
		})
	then
		return M.new(ERROR_TYPES.validation, "Input validation failed", exit_code, {
			suggestion = "Check command arguments and options",
			stderr = stderr,
		})
	end

	local message = "Command execution failed"
	if stderr ~= "" then
		local first_line = stderr:match("([^\n]+)")
		if first_line and first_line:match("%S") then
			message = vim.trim(first_line)
		end
	end

	return M.new(ERROR_TYPES.command, message, exit_code, { stderr = stderr })
end

M.ErrorType = ERROR_TYPES

return M

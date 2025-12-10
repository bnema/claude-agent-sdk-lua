-- luacheck: globals vim

local M = {}

M.Behavior = {
	ALLOW = "allow",
	DENY = "deny",
	ASK = "ask",
}

---@class PermissionResult
---@field behavior string
---@field message? string

---@class ToolInput
---@field command? string
---@field file_path? string
---@field pattern? string
---@field content? string
---@field old_string? string
---@field new_string? string
---@field raw? table

---@return PermissionResult
function M.allow()
	return { behavior = M.Behavior.ALLOW }
end

---@param message? string
---@return PermissionResult
function M.deny(message)
	return { behavior = M.Behavior.DENY, message = message }
end

---@param message? string
---@return PermissionResult
function M.ask(message)
	return { behavior = M.Behavior.ASK, message = message }
end

---@return fun(tool: string, input: ToolInput): PermissionResult
function M.read_only_callback()
	local read_only_tools = {
		Read = true,
		Grep = true,
		Glob = true,
	}
	return function(tool)
		if read_only_tools[tool] then
			return M.allow()
		end
		return M.deny("Only read-only operations are allowed")
	end
end

---@param blocked_patterns? string[]
---@return fun(tool: string, input: ToolInput): PermissionResult
function M.safe_bash_callback(blocked_patterns)
	blocked_patterns = blocked_patterns
		or {
			"rm -rf",
			"rm -r",
			"> /dev/",
			"dd if=",
			"mkfs",
			":(){:|:&};:",
			"chmod -R 777",
			"curl | sh",
			"wget | sh",
		}

	return function(tool, input)
		if tool ~= "Bash" then
			return M.allow()
		end

		local command = input and input.command or ""
		for _, pattern in ipairs(blocked_patterns) do
			if command:find(pattern, 1, true) then
				return M.deny(("Blocked dangerous command pattern: %s"):format(pattern))
			end
		end

		return M.allow()
	end
end

---@param allowed_paths string[]
---@param denied_paths? string[]
---@return fun(tool: string, input: ToolInput): PermissionResult
function M.file_path_callback(allowed_paths, denied_paths)
	denied_paths = denied_paths or {}

	return function(tool, input)
		local file_tools = {
			Read = true,
			Write = true,
			Edit = true,
		}
		if not file_tools[tool] then
			return M.allow()
		end

		local file_path = input and input.file_path or ""
		if file_path == "" then
			return M.allow()
		end

		for _, denied in ipairs(denied_paths) do
			if file_path:sub(1, #denied) == denied then
				return M.deny(("Access to path %s is denied"):format(denied))
			end
		end

		if allowed_paths and #allowed_paths > 0 then
			for _, allowed in ipairs(allowed_paths) do
				if file_path:sub(1, #allowed) == allowed then
					return M.allow()
				end
			end
			return M.deny(("File path %s is not in allowed paths"):format(file_path))
		end

		return M.allow()
	end
end

---@param ... fun(tool: string, input: ToolInput): PermissionResult|nil
---@return fun(tool: string, input: ToolInput): PermissionResult
function M.chain_callbacks(...)
	local callbacks = { ... }
	return function(tool, input)
		for _, cb in ipairs(callbacks) do
			if cb then
				local result = cb(tool, input)
				if result and result.behavior ~= M.Behavior.ALLOW then
					return result
				end
			end
		end
		return M.allow()
	end
end

return M

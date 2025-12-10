local BasePlugin = require("claude-code.plugins.base")

local ToolFilterPlugin = {}
ToolFilterPlugin.__index = ToolFilterPlugin
setmetatable(ToolFilterPlugin, { __index = BasePlugin })

---@param blocked_tools? table<string, string>
---@return ToolFilterPlugin
function ToolFilterPlugin.new(blocked_tools)
	local self = BasePlugin.new("tool-filter", "1.0.0")
	self.blocked_tools = blocked_tools or {}
	return setmetatable(self, ToolFilterPlugin)
end

function ToolFilterPlugin:on_tool_call(tool_name, _)
	local reason = self.blocked_tools[tool_name]
	if reason then
		return false, reason ~= "" and reason or "tool is blocked"
	end
	return true
end

function ToolFilterPlugin:block(tool_name, reason)
	self.blocked_tools[tool_name] = reason or "blocked"
end

function ToolFilterPlugin:unblock(tool_name)
	self.blocked_tools[tool_name] = nil
end

return ToolFilterPlugin

-- luacheck: globals vim

local BasePlugin = require("claude-code.plugins.base")

local LoggingPlugin = {}
LoggingPlugin.__index = LoggingPlugin
setmetatable(LoggingPlugin, { __index = BasePlugin })

---@param logger? fun(message: string)
---@return LoggingPlugin
function LoggingPlugin.new(logger)
	local self = BasePlugin.new("logging", "1.0.0")
	self.logger = logger or function(msg)
		print(msg)
	end
	self.log_tools = true
	self.log_messages = true
	self.log_result = true
	return setmetatable(self, LoggingPlugin)
end

function LoggingPlugin:on_tool_call(tool_name, input)
	if self.log_tools and self.logger then
		self.logger(("[logging] tool call: %s %s"):format(tool_name, vim.inspect(input or {})))
	end
	return true
end

function LoggingPlugin:on_message(msg)
	if self.log_messages and self.logger then
		self.logger(("[logging] message: %s/%s"):format(msg.type or "unknown", msg.subtype or ""))
	end
	return true
end

function LoggingPlugin:on_complete(res)
	if self.log_result and self.logger then
		local cost = res and res.total_cost_usd or 0
		local turns = res and res.num_turns or 0
		self.logger(("[logging] complete: cost=$%.4f turns=%s"):format(cost, tostring(turns)))
	end
	return true
end

return LoggingPlugin

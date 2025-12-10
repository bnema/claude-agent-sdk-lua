local BasePlugin = require("claude-code.plugins.base")

local MetricsPlugin = {}
MetricsPlugin.__index = MetricsPlugin
setmetatable(MetricsPlugin, { __index = BasePlugin })

---@return MetricsPlugin
function MetricsPlugin.new()
	local self = BasePlugin.new("metrics", "1.0.0")
	self.tool_calls = {}
	self.message_count = 0
	self.total_cost = 0
	self.execution_count = 0
	return setmetatable(self, MetricsPlugin)
end

function MetricsPlugin:on_tool_call(tool_name, _)
	self.tool_calls[tool_name] = (self.tool_calls[tool_name] or 0) + 1
	return true
end

function MetricsPlugin:on_message(_)
	self.message_count = self.message_count + 1
	return true
end

function MetricsPlugin:on_complete(res)
	if res then
		self.total_cost = self.total_cost + (res.total_cost_usd or 0)
	end
	self.execution_count = self.execution_count + 1
	return true
end

function MetricsPlugin:get()
	local counts = {}
	for k, v in pairs(self.tool_calls) do
		counts[k] = v
	end

	return {
		tool_calls = counts,
		message_count = self.message_count,
		total_cost = self.total_cost,
		execution_count = self.execution_count,
	}
end

function MetricsPlugin:reset()
	self.tool_calls = {}
	self.message_count = 0
	self.total_cost = 0
	self.execution_count = 0
end

return MetricsPlugin

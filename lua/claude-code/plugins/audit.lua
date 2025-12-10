-- luacheck: globals vim

local BasePlugin = require("claude-code.plugins.base")

local AuditPlugin = {}
AuditPlugin.__index = AuditPlugin
setmetatable(AuditPlugin, { __index = BasePlugin })

local function now_ms()
	return math.floor(vim.loop.now())
end

---@param max_size? integer
---@return AuditPlugin
function AuditPlugin.new(max_size)
	local self = BasePlugin.new("audit", "1.0.0")
	self.records = {}
	self.max_size = max_size or 0
	return setmetatable(self, AuditPlugin)
end

function AuditPlugin:on_tool_call(tool_name, input)
	local record = {
		timestamp = now_ms(),
		tool_name = tool_name,
		input = input and input.raw or {},
		session_id = input and input.session_id or nil,
	}

	table.insert(self.records, record)

	if self.max_size > 0 and #self.records > self.max_size then
		self.records = { table.unpack(self.records, #self.records - self.max_size + 1) }
	end

	return true
end

function AuditPlugin:get_records()
	local copy = {}
	for i, record in ipairs(self.records) do
		copy[i] = record
	end
	return copy
end

function AuditPlugin:clear()
	self.records = {}
end

return AuditPlugin

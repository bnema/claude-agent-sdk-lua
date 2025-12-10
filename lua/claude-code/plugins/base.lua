local BasePlugin = {}
BasePlugin.__index = BasePlugin

---@param name string
---@param version? string
function BasePlugin.new(name, version)
	return setmetatable({
		_name = name or "",
		_version = version or "0.0.0",
	}, BasePlugin)
end

function BasePlugin:name()
	return self._name
end

function BasePlugin:version()
	return self._version
end

function BasePlugin:configure(cfg)
	self.config = cfg
	return true
end

function BasePlugin:initialize()
	local _ = self
	return true
end

function BasePlugin:on_tool_call(_, _)
	local _ = self
	return true
end

function BasePlugin:on_pre_tool_use(_, _, _)
	local _ = self
	return true
end

function BasePlugin:on_post_tool_use(_, _, _, _)
	local _ = self
	return true
end

function BasePlugin:on_user_prompt_submit(_, _)
	local _ = self
	return true
end

function BasePlugin:on_stop(_)
	local _ = self
	return true
end

function BasePlugin:on_subagent_stop(_)
	local _ = self
	return true
end

function BasePlugin:on_permission_update(_)
	local _ = self
	return true
end

function BasePlugin:on_message(_)
	local _ = self
	return true
end

function BasePlugin:on_complete(_)
	local _ = self
	return true
end

function BasePlugin:shutdown()
	local _ = self
	return true
end

return BasePlugin

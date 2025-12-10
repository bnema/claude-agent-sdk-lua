local PluginManager = {}
PluginManager.__index = PluginManager

local function normalize_config(config)
	config = config or {}
	return {
		enabled = config.enabled ~= false,
		priority = config.priority or 100,
		config = config.config,
	}
end

local function call_plugin(entry, method, ...)
	local plugin = entry.plugin
	local fn = plugin[method]
	if not fn then
		return true, nil
	end

	local ok, res, err = pcall(fn, plugin, ...)
	if not ok then
		return false, ("plugin '%s' %s failed: %s"):format(plugin:name() or "unknown", method, res)
	end

	if res == false then
		return false, err or ("plugin '%s' %s returned false"):format(plugin:name() or "unknown", method)
	end

	return true, nil
end

---@return PluginManager
function PluginManager.new()
	return setmetatable({
		plugins = {},
		initialized = false,
	}, PluginManager)
end

---@return boolean, string|nil
function PluginManager:register(plugin, config)
	if plugin == nil then
		return false, "plugin cannot be nil"
	end

	if type(plugin.name) ~= "function" then
		return false, "plugin must implement :name()"
	end

	local name = plugin:name()
	if not name or name == "" then
		return false, "plugin name cannot be empty"
	end

	for _, entry in ipairs(self.plugins) do
		if entry.plugin:name() == name then
			return false, ("plugin '%s' already registered"):format(name)
		end
	end

	local normalized = normalize_config(config)
	local entry = {
		plugin = plugin,
		config = normalized,
		priority = normalized.priority,
	}

	local inserted = false
	for i, existing in ipairs(self.plugins) do
		if entry.priority < existing.priority then
			table.insert(self.plugins, i, entry)
			inserted = true
			break
		end
	end

	if not inserted then
		table.insert(self.plugins, entry)
	end

	return true, nil
end

---@return boolean
function PluginManager:unregister(name)
	for i, entry in ipairs(self.plugins) do
		if entry.plugin:name() == name then
			table.remove(self.plugins, i)
			return true
		end
	end
	return false
end

---@return boolean, string|nil
function PluginManager:initialize()
	if self.initialized then
		return true, nil
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			if entry.config.config and type(entry.plugin.configure) == "function" then
				entry.plugin:configure(entry.config.config)
			end
			local ok, err = call_plugin(entry, "initialize")
			if not ok then
				return false, err
			end
		end
	end

	self.initialized = true
	return true, nil
end

local function ensure_initialized(self)
	if self.initialized then
		return true, nil
	end
	return self:initialize()
end

---@return boolean, string|nil
function PluginManager:on_tool_call(tool_name, input)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_tool_call", tool_name, input)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_pre_tool_use(tool_name, input, ctx)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_pre_tool_use", tool_name, input, ctx)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_post_tool_use(tool_name, input, response, ctx)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_post_tool_use", tool_name, input, response, ctx)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_user_prompt_submit(prompt, ctx)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_user_prompt_submit", prompt, ctx)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_stop(ctx)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_stop", ctx)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_subagent_stop(ctx)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_subagent_stop", ctx)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_permission_update(update)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_permission_update", update)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_message(msg)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_message", msg)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:on_complete(result)
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for _, entry in ipairs(self.plugins) do
		if entry.config.enabled then
			ok, err = call_plugin(entry, "on_complete", result)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

---@return boolean, string|nil
function PluginManager:shutdown()
	local ok, err = ensure_initialized(self)
	if not ok then
		return false, err
	end

	for i = #self.plugins, 1, -1 do
		local entry = self.plugins[i]
		local shutdown_ok, shutdown_err = call_plugin(entry, "shutdown")
		if not shutdown_ok then
			err = shutdown_err
		end
	end

	self.initialized = false
	return err == nil, err
end

---@return string[]
function PluginManager:list()
	local names = {}
	for i, entry in ipairs(self.plugins) do
		names[i] = entry.plugin:name()
	end
	return names
end

---@return table|nil
function PluginManager:get(name)
	for _, entry in ipairs(self.plugins) do
		if entry.plugin:name() == name then
			return entry.plugin
		end
	end
	return nil
end

---@return integer
function PluginManager:count()
	return #self.plugins
end

---@return boolean, string|nil
function PluginManager:set_enabled(name, enabled)
	for _, entry in ipairs(self.plugins) do
		if entry.plugin:name() == name then
			entry.config.enabled = enabled
			return true, nil
		end
	end
	return false, ("plugin '%s' not found"):format(name)
end

return {
	new = PluginManager.new,
	PluginManager = PluginManager,
}

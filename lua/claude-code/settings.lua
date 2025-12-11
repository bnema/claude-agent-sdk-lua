-- luacheck: globals vim

local M = {}

-- Default settings structure
local default_settings = {
	permissions = {
		allow = {},
		deny = {},
		ask = {},
	},
}

-- Get the settings file path for a project (prefer settings.local.json)
---@param project_dir? string
---@return string, string  -- local path, shared path
function M.get_settings_paths(project_dir)
	local dir = project_dir or vim.fn.getcwd()
	return dir .. "/.claude/settings.local.json", dir .. "/.claude/settings.json"
end

-- Read settings from .claude/settings.local.json (or settings.json fallback)
---@param project_dir? string
---@return table
function M.read(project_dir)
	local local_path, shared_path = M.get_settings_paths(project_dir)

	-- Try local first, then shared
	local path = local_path
	local file = io.open(path, "r")
	if not file then
		path = shared_path
		file = io.open(path, "r")
	end

	if not file then
		return vim.deepcopy(default_settings)
	end

	local content = file:read("*a")
	file:close()

	local ok, settings = pcall(vim.json.decode, content)
	if not ok or type(settings) ~= "table" then
		return vim.deepcopy(default_settings)
	end

	-- Ensure permissions structure exists
	settings.permissions = settings.permissions or {}
	settings.permissions.allow = settings.permissions.allow or {}
	settings.permissions.deny = settings.permissions.deny or {}
	settings.permissions.ask = settings.permissions.ask or {}

	return settings
end

-- Write settings to .claude/settings.local.json
---@param settings table
---@param project_dir? string
---@return boolean, string|nil
function M.write(settings, project_dir)
	local path = M.get_settings_paths(project_dir) -- Use local path
	local dir = vim.fn.fnamemodify(path, ":h")

	-- Ensure .claude directory exists
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	local ok, json = pcall(vim.json.encode, settings)
	if not ok then
		return false, "Failed to encode settings"
	end

	-- Pretty print JSON (simple formatting)
	-- Use vim.fn.json_encode for better formatting if available
	local formatted = vim.fn.system({ "jq", "." }, json)
	if vim.v.shell_error == 0 then
		json = formatted
	end

	local file = io.open(path, "w")
	if not file then
		return false, "Failed to open settings file for writing"
	end

	file:write(json)
	file:close()
	return true, nil
end

-- Build permission string from tool name and input
---@param tool_name string
---@param tool_input table
---@return string
function M.build_permission_string(tool_name, tool_input)
	if tool_name == "Bash" and tool_input.command then
		-- Extract base command (first word before space)
		local base_cmd = tool_input.command:match("^([^%s]+)")
		return string.format("Bash(%s:*)", base_cmd)
	elseif tool_name == "Read" and tool_input.file_path then
		return string.format("Read(%s)", tool_input.file_path)
	elseif tool_name == "Write" and tool_input.file_path then
		return string.format("Write(%s)", tool_input.file_path)
	elseif tool_name == "Edit" and tool_input.file_path then
		return string.format("Edit(%s)", tool_input.file_path)
	elseif tool_name == "Glob" and tool_input.pattern then
		return string.format("Glob(%s)", tool_input.pattern)
	elseif tool_name == "Grep" and tool_input.pattern then
		return string.format("Grep(%s)", tool_input.pattern)
	elseif tool_name == "WebFetch" and tool_input.url then
		-- Extract domain from URL
		local domain = tool_input.url:match("https?://([^/]+)")
		if domain then
			return string.format("WebFetch(domain:%s)", domain)
		end
	elseif tool_name == "Skill" and tool_input.skill then
		return string.format("Skill(%s)", tool_input.skill)
	end
	-- Default: just tool name
	return tool_name
end

-- Check if a tool call matches a permission pattern
---@param tool_name string
---@param tool_input table
---@param pattern string
---@return boolean
function M.matches_pattern(tool_name, tool_input, pattern)
	-- Exact tool name match (e.g., "WebSearch" allows all WebSearch)
	if pattern == tool_name then
		return true
	end

	-- MCP tools (e.g., "mcp__context7__resolve-library-id")
	if pattern:match("^mcp__") then
		if tool_name == pattern then
			return true
		end
		return false
	end

	-- Parse pattern: ToolName(args)
	local pattern_tool, pattern_args = pattern:match("^(%w+)%((.+)%)$")
	if not pattern_tool then
		-- Simple tool name comparison
		return pattern == tool_name
	end

	-- Tool name must match
	if pattern_tool ~= tool_name then
		return false
	end

	-- Handle different tool types
	if tool_name == "Bash" and tool_input.command then
		-- Pattern like "Bash(git add:*)" matches "git add ."
		local pattern_cmd = pattern_args:gsub(":*$", "") -- Remove :* suffix
		local is_wildcard = pattern_args:match(":*$") ~= nil

		if is_wildcard then
			-- Match if command starts with pattern_cmd
			return tool_input.command:sub(1, #pattern_cmd) == pattern_cmd
		else
			-- Exact match
			return tool_input.command == pattern_args
		end
	elseif tool_name == "Read" and tool_input.file_path then
		-- Pattern like "Read(//path/**)" or "Read(/path/*)"
		local pattern_path = pattern_args:gsub("^/", "") -- Remove leading /
		local file_path = tool_input.file_path

		-- Handle ** glob (recursive)
		if pattern_path:match("%*%*") then
			local base = pattern_path:gsub("%*%*.*", ""):gsub("/$", "")
			return file_path:sub(1, #base) == base
		end

		-- Handle * glob (single level)
		if pattern_path:match("%*") then
			local lua_pattern = "^" .. pattern_path:gsub("%*", "[^/]*") .. "$"
			return file_path:match(lua_pattern) ~= nil
		end

		-- Exact match
		return file_path == pattern_path
	elseif tool_name == "WebFetch" and tool_input.url then
		-- Pattern like "WebFetch(domain:github.com)"
		local domain_pattern = pattern_args:match("^domain:(.+)$")
		if domain_pattern then
			local url_domain = tool_input.url:match("https?://([^/]+)")
			return url_domain == domain_pattern or (url_domain and url_domain:match("%." .. domain_pattern:gsub("%.", "%%.") .. "$"))
		end
	elseif tool_input.file_path then
		-- Generic file path matching for Write, Edit, etc.
		return tool_input.file_path == pattern_args or tool_input.file_path:match("^" .. pattern_args:gsub("%*", ".*") .. "$")
	elseif tool_input.pattern then
		-- Glob/Grep pattern matching
		return tool_input.pattern == pattern_args
	end

	return false
end

-- Check if a tool call is allowed by settings
---@param tool_name string
---@param tool_input table
---@param settings table
---@return boolean|nil  -- true=allow, false=deny, nil=ask
function M.check_permission(tool_name, tool_input, settings)
	local permissions = settings.permissions or {}
	local allow_list = permissions.allow or {}
	local deny_list = permissions.deny or {}

	-- Check deny list first (deny takes precedence)
	for _, pattern in ipairs(deny_list) do
		if M.matches_pattern(tool_name, tool_input, pattern) then
			return false
		end
	end

	-- Check allow list
	for _, pattern in ipairs(allow_list) do
		if M.matches_pattern(tool_name, tool_input, pattern) then
			return true
		end
	end

	-- Not in either list, need to ask
	return nil
end

-- Add a permission to the allow list and save
---@param tool_name string
---@param tool_input table
---@param project_dir? string
---@return boolean, string|nil
function M.add_allow(tool_name, tool_input, project_dir)
	local settings = M.read(project_dir)
	local perm_string = M.build_permission_string(tool_name, tool_input)

	-- Check if already in allow list
	for _, existing in ipairs(settings.permissions.allow) do
		if existing == perm_string then
			return true, nil -- Already allowed
		end
	end

	table.insert(settings.permissions.allow, perm_string)
	return M.write(settings, project_dir)
end

-- Add a permission to the deny list and save
---@param tool_name string
---@param tool_input table
---@param project_dir? string
---@return boolean, string|nil
function M.add_deny(tool_name, tool_input, project_dir)
	local settings = M.read(project_dir)
	local perm_string = M.build_permission_string(tool_name, tool_input)

	for _, existing in ipairs(settings.permissions.deny) do
		if existing == perm_string then
			return true, nil
		end
	end

	table.insert(settings.permissions.deny, perm_string)
	return M.write(settings, project_dir)
end

return M

-- luacheck: globals vim

local options = require("claude-code.options")
local errors = require("claude-code.errors")

local VALID_MODEL_ALIASES = {
	sonnet = true,
	opus = true,
	haiku = true,
}

local function is_valid_mcp_tool(tool)
	return tool:sub(1, 5) == "mcp__" and select(2, tool:gsub("__", "")) >= 2
end

local function validate_tools(tools)
	if tools == nil then
		return true
	end

	if type(tools) ~= "table" then
		return false, "tools must be an array of strings"
	end

	for _, tool in ipairs(tools) do
		if type(tool) ~= "string" or tool == "" then
			return false, "tool names must be non-empty strings"
		end
		if tool:sub(1, 5) == "mcp__" and not is_valid_mcp_tool(tool) then
			return false, "invalid MCP tool name (mcp__<serverName>__<toolName>)"
		end
	end

	return true
end

local function validate_config(config)
	if type(config) ~= "table" then
		return false, "subagent config must be a table"
	end

	if type(config.description) ~= "string" or vim.trim(config.description) == "" then
		return false, "subagent description is required"
	end

	if type(config.prompt) ~= "string" or vim.trim(config.prompt) == "" then
		return false, "subagent prompt is required"
	end

	if config.model and config.model ~= "" and not VALID_MODEL_ALIASES[config.model] then
		return false, "invalid model alias (must be sonnet, opus, or haiku)"
	end

	local tools_ok, tools_err = validate_tools(config.tools)
	if not tools_ok then
		return false, tools_err
	end

	if config.working_directory and type(config.working_directory) ~= "string" then
		return false, "working_directory must be a string"
	end

	return true
end

local function build_options(config, parent_opts)
	local opts = {
		system_prompt = config.prompt,
		allowed_tools = config.tools,
		format = "stream-json",
	}

	if config.model and config.model ~= "" then
		opts.model_alias = config.model
	elseif parent_opts then
		opts.model_alias = parent_opts.model_alias
		opts.model = parent_opts.model
	end

	if config.max_turns and config.max_turns > 0 then
		opts.max_turns = config.max_turns
	elseif parent_opts then
		opts.max_turns = parent_opts.max_turns
	end

	if config.working_directory and config.working_directory ~= "" then
		opts.working_directory = config.working_directory
	elseif parent_opts and parent_opts.working_directory then
		opts.working_directory = parent_opts.working_directory
	end

	if parent_opts then
		opts.mcp_config_path = parent_opts.mcp_config_path
		opts.permission_mode = parent_opts.permission_mode
		opts.permission_callback = parent_opts.permission_callback
		opts.budget_tracker = parent_opts.budget_tracker
		opts.plugin_manager = parent_opts.plugin_manager
	end

	return opts
end

---@class SubagentManager
---@field client ClaudeClient
---@field agents table<string, table>
---@field sessions table<string, string>
local SubagentManager = {}
SubagentManager.__index = SubagentManager

---@param client ClaudeClient
---@return SubagentManager
local function new_manager(client)
	return setmetatable({
		client = client,
		agents = {},
		sessions = {},
	}, SubagentManager)
end

---@param name string
---@param config table
---@return boolean, string|nil
function SubagentManager:register(name, config)
	if type(name) ~= "string" or vim.trim(name) == "" then
		return false, "agent name cannot be empty"
	end

	local ok, err = validate_config(config)
	if not ok then
		return false, string.format("invalid config for %s: %s", name, err)
	end

	self.agents[name] = vim.deepcopy(config)
	return true, nil
end

---@param agents table<string, table>
---@return boolean, string|nil
function SubagentManager:register_many(agents)
	for name, config in pairs(agents or {}) do
		local ok, err = self:register(name, config)
		if not ok then
			return false, err
		end
	end
	return true, nil
end

---@param name string
function SubagentManager:unregister(name)
	self.agents[name] = nil
	self.sessions[name] = nil
end

---@param name string
---@return table|nil
function SubagentManager:get(name)
	local config = self.agents[name]
	if not config then
		return nil
	end
	return vim.deepcopy(config)
end

---@return string[]
function SubagentManager:list()
	local names = {}
	for name in pairs(self.agents) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

---@return table<string, string>
function SubagentManager:descriptions()
	local descriptions = {}
	for name, config in pairs(self.agents) do
		descriptions[name] = config.description
	end
	return descriptions
end

---@param agent_name string
---@param prompt string
---@param parent_opts? table
---@return table|nil, ClaudeError|nil
function SubagentManager:run(agent_name, prompt, parent_opts)
	local config = self.agents[agent_name]
	if not config then
		return nil,
			errors.new(errors.ErrorType.validation, string.format("unknown subagent: %s", agent_name), nil, {
				agent = agent_name,
			})
	end

	local opts = build_options(config, parent_opts or {})
	return self.client:run_prompt(prompt, options.merge(parent_opts or {}, opts))
end

---@param agent_name string
---@param prompt string
---@param parent_opts? table
---@param on_message fun(msg: table)
---@param on_error fun(err: ClaudeError)
---@param on_complete fun()
---@return table|nil
function SubagentManager:stream(agent_name, prompt, parent_opts, on_message, on_error, on_complete)
	local config = self.agents[agent_name]
	if not config then
		on_error(errors.new(errors.ErrorType.validation, "unknown subagent", nil, { agent = agent_name }))
		return nil
	end

	local opts = build_options(config, parent_opts or {})
	return self.client:stream_prompt(prompt, options.merge(parent_opts or {}, opts), on_message, on_error, on_complete)
end

---@param agent_name string
---@param prompt string
---@param parent_opts? table
---@return table|nil, ClaudeError|nil
function SubagentManager:resume(agent_name, prompt, parent_opts)
	local session_id = self.sessions[agent_name]
	if not session_id then
		return nil,
			errors.new(errors.ErrorType.session, string.format("no session for subagent %s", agent_name), nil, {
				agent = agent_name,
			})
	end

	local config = self.agents[agent_name]
	if not config then
		return nil,
			errors.new(errors.ErrorType.validation, string.format("unknown subagent: %s", agent_name), nil, {
				agent = agent_name,
			})
	end

	local opts = build_options(config, parent_opts or {})
	opts.resume_id = session_id
	opts.continue = false
	return self.client:run_prompt(prompt, options.merge(parent_opts or {}, opts))
end

---@param agent_name string
---@param session_id string
function SubagentManager:set_session(agent_name, session_id)
	if type(session_id) ~= "string" or session_id == "" then
		return
	end
	self.sessions[agent_name] = session_id
end

---@param agent_name string
---@return string|nil
function SubagentManager:get_session(agent_name)
	return self.sessions[agent_name]
end

---@param agent_name string
function SubagentManager:clear_session(agent_name)
	self.sessions[agent_name] = nil
end

function SubagentManager:clear_all_sessions()
	self.sessions = {}
end

local function security_reviewer_agent()
	return {
		description = "Security auditing and vulnerability analysis. "
			.. "Use for security reviews and identifying security flaws.",
		prompt = [[You are a security expert specializing in application security.
Focus on:
- Authentication and authorization vulnerabilities
- Injection vulnerabilities (SQL, XSS, command injection)
- Insecure dependencies and outdated packages
- Credential exposure and secrets management
- API security issues and rate limiting

Provide detailed explanations with severity levels and remediation steps.]],
		tools = { "Read", "Grep", "Glob" },
		model = "sonnet",
	}
end

local function code_reviewer_agent()
	return {
		description = "Code quality and best practices expert. Use for code reviews and refactoring suggestions.",
		prompt = [[You are a senior software architect focused on code quality.
Review:
- Code organization and modularity
- Design patterns and SOLID principles
- Error handling and edge cases
- Code duplication and technical debt
- Documentation quality

Provide refactoring suggestions with examples.]],
		tools = { "Read", "Grep", "Glob" },
		model = "sonnet",
	}
end

local function test_analyst_agent()
	return {
		description = "Testing and QA expert. Use for test coverage analysis and recommendations.",
		prompt = [[You are a QA and testing expert.
Evaluate:
- Test coverage completeness
- Edge cases and boundary conditions
- Integration test scenarios
- Mock and stub usage
- Test maintainability

Suggest missing tests with code examples.]],
		tools = { "Read", "Grep", "Glob", "Bash" },
		model = "haiku",
	}
end

local function performance_analyst_agent()
	return {
		description = "Performance optimization expert. Use for analyzing bottlenecks and optimization opportunities.",
		prompt = [[You are a performance optimization specialist.
Analyze:
- Algorithm complexity and bottlenecks
- Memory usage patterns
- Database query optimization
- Caching strategies
- Resource utilization

Provide specific metrics and actionable recommendations.]],
		tools = { "Read", "Grep", "Glob", "Bash" },
		model = "sonnet",
	}
end

local function documentation_agent()
	return {
		description = "Documentation specialist. Use for generating or improving documentation and README files.",
		prompt = [[You are a technical documentation expert.
Focus on:
- Clear and concise explanations
- Code examples and usage patterns
- API documentation with parameters and return values
- README structure and content
- Inline code comments

Generate well-structured, comprehensive documentation.]],
		tools = { "Read", "Grep", "Glob", "Write" },
		model = "sonnet",
	}
end

return {
	new_manager = new_manager,
	SubagentManager = SubagentManager,
	security_reviewer = security_reviewer_agent,
	code_reviewer = code_reviewer_agent,
	test_analyst = test_analyst_agent,
	performance_analyst = performance_analyst_agent,
	documentation = documentation_agent,
}

-- luacheck: globals vim

local args_builder = require("claude-code.util.args")
local budget = require("claude-code.budget")
local errors = require("claude-code.errors")
local options = require("claude-code.options")
local result_parser = require("claude-code.result")
local client_mod = require("claude-code.client")

local REQUIRED_FLAG = "i-accept-all-risks"

local function is_production_env()
	local env = vim.env
	return env.NODE_ENV == "production"
		or env.GO_ENV == "production"
		or env.LUA_ENV == "production"
		or env.ENVIRONMENT == "production"
		or env.ENVIRONMENT == "prod"
end

local function warn(message)
	if vim.notify then
		vim.notify(message, vim.log.levels.WARN)
	else
		io.stderr:write(message .. "\n")
	end
end

local function resolve_budget_tracker(opts)
	if opts.budget_tracker then
		return opts.budget_tracker
	end

	if opts.max_budget_usd and opts.max_budget_usd > 0 then
		return budget.new({ max_budget_usd = opts.max_budget_usd })
	end

	return nil
end

local function apply_budget(tracker, res)
	if not tracker or not res then
		return nil
	end

	local cost = res.total_cost_usd or res.cost_usd
	if not cost or cost <= 0 then
		return nil
	end

	local ok, budget_err = tracker:add_spend(res.session_id or "default", cost)
	if not ok then
		return errors.new(errors.ErrorType.validation, budget_err or "Budget exceeded", nil, {
			max_budget_usd = tracker.config.max_budget_usd,
			current_spend = tracker:total(),
		})
	end

	return nil
end

local function call_plugin_manager(manager, method, ...)
	if not manager or type(manager[method]) ~= "function" then
		return nil
	end

	local ok, success, err = pcall(manager[method], manager, ...)
	if not ok then
		return errors.new(errors.ErrorType.validation, success)
	end

	if success == false then
		return errors.new(errors.ErrorType.validation, err or "plugin rejected operation")
	end

	return nil
end

local function merge_env(env_vars)
	if not env_vars or vim.tbl_isempty(env_vars) then
		return nil
	end

	local merged = vim.fn.environ()
	for key, value in pairs(env_vars) do
		merged[key] = value
	end

	return merged
end

---@class DangerousClient
---@field client ClaudeClient
---@field env_vars table<string, string>
---@field mcp_debug boolean
local DangerousClient = {}
DangerousClient.__index = DangerousClient

---@param bin_path? string
---@return DangerousClient|nil, string|nil
local function new(bin_path)
	if vim.env.CLAUDE_ENABLE_DANGEROUS ~= REQUIRED_FLAG then
		return nil, "dangerous client requires CLAUDE_ENABLE_DANGEROUS=i-accept-all-risks"
	end

	if is_production_env() then
		return nil, "dangerous client is blocked in production environments"
	end

	return setmetatable({
		client = client_mod.new(bin_path),
		env_vars = {},
		mcp_debug = false,
	}, DangerousClient),
		nil
end

---@param env_vars table<string, string>
---@return boolean, string|nil
function DangerousClient:set_environment_variables(env_vars)
	if type(env_vars) ~= "table" then
		return false, "environment variables must be provided as a table"
	end

	for key in pairs(env_vars) do
		local upper = key:upper()
		if upper:find("PASSWORD", 1, true) or upper:find("SECRET", 1, true) or upper:find("TOKEN", 1, true) then
			warn(string.format("Setting potentially sensitive environment variable: %s", key))
		end
		if upper:find("PATH", 1, true) then
			warn("Modifying PATH can affect executable resolution")
		end
	end

	for key, value in pairs(env_vars) do
		self.env_vars[key] = value
	end

	return true, nil
end

---@return boolean
function DangerousClient:enable_mcp_debug()
	self.mcp_debug = true
	warn("MCP debugging enabled; verbose logging may include sensitive data")
	return true
end

local function run_with_flags(self, prompt, opts, skip_permissions, env_vars)
	local merged_opts = options.merge(self.client.default_options, opts or {})
	local opt_err = options.validate(merged_opts)
	if opt_err then
		return nil, opt_err
	end

	local args = args_builder.build(prompt or "", merged_opts)
	if skip_permissions then
		table.insert(args, "--dangerously-skip-permissions")
		warn("Executing with permissions bypassed; this removes all safety controls")
	end

	if self.mcp_debug then
		table.insert(args, "--mcp-debug")
		if not merged_opts.verbose then
			table.insert(args, "--verbose")
		end
	end

	local env = merge_env(self.env_vars)
	if env_vars and not vim.tbl_isempty(env_vars) then
		env = env or vim.fn.environ()
		for key, value in pairs(env_vars) do
			env[key] = value
		end
	end
	local result = vim.system(
		vim.list_extend({ self.client.bin_path }, args),
		{ text = true, timeout = merged_opts.timeout, env = env }
	):wait()

	if result.code ~= 0 then
		return nil, errors.parse(result.stderr or "", result.code)
	end

	local parsed, parse_err = result_parser.parse(result.stdout or "", merged_opts.format)
	if parse_err then
		return nil, parse_err
	end

	local tracker = resolve_budget_tracker(merged_opts)
	local budget_err = apply_budget(tracker, parsed)
	if budget_err then
		return nil, budget_err
	end

	local plugin_err = call_plugin_manager(merged_opts.plugin_manager, "on_complete", parsed)
	if plugin_err then
		return nil, plugin_err
	end

	return parsed, nil
end

---@param prompt string
---@param opts? table
---@return table|nil, ClaudeError|nil
function DangerousClient:bypass_all_permissions(prompt, opts)
	return run_with_flags(self, prompt, opts, true, nil)
end

---@param prompt string
---@param opts? table
---@param env_vars? table<string, string>
---@return table|nil, ClaudeError|nil
function DangerousClient:run_with_environment(prompt, opts, env_vars)
	return run_with_flags(self, prompt, opts, false, env_vars or {})
end

---@return string[]
function DangerousClient:get_security_warnings()
	local warnings = {}

	if not vim.tbl_isempty(self.env_vars) then
		table.insert(
			warnings,
			string.format("Environment injection active (%d variables)", vim.tbl_count(self.env_vars))
		)
	end
	if self.mcp_debug then
		table.insert(warnings, "MCP debug logging enabled")
	end

	return warnings
end

function DangerousClient:reset()
	self.env_vars = {}
	self.mcp_debug = false
	warn("Cleared dangerous settings")
end

return {
	new = new,
	DangerousClient = DangerousClient,
}

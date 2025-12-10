-- luacheck: globals vim

local args_builder = require("claude-code.util.args")
local errors = require("claude-code.errors")
local options = require("claude-code.options")
local result_parser = require("claude-code.result")

---@class ClaudeClient
---@field bin_path string
---@field default_options table
local ClaudeClient = {}
ClaudeClient.__index = ClaudeClient

---@param bin_path? string
---@param default_options? table
---@return ClaudeClient
local function new(bin_path, default_options)
	return setmetatable({
		bin_path = bin_path or "claude",
		default_options = options.normalize(default_options),
	}, ClaudeClient)
end

---@param prompt string
---@param opts? table
---@return table|nil, ClaudeError|nil
function ClaudeClient:run_prompt(prompt, opts)
	local merged_opts = options.merge(self.default_options, opts or {})
	local err = options.validate(merged_opts)
	if err then
		return nil, err
	end

	local cmd_args = vim.list_extend({ self.bin_path }, args_builder.build(prompt or "", merged_opts))
	local result = vim.system(cmd_args, { text = true, timeout = merged_opts.timeout }):wait()

	if result.code ~= 0 then
		return nil, errors.parse(result.stderr or "", result.code)
	end

	local parsed, parse_err = result_parser.parse(result.stdout or "", merged_opts.format)
	if parse_err then
		return nil, parse_err
	end

	return parsed, nil
end

return {
	ClaudeClient = ClaudeClient,
	new = new,
}

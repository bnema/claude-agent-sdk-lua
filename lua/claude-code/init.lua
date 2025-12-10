---@mod claude-code Claude Code SDK for Neovim
---@brief [[
--- A Lua SDK for the Claude Code CLI, designed for Neovim plugin developers.
--- Provides sync/async execution, streaming, permissions, budget tracking,
--- plugins, and subagent management.
---@brief ]]

local M = {}

M.VERSION = "0.1.0"

M.OutputFormat = { TEXT = "text", JSON = "json", STREAM_JSON = "stream-json" }
M.PermissionMode = { DEFAULT = "default", ACCEPT_EDITS = "acceptEdits", BYPASS = "bypassPermissions" }

M.Client = require("claude-code.client").ClaudeClient
M.new_client = require("claude-code.client").new

M.is_retryable = require("claude-code.errors").is_retryable
M.retry_delay = require("claude-code.errors").retry_delay

local permissions = require("claude-code.permissions")
M.allow = permissions.allow
M.deny = permissions.deny
M.ask = permissions.ask
M.read_only_callback = permissions.read_only_callback
M.safe_bash_callback = permissions.safe_bash_callback
M.file_path_callback = permissions.file_path_callback
M.chain_callbacks = permissions.chain_callbacks

M.new_budget_tracker = require("claude-code.budget").new

---@param opts? { bin_path?: string, default_options?: table }
---@return table client
function M.setup(opts)
	opts = opts or {}
	return M.new_client(opts.bin_path, opts.default_options)
end

return M

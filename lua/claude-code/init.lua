---@mod claude-code Claude Code SDK for Neovim
---@brief [[
--- A Lua SDK for the Claude Code CLI, designed for Neovim plugin developers.
--- Provides sync/async execution, streaming, permissions, budget tracking,
--- plugins, and subagent management.
---@brief ]]

local M = {}

M.VERSION = "0.1.0"

-- TODO: Implement core modules
-- M.Client = require("claude-code.client").ClaudeClient
-- M.new_client = require("claude-code.client").new

---@param opts? { bin_path?: string, default_options?: table }
---@return table client
function M.setup(opts)
  opts = opts or {}
  -- TODO: Implement client creation
  return {}
end

return M

-- luacheck: globals vim pending

local M = {}

local function cli_bin()
	return vim.env.CLAUDE_CLI_BIN or "claude"
end

function M.has_cli()
	return vim.fn.executable(cli_bin()) == 1
end

function M.skip_if_no_cli()
	if M.has_cli() then
		return false
	end

	pending("Claude CLI not available (set CLAUDE_CLI_BIN to a valid path)")
	return true
end

function M.new_client()
	local claude = require("claude-code")
	return claude.setup({ bin_path = cli_bin() })
end

return M

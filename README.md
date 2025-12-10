# claude-agent-sdk-lua

A Lua SDK for the Claude Code CLI, designed for Neovim plugin developers.

## Requirements

- Neovim 0.10+
- Claude Code CLI installed and accessible in PATH

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "bnema/claude-agent-sdk-lua",
  config = function()
    local claude = require("claude-code")
    -- Your configuration here
  end,
}
```

## Quick Start (plugin authors)

```lua
local claude = require("claude-code")

-- Create one client and share it across your plugin
local client = claude.setup({
  bin_path = "claude",          -- or absolute path
  default_options = {
    mcp_config_path = "/path/to/mcp.json",
    permission_mode = "default", -- or "acceptEdits"
  },
})

-- Synchronous call
local result, err = client:run_prompt("Hello!", { format = "json" })
if err then
  vim.notify("Error: " .. tostring(err), vim.log.levels.ERROR)
else
  print("Response: " .. result.result)
end

-- Asynchronous call
client:run_prompt_async("Explain this code", {}, function(err, result)
  if result then
    print(result.result)
  end
end)

-- Streaming (partial messages enabled)
client:stream_prompt("Build a function", {},
  function(msg) print(msg.type) end,
  function(err) vim.notify(tostring(err)) end,
  function() print("Done!") end
)

-- Permissions
local cb = claude.safe_bash_callback({ "rm", "shutdown" })
client:run_prompt("Run this shell cmd", { permission_callback = cb })
```

## Features

- Sync and async prompt execution
- Real-time streaming support
- Permission callbacks for tool control
- Budget tracking
- Plugin system with lifecycle hooks
- Subagent management
- Guarded dangerous client for bypassing permissions
- Full LuaLS type annotations

## Plugin author guide

- **Create one client**: Build it in your setup and reuse to avoid extra CLI startup.
- **Async-first**: Prefer `run_prompt_async` or `stream_prompt` to keep UI responsive.
- **Permissions**: Pass `permission_mode` and `permission_callback` to enforce your plugin’s policy. Built-ins cover read-only, safe bash, and path allowlists.
- **Budget**: Attach `budget_tracker` or `max_budget_usd` to avoid runaway costs.
- **Plugins**: Use `new_plugin_manager()` to register logging/metrics/audit or a tool filter and pass it via `{ plugin_manager = ... }`.
- **Subagents**: Register presets like `claude.security_reviewer_agent()` and call `subagents:run("security", prompt)` when you need specialized reviews.
- **Dangerous client (opt-in)**: Only when `CLAUDE_ENABLE_DANGEROUS=i-accept-all-risks` and not in production. Use `new_dangerous_client()` to bypass permissions or inject env vars—never with untrusted input.

## Plugins

```lua
local plugins = claude.new_plugin_manager()
plugins:register(claude.LoggingPlugin.new())
plugins:register(claude.ToolFilterPlugin.new({ allowed_tools = { "Read", "Grep" } }))
client:run_prompt("Hello", { plugin_manager = plugins })
```

## Formatting & Linting

Run stylua and luacheck after changes:

```
stylua lua
luacheck lua/claude-code
```

## Running tests

Unit tests and integration tests are written with plenary:

```
# Unit/specs (keep user config out with -u NONE; set PLENARY_PATH if not packadded)
nvim --headless -u NONE -c "luafile tests/minimal_init.lua | PlenaryBustedDirectory tests/plenary"

# Integration (requires Claude CLI in PATH or CLAUDE_CLI_BIN)
PLENARY_PATH=/path/to/plenary.nvim CLAUDE_CLI_BIN=/usr/local/bin/claude \
  nvim --headless -u NONE -c "luafile tests/minimal_init.lua | PlenaryBustedDirectory tests/plenary"
```

The integration specs will `pending` if the CLI binary is missing so they won’t fail your run.

## License

MIT

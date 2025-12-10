# claude-code-lua

A Lua SDK for the Claude Code CLI, designed for Neovim plugin developers.

## Requirements

- Neovim 0.10+
- Claude Code CLI installed and accessible in PATH

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "brice/claude-code-lua",
  config = function()
    local claude = require("claude-code")
    -- Your configuration here
  end,
}
```

## Quick Start

```lua
local claude = require("claude-code")

-- Create a client
local client = claude.setup({ bin_path = "claude" })

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

-- Subagents
local subagents = claude.new_subagent_manager(client)
subagents:register("security", claude.security_reviewer_agent())
local res = subagents:run("security", "Audit the auth flow")
print(res and res.result)

-- Dangerous client (guarded)
local dangerous, derr = claude.new_dangerous_client("claude")
if dangerous then
  dangerous:enable_mcp_debug()
  dangerous:bypass_all_permissions("Do the risky thing", { max_turns = 1 })
end
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

## License

MIT

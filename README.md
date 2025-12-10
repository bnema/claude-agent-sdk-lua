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

-- Streaming
client:stream_prompt("Build a function", {},
  function(msg) print(msg.type) end,
  function(err) vim.notify(tostring(err)) end,
  function() print("Done!") end
)
```

## Features

- Sync and async prompt execution
- Real-time streaming support
- Permission callbacks for tool control
- Budget tracking
- Plugin system with lifecycle hooks
- Subagent management
- Full LuaLS type annotations

## License

MIT

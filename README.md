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
    settings = { projectSettings = { maxModelDepth = "quick" } },
    setting_sources = { "userSettings", "projectSettings" },
    agents = { helper = { instructions = "You summarize responses" } },
    plugins = { "/path/to/claude-plugins" },
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

-- Continue/resume a session (no history scraping required)
local first, err = client:run_prompt("Start session", { format = "json" })
if first and first.session_id then
  client:continue_conversation("Keep going", { session_id = first.session_id })
  client:resume_conversation("Return later", first.session_id, { fork_session = true })
end

-- List recent sessions for the current project (from ~/.claude/history.jsonl)
local sessions = client:list_sessions({ limit = 10 })
if sessions and sessions[1] then
  client:resume_session(sessions[1].session_id, "Pick up where we left off")
end

-- Async listing with summaries populated from session files
client:list_sessions_async({ limit = 5 }, function(found, list_err)
  if found and not list_err and found[1] then
    print(found[1].summary or found[1].display)
  end
end)
```

## Features

- Sync and async prompt execution
- Real-time streaming support
- Permission callbacks for tool control
- Session control: continue/resume/fork, explicit `session_id` selection
- Budget tracking
- Plugin system with lifecycle hooks
- Agents, settings, betas, fallback model, thinking token cap, plugin dirs, structured MCP config
- Subagent management
- Guarded dangerous client for bypassing permissions
- Session history helpers (list/resume recent sessions)
- Full LuaLS type annotations

## API Reference

- `setup(opts?)` / `new_client(bin_path?, default_opts?)`: create a client (sync/async/stream) wired to the Claude Code CLI.
- `OutputFormat` / `PermissionMode`: enums for `format` and `permission_mode` options.
- `allow/deny/ask`: permission callbacks for deterministic, blocked, or interactive tool control.
- `read_only_callback` / `safe_bash_callback(cmds)` / `file_path_callback(paths)` / `chain_callbacks(...)`: built-in permission policies.
- `is_retryable(err)` / `retry_delay(err)`: helpers for handling CLI retryable errors.
- `new_budget_tracker({ max_budget_usd? })`: track cumulative cost across calls.
- `new_plugin_manager()` / `PluginManager` / `BasePlugin`: register lifecycle hooks; built-ins include `LoggingPlugin`, `MetricsPlugin`, `AuditPlugin`, `ToolFilterPlugin`.
- `new_subagent_manager(client)` / `SubagentManager`: manage specialized agents; presets `security_reviewer_agent`, `code_reviewer_agent`, `test_analyst_agent`, `performance_analyst_agent`, `documentation_agent`.
- `new_dangerous_client(opts?)` / `DangerousClient`: permission-bypassing client guarded by `CLAUDE_ENABLE_DANGEROUS=i-accept-all-risks` and disabled in prod envs.
- `history.list_sessions({ project?, limit?, claude_dir? })` / `history.list_sessions_async(opts, cb)`: enumerate recent Claude sessions from `~/.claude/history.jsonl`; defaults to the current working directory. `client:list_sessions` and `client:list_sessions_async` forward to these helpers.

## Plugin author guide

- **Create one client**: Build it in your setup and reuse to avoid extra CLI startup.
- **Async-first**: Prefer `run_prompt_async` or `stream_prompt` to keep UI responsive.
- **Permissions**: Pass `permission_mode` and `permission_callback` to enforce your plugin’s policy. Built-ins cover read-only, safe bash, and path allowlists.
- **Budget**: Attach `budget_tracker` or `max_budget_usd` to avoid runaway costs.
- **Plugins**: Use `new_plugin_manager()` to register logging/metrics/audit or a tool filter and pass it via `{ plugin_manager = ... }`. Hooks include `on_pre_tool_use`, `on_post_tool_use`, `on_user_prompt_submit`, `on_stop`, `on_subagent_stop`, `on_permission_update`, `on_tool_call`, `on_message`, `on_complete`.
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

-- luacheck: globals vim

local errors = require("claude-code.errors")

local M = {}

local DEFAULT_LIMIT = 50
local HISTORY_FILE = "history.jsonl"

---@class SessionEntry
---@field session_id string
---@field display string
---@field summary? string
---@field project string
---@field timestamp? number

local function normalize_path(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end

	local normalized = vim.fs.normalize(path)
	normalized = normalized:gsub("[/\\]+$", "")
	return normalized
end

local function resolve_claude_dir(opts)
	if type(opts) == "string" and opts ~= "" then
		return opts
	end

	if type(opts) == "table" and type(opts.claude_dir) == "string" and opts.claude_dir ~= "" then
		return opts.claude_dir
	end

	local home = vim.loop.os_homedir() or vim.env.HOME
	if not home or home == "" then
		return vim.fn.expand("~/.claude")
	end

	return vim.fs.joinpath(home, ".claude")
end

---@param path string
---@return string
function M.encode_project_path(path)
	if not path then
		return ""
	end

	local encoded = path:gsub(":", "-")
	encoded = encoded:gsub("[/\\]", "-")
	encoded = encoded:gsub("%-+", "-")
	return encoded
end

---@param project string
---@param opts? { claude_dir?: string }|string
---@return string
function M.get_project_dir(project, opts)
	return vim.fs.joinpath(resolve_claude_dir(opts), "projects", M.encode_project_path(project))
end

---@param session_id string
---@param project string
---@param opts? { claude_dir?: string }|string
---@return string
function M.get_session_file(session_id, project, opts)
	return vim.fs.joinpath(M.get_project_dir(project, opts), session_id .. ".jsonl")
end

local function parse_history_line(line)
	if not line or line == "" or not line:match("%S") then
		return nil
	end

	local ok, decoded = pcall(vim.json.decode, line)
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local session_id = decoded.sessionId or decoded.session_id
	if type(session_id) ~= "string" or session_id == "" then
		return nil
	end

	local project = normalize_path(decoded.project)
	if not project then
		return nil
	end

	local display = decoded.display
	if type(display) ~= "string" then
		display = tostring(display or "")
	end

	return {
		session_id = session_id,
		display = display,
		project = project,
		timestamp = tonumber(decoded.timestamp),
	}
end

---@param opts? { project?: string, limit?: number, claude_dir?: string }
---@return SessionEntry[]|nil, ClaudeError|nil
function M.list_sessions(opts)
	opts = opts or {}
	local claude_dir = resolve_claude_dir(opts)
	local history_path = vim.fs.joinpath(claude_dir, HISTORY_FILE)

	if not vim.loop.fs_stat(history_path) then
		return {}, nil
	end

	local file, open_err = io.open(history_path, "r")
	if not file then
		return nil,
			errors.new(errors.ErrorType.command, "Failed to read Claude history", nil, {
				error = open_err,
				path = history_path,
			})
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	local seen = {}
	local sessions = {}
	local limit = tonumber(opts.limit)
	if not limit then
		limit = DEFAULT_LIMIT
	elseif limit < 0 then
		limit = DEFAULT_LIMIT
	elseif limit == 0 then
		return {}, nil
	end

	local project_filter = normalize_path(opts.project or vim.fn.getcwd())

	for i = #lines, 1, -1 do
		if #sessions >= limit then
			break
		end

		local entry = parse_history_line(lines[i])
		if entry and (not project_filter or entry.project == project_filter) and not seen[entry.session_id] then
			seen[entry.session_id] = true
			table.insert(sessions, entry)
		end
	end

	return sessions, nil
end

local function parse_summary(data)
	if not data or data == "" then
		return nil
	end

	local first_line = data:match("([^\n]*)")
	if not first_line or not first_line:match("%S") then
		return nil
	end

	local ok, decoded = pcall(vim.json.decode, first_line)
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	if type(decoded.summary) == "string" and decoded.summary ~= "" then
		return decoded.summary
	end

	if type(decoded.title) == "string" and decoded.title ~= "" then
		return decoded.title
	end

	return nil
end

local function read_summary_async(path, callback)
	local done = vim.schedule_wrap(callback)

	if not path or path == "" then
		done(nil)
		return
	end

	vim.loop.fs_open(path, "r", 438, function(open_err, fd)
		if open_err or not fd then
			done(nil)
			return
		end

		vim.loop.fs_read(fd, 4096, 0, function(read_err, data)
			vim.loop.fs_close(fd)

			if read_err then
				done(nil)
				return
			end

			done(parse_summary(data))
		end)
	end)
end

---@param opts? { project?: string, limit?: number, claude_dir?: string }
---@param callback fun(sessions: SessionEntry[]|nil, err: ClaudeError|nil)
function M.list_sessions_async(opts, callback)
	local notify = vim.schedule_wrap(callback)
	local sessions, err = M.list_sessions(opts)
	if err or not sessions then
		notify(nil, err)
		return
	end

	if #sessions == 0 then
		notify({}, nil)
		return
	end

	local remaining = #sessions
	for _, session in ipairs(sessions) do
		local session_file = M.get_session_file(session.session_id, session.project, opts)
		read_summary_async(session_file, function(summary)
			session.summary = summary
			remaining = remaining - 1
			if remaining == 0 then
				notify(sessions, nil)
			end
		end)
	end
end

return M

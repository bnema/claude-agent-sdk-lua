-- luacheck: globals vim

local history = require("claude-code.history")

require("plenary.busted")

local function tmp_claude_dir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

local function write_history(dir, entries)
	local path = vim.fs.joinpath(dir, "history.jsonl")
	local file = assert(io.open(path, "w"))
	for _, entry in ipairs(entries) do
		file:write(vim.json.encode(entry))
		file:write("\n")
	end
	file:close()
	return path
end

local function write_session(dir, project, session_id, summary)
	local project_dir = history.get_project_dir(project, dir)
	vim.fn.mkdir(project_dir, "p")
	local session_path = history.get_session_file(session_id, project, dir)
	local file = assert(io.open(session_path, "w"))

	if summary then
		file:write(vim.json.encode({ type = "summary", summary = summary, leafUuid = "leaf" }))
		file:write("\n{}\n")
	end

	file:close()
	return session_path
end

describe("history", function()
	it("encodes project paths", function()
		assert.are.equal("-home-brice-projects-foo", history.encode_project_path("/home/brice/projects/foo"))
		assert.are.equal("C-Users-test", history.encode_project_path("C:\\Users\\test"))
	end)

	it("lists recent sessions for a project", function()
		local dir = tmp_claude_dir()
		local project = "/tmp/project-a"
		local other_project = "/tmp/project-b"

		write_history(dir, {
			{ display = "old", timestamp = 1, project = project, sessionId = "s1" },
			{ display = "new", timestamp = 2, project = project, sessionId = "s2" },
			{ display = "dup", timestamp = 3, project = project, sessionId = "s1" },
			{ display = "other", timestamp = 4, project = other_project, sessionId = "s3" },
		})

		local sessions, err = history.list_sessions({ claude_dir = dir, project = project })
		assert.is_nil(err)
		assert.are.same(
			{ "s1", "s2" },
			vim.tbl_map(function(s)
				return s.session_id
			end, sessions)
		)
		assert.are.equal("dup", sessions[1].display)
	end)

	it("loads summaries asynchronously", function()
		local dir = tmp_claude_dir()
		local project = "/tmp/project-c"

		write_history(dir, {
			{ display = "has summary", timestamp = 1, project = project, sessionId = "s1" },
			{ display = "no summary", timestamp = 2, project = project, sessionId = "s2" },
		})

		write_session(dir, project, "s1", "Session Summary")

		local done = false
		local captured = nil
		local err = nil

		history.list_sessions_async({ claude_dir = dir, project = project }, function(sessions, list_err)
			captured = sessions
			err = list_err
			done = true
		end)

		vim.wait(2000, function()
			return done
		end)

		assert.is_true(done)
		assert.is_nil(err)
		assert.is_truthy(captured)
		assert.are.equal("Session Summary", captured[1].summary)
		assert.are.equal("no summary", captured[2].display)
	end)
end)

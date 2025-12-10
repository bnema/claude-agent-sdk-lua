local subagent = require("claude-code.subagent")

require("plenary.busted")

describe("SubagentManager", function()
	it("validates configs", function()
		local mgr = subagent.new_manager({ default_options = {} })
		local ok, err = mgr:register("bad", { description = "", prompt = "x" })
		assert.is_false(ok)
		assert.is_truthy(err:find("description"))
	end)

	it("runs registered agents with merged options", function()
		local captured_opts
		local fake_client = {
			default_options = {},
			run_prompt = function(_, prompt, opts)
				captured_opts = opts
				return { result = prompt }, nil
			end,
		}

		local mgr = subagent.new_manager(fake_client)
		local ok, err = mgr:register("security", subagent.security_reviewer())
		assert.is_true(ok)
		assert.is_nil(err)

		local res, run_err = mgr:run("security", "Audit", { max_turns = 2, permission_mode = "default" })
		assert.is_nil(run_err)
		assert.are.same("Audit", res.result)
		assert.are.same("stream-json", captured_opts.format)
		assert.is_truthy(captured_opts.system_prompt:find("security expert"))
		assert.are.same({ "Read", "Grep", "Glob" }, captured_opts.allowed_tools)
		assert.equals(2, captured_opts.max_turns)
	end)

	it("errors when resuming without a session", function()
		local mgr = subagent.new_manager({ default_options = {}, run_prompt = function() end })
		local _, err = mgr:resume("missing", "prompt", {})
		assert.is_truthy(err)
		assert.equals("session", err.type)
	end)
end)

-- luacheck: globals vim pending

local helpers = require("tests.plenary.helpers.integration")

require("plenary.busted")

describe("integration (Claude CLI)", function()
	if helpers.skip_if_no_cli() then
		return
	end

	local client = helpers.new_client()

	it("runs JSON prompt", function()
		local res, err = client:run_prompt("What is 2+2?", { format = "json" })
		assert.is_nil(err)
		assert.is_truthy(res.result)
		assert.is_truthy(res.session_id)
		assert.is_true((res.cost_usd or 0) >= 0)
	end)

	it("runs text prompt", function()
		local res, err = client:run_prompt("Say hello", { format = "text" })
		assert.is_nil(err)
		assert.is_truthy(res.result)
		assert.is_truthy(res.result:lower():find("hello"))
	end)

	it("streams messages", function()
		local messages = {}
		local done = false
		local stream_err = nil

		client:stream_prompt("Count from 1 to 5", {}, function(msg)
			table.insert(messages, msg)
		end, function(err)
			stream_err = err
		end, function()
			done = true
		end)

		vim.wait(30000, function()
			return done or stream_err ~= nil
		end)

		assert.is_nil(stream_err)
		assert.is_true(done)
		assert.is_true(#messages > 0)
	end)
end)

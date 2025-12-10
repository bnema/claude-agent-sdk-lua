-- luacheck: globals vim

local dangerous = require("claude-code.dangerous")

require("plenary.busted")

describe("DangerousClient", function()
	local saved_env = {}

	before_each(function()
		for _, key in ipairs({ "CLAUDE_ENABLE_DANGEROUS", "NODE_ENV", "GO_ENV", "LUA_ENV", "ENVIRONMENT" }) do
			saved_env[key] = vim.env[key]
		end
	end)

	after_each(function()
		for key, val in pairs(saved_env) do
			vim.env[key] = val
		end
	end)

	it("blocks when confirmation flag is missing", function()
		vim.env.CLAUDE_ENABLE_DANGEROUS = nil
		local client, err = dangerous.new("claude")
		assert.is_nil(client)
		assert.is_truthy(err:find("i-accept-all-risks"))
	end)

	it("blocks in production environments", function()
		vim.env.CLAUDE_ENABLE_DANGEROUS = "i-accept-all-risks"
		vim.env.NODE_ENV = "production"
		local client, err = dangerous.new("claude")
		assert.is_nil(client)
		assert.is_truthy(err:find("production"))
	end)

	it("constructs when allowed", function()
		vim.env.CLAUDE_ENABLE_DANGEROUS = "i-accept-all-risks"
		vim.env.NODE_ENV = nil
		vim.env.GO_ENV = nil
		vim.env.LUA_ENV = nil
		vim.env.ENVIRONMENT = nil

		local client, err = dangerous.new("claude")
		assert.is_nil(err)
		assert.is_table(client)
		assert.are.same({}, client:get_security_warnings())
	end)
end)

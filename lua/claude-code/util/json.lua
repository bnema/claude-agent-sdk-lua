-- luacheck: globals vim

local M = {}

---@param on_value fun(value: table)
---@param on_error fun(line: string, decode_err: any)
---@return fun(chunk: string|nil)
function M.new_line_parser(on_value, on_error)
	local buffer = ""

	return function(chunk)
		if chunk == nil then
			if buffer:match("%S") then
				local ok, decoded = pcall(vim.json.decode, buffer)
				if ok and type(decoded) == "table" then
					on_value(decoded)
				else
					on_error(buffer, decoded)
				end
			end
			buffer = ""
			return
		end

		buffer = buffer .. chunk

		while true do
			local nl = buffer:find("\n", 1, true)
			if not nl then
				break
			end

			local line = buffer:sub(1, nl - 1)
			buffer = buffer:sub(nl + 1)

			if line:match("%S") then
				local ok, decoded = pcall(vim.json.decode, line)
				if ok and type(decoded) == "table" then
					on_value(decoded)
				else
					on_error(line, decoded)
					buffer = ""
					return
				end
			end
		end
	end
end

return M

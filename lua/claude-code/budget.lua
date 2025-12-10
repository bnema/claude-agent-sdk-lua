-- luacheck: globals vim

local M = {}

---@class BudgetConfig
---@field max_budget_usd? number
---@field warning_threshold? number
---@field on_warning? fun(current: number, max: number)
---@field on_exceeded? fun(current: number, max: number)

---@class BudgetTracker
---@field total_spent number
---@field session_spent table<string, number>
---@field config BudgetConfig
---@field warning_emitted boolean
local BudgetTracker = {}
BudgetTracker.__index = BudgetTracker

---@param config? BudgetConfig
---@return BudgetTracker
function M.new(config)
	config = config or {}

	return setmetatable({
		total_spent = 0,
		session_spent = {},
		config = {
			max_budget_usd = config.max_budget_usd or config.MaxBudgetUSD,
			warning_threshold = config.warning_threshold or config.WarningThreshold or 0,
			on_warning = config.on_warning or config.OnBudgetWarning,
			on_exceeded = config.on_exceeded or config.OnBudgetExceeded,
		},
		warning_emitted = false,
	}, BudgetTracker)
end

---@return number
function BudgetTracker:total()
	return self.total_spent
end

---@param session_id string
---@return number
function BudgetTracker:session_total(session_id)
	return self.session_spent[session_id] or 0
end

---@return number
function BudgetTracker:remaining()
	local max_budget = self.config.max_budget_usd or 0
	if max_budget <= 0 then
		return -1
	end

	local remaining = max_budget - self.total_spent
	if remaining < 0 then
		return 0
	end
	return remaining
end

---@param amount number
---@return boolean
function BudgetTracker:can_spend(amount)
	local max_budget = self.config.max_budget_usd or 0
	if max_budget <= 0 then
		return true
	end
	return self.total_spent + amount <= max_budget
end

---@param session_id string
---@param amount number
---@return boolean, string?
function BudgetTracker:add_spend(session_id, amount)
	session_id = session_id or "default"
	amount = amount or 0

	self.total_spent = self.total_spent + amount
	self.session_spent[session_id] = (self.session_spent[session_id] or 0) + amount

	local max_budget = self.config.max_budget_usd or 0
	if
		max_budget > 0
		and self.config.warning_threshold
		and self.config.warning_threshold > 0
		and not self.warning_emitted
	then
		local warning_amount = max_budget * self.config.warning_threshold
		if self.total_spent >= warning_amount then
			self.warning_emitted = true
			if self.config.on_warning then
				pcall(self.config.on_warning, self.total_spent, max_budget)
			end
		end
	end

	if max_budget > 0 and self.total_spent > max_budget then
		if self.config.on_exceeded then
			pcall(self.config.on_exceeded, self.total_spent, max_budget)
		end
		return false, "Budget limit exceeded"
	end

	return true, nil
end

function BudgetTracker:reset()
	self.total_spent = 0
	self.session_spent = {}
	self.warning_emitted = false
end

---@param session_id string
function BudgetTracker:reset_session(session_id)
	local spent = self.session_spent[session_id]
	if spent then
		self.total_spent = self.total_spent - spent
		self.session_spent[session_id] = nil
	end
end

---@param new_config BudgetConfig
function BudgetTracker:update_config(new_config)
	self.config.max_budget_usd = new_config.max_budget_usd or new_config.MaxBudgetUSD or self.config.max_budget_usd
	self.config.warning_threshold = new_config.warning_threshold
		or new_config.WarningThreshold
		or self.config.warning_threshold
	self.config.on_warning = new_config.on_warning or new_config.OnBudgetWarning or self.config.on_warning
	self.config.on_exceeded = new_config.on_exceeded or new_config.OnBudgetExceeded or self.config.on_exceeded
	self.warning_emitted = false
end

M.BudgetTracker = BudgetTracker

return M

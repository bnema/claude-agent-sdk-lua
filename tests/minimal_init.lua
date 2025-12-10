-- luacheck: globals vim

vim.opt.runtimepath:append(".")

local plenary_path = vim.env.PLENARY_PATH
if plenary_path and plenary_path ~= "" then
	vim.opt.runtimepath:append(plenary_path)
end

pcall(vim.cmd, "packadd plenary.nvim")
pcall(vim.cmd, "runtime plugin/plenary.vim")

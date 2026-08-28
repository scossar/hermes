local config = require("hermes.config")

local M = {}

--- Setup the plugin with user options.
--- @param opts table|nil User configuration overrides
function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})
end

--- Example command implementation.
function M.hello()
  vim.notify("Hello from hermes.nvim!", vim.log.levels.INFO)
end

return M

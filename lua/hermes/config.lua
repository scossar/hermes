local M = {}

--- Default plugin options. Extend as needed.
M.defaults = {
  enabled = true,
}

--- Active options table, populated by setup().
M.options = M.defaults

return M

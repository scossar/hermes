local M = {}

M.defaults = {
  enabled = true,
}

M.options = vim.tbl_deep_extend("force", {}, M.defaults)

return M

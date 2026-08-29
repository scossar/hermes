local M = {}

M.defaults = {
  enabled = true,
  bridge_cmd = { "node", vim.fn.stdpath("data") .. "hermes.nvim/bridge/build/bridge.js", "http://127.0.0.1" },
}

M.options = vim.tbl_deep_extend("force", {}, M.defaults)

return M

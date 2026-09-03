local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

M.defaults = {
  enabled = true,
  session_store_file = vim.fn.stdpath("state") .. "/hermes.nvim/session.json",
  bridge_cmd = {
    "node",
    plugin_root .. "/bridge/dist/bridge.js",
    "http://127.0.0.1:9119",
  },
  composer_height = 10,
}

M.options = vim.tbl_deep_extend("force", {}, M.defaults)

return M

local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

M.defaults = {
  enabled = true,
  bridge_cmd = {
    "node",
    plugin_root .. "/bridge/dist/bridge.js",
    "http://127.0.0.1:9119",
  },
}

M.options = vim.tbl_deep_extend("force", {}, M.defaults)

return M

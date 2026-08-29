local config = require("hermes.config")
local chat = require("hermes.chat")
local buffer = require("hermes.buffer")
local session = require("hermes.session")
local selection = require("hermes.selection")

local M = {}

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})
  chat.setup()
end

function M.ask(prompt)
  chat.ask(prompt)
end

function M.ask_selection()
  chat.ask_selection(selection.current())
end

function M.open()
  buffer.show()
end

function M.stop()
  chat.stop()
  session.shutdown()
end

return M

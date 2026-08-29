local config = require("hermes.config")
local chat = require("hermes.chat")
local buffer = require("hermes.buffer")
local session = require("hermes.session")
local selection = require("hermes.selection")
local interaction = require("hermes.interaction")
local events = require("hermes.events")

local M = {}

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})
  chat.setup()
  interaction.setup()
  events.setup()
end

function M.ask(prompt)
  chat.ask(prompt)
end

function M.ask_selection()
  chat.ask_selection(selection.current())
end

function M.open()
  chat.open()
end

function M.stop()
  chat.stop()
  session.shutdown()
end

function M.interrupt()
  chat.interrupt()
end

function M.new_session()
  chat.stop()
  buffer.clear()
  session.new_session(function(_, err)
    if err then
      vim.notify("hermes: could not create a new session: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

return M

local config = require("hermes.config")
local chat = require("hermes.chat")
local session = require("hermes.session")
local selection = require("hermes.selection")
local interaction = require("hermes.interaction")
local events = require("hermes.events")

local M = {}

local initialized = false

local function initialize()
  if initialized then
    return
  end
  initialized = true
  chat.setup()
  interaction.setup()
  events.setup()
end

local function ensure_setup()
  if not initialized then
    M.setup()
  end
end

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", {}, config.defaults, opts or {})
  initialize()
end

function M.ask(prompt)
  ensure_setup()
  chat.ask(prompt)
end

function M.ask_selection()
  ensure_setup()
  chat.ask_selection(selection.current())
end

function M.open()
  ensure_setup()
  chat.open()
end

function M.stop()
  ensure_setup()
  chat.stop()
  session.shutdown()
end

function M.interrupt()
  ensure_setup()
  chat.interrupt()
end

function M.new_session()
  ensure_setup()
  if not chat.begin_session_transition() then
    vim.notify("hermes: wait for the new session to finish", vim.log.levels.WARN)
    return
  end
  session.new_session(function(_, err)
    if err then
      chat.end_session_transition()
      vim.notify("hermes: could not create a new session: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
      return
    end
    chat.reset_conversation()
    chat.end_session_transition()
  end)
end

return M

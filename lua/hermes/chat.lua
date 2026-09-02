local application = require("hermes.application")

local M = {}

local function app()
  return application.get()
end

function M.setup() end

function M.ask(text, options)
  return app():submit(text, options)
end

function M.ask_selection(text)
  return app():submit(text, { selection = true, delimiter = true })
end

function M.open()
  return app():open()
end

function M.is_running()
  return app():is_running()
end

function M.stop()
  return app():stop()
end

function M.interrupt()
  if not app():interrupt() then
    vim.notify("hermes: no active turn to interrupt", vim.log.levels.INFO)
  end
end

function M.new_session(callback)
  return app():new_session(callback)
end

-- Compatibility facade for callers that used the old transition API.
function M.begin_session_transition()
  local phase = app():model().session.phase
  return phase ~= "replacing" and phase ~= "persisting_replacement"
end

function M.end_session_transition() end

function M.reset_conversation()
  require("hermes.buffer").clear()
end

function M.reset()
  application.reset()
end

return M

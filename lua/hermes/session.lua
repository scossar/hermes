local application = require("hermes.application")

local M = {}

local function app()
  return application.get()
end

function M.is_active()
  return app():model().session.phase == "active"
end

function M.current_session_id()
  return app():model().session.live_id
end

function M.current_stored_session_id()
  return app():model().session.durable_id
end

-- Compatibility adapter. New code submits/open through hermes.application.
function M.ensure_session(callback)
  local current = app()
  if current:model().session.phase == "active" then
    callback(current:model().session.live_id, nil, { messages = {} })
    return
  end
  current:open()
  callback(nil, { message = "session activation is asynchronous; use the application controller" })
end

function M.shutdown(callback)
  app():stop()
  if callback then
    callback()
  end
end

function M.new_session(callback)
  return app():new_session(callback)
end

-- Lifecycle listeners moved into machine events/effects. These no-ops preserve
-- source compatibility without creating a second state owner.
function M.on_disconnect() end
function M.on_resume() end

return M

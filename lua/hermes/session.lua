local process = require("hermes.process")
local rpc = require("hermes.rpc")
local config = require("hermes.config")

local M = {}

local session_id = nil
local stored_session_id = nil
local state = "stopped"
local waiters = {}
local disconnect_handler = nil

local function reset()
  session_id = nil
  stored_session_id = nil
  state = "stopped"
end

local function notify_waiters(id)
  local callbacks = waiters
  waiters = {}
  for _, callback in ipairs(callbacks) do
    callback(id)
  end
end

local function fail_waiters(message)
  local callbacks = waiters
  waiters = {}
  reset()
  for _, callback in ipairs(callbacks) do
    callback(nil, { message = message })
  end
  vim.notify("hermes: " .. message, vim.log.levels.ERROR)
end

function M.is_active()
  return state == "active" and session_id ~= nil
end

function M.current_session_id()
  return session_id
end

function M.current_stored_session_id()
  return stored_session_id
end

function M.on_disconnect(handler)
  disconnect_handler = handler
end

function M.ensure_session(cb)
  if M.is_active() then
    cb(session_id)
    return
  end

  table.insert(waiters, cb)
  if state == "connecting" or state == "creating" then
    return
  end

  state = "connecting"
  local started = process.start(config.options.bridge_cmd, rpc.handle_message, function(code)
    local was_active = state == "active"
    reset()
    rpc.fail_pending({ code = -32000, message = "bridge process exited" })
    if was_active and disconnect_handler then
      disconnect_handler()
    end
    if code ~= 0 or was_active then
      vim.notify("hermes: bridge disconnected", vim.log.levels.ERROR)
    end
  end)

  if not started then
    fail_waiters("could not start bridge process")
    return
  end

  state = "creating"
  rpc.request("session.create", {
    cols = 100,
    cwd = vim.fn.getcwd(),
    source = "hermes.nvim",
    title = "hermes.nvim session",
  }, function(result)
    session_id = result.session_id
    stored_session_id = result.stored_session_id
    state = "active"
    notify_waiters(session_id)
  end, function(err)
    fail_waiters("session.create failed: " .. (err.message or "unknown error"))
    process.stop()
  end)
end

function M.shutdown()
  if not M.is_active() then
    process.stop()
    reset()
    return
  end

  state = "closing"
  rpc.request("session.close", { session_id = session_id }, function()
    process.stop()
    reset()
  end, function(err)
    vim.notify("hermes: session.close failed: " .. (err.message or "unknown error"), vim.log.levels.WARN)
    process.stop()
    reset()
  end)
end

return M

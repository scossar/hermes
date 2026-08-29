local process = require("hermes.process")
local rpc = require("hermes.rpc")
local config = require("hermes.config")
local durable_state = require("hermes.state")

local M = {}

local session_id = nil
local stored_session_id = nil
local state = "stopped"
local waiters = {}
local disconnect_handler = nil
local shutdown_waiters = {}
local start_session

local function reset()
  session_id = nil
  stored_session_id = nil
  state = "stopped"
end

local function notify_waiters(id, err, details)
  local callbacks = waiters
  waiters = {}
  for _, callback in ipairs(callbacks) do
    callback(id, err, details)
  end
end

local function notify_shutdown_waiters()
  local callbacks = shutdown_waiters
  shutdown_waiters = {}
  for _, callback in ipairs(callbacks) do
    callback()
  end
end

local function fail_waiters(message)
  notify_waiters(nil, { message = message })
  vim.notify("hermes: " .. message, vim.log.levels.ERROR)
end

local function on_process_exit(code)
  local was_active = state == "active"
  reset()
  rpc.fail_pending({ code = -32000, message = "bridge process exited" })
  if was_active and disconnect_handler then
    disconnect_handler()
  end
  if code ~= 0 or was_active then
    vim.notify("hermes: bridge disconnected", vim.log.levels.ERROR)
  end
  notify_shutdown_waiters()
  if #waiters > 0 then
    start_session()
  end
end

local function activate(result)
  if type(result) ~= "table" or type(result.session_id) ~= "string" or result.session_id == "" then
    fail_waiters("invalid session response")
    state = "stopping"
    process.stop()
    return
  end
  session_id = result.session_id
  stored_session_id = result.stored_session_id or result.session_key or result.resumed
  if stored_session_id then
    durable_state.save(config.options.state_file, stored_session_id)
  end
  state = "active"
  notify_waiters(session_id, nil, result)
end

local function request_session()
  local persisted_id = durable_state.load(config.options.state_file)
  local method = persisted_id and "session.resume" or "session.create"
  local params = {
    cols = 100,
    cwd = vim.fn.getcwd(),
    source = "hermes.nvim",
  }
  if persisted_id then
    params.session_id = persisted_id
  else
    params.title = "hermes.nvim session"
  end

  state = persisted_id and "resuming" or "creating"
  rpc.request(method, params, activate, function(err)
    if persisted_id and (err.code == 4007 or err.code == 4001) then
      durable_state.clear(config.options.state_file)
      state = "stopped"
      request_session()
      return
    end
    fail_waiters(string.format("%s failed: %s", method, err.message or "unknown error"))
    state = "stopping"
    process.stop()
  end)
end

start_session = function()
  state = "connecting"
  local started = process.start(config.options.bridge_cmd, rpc.handle_message, on_process_exit)
  if not started then
    reset()
    fail_waiters("could not start bridge process")
    return
  end
  request_session()
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
    cb(session_id, nil, { session_id = session_id, stored_session_id = stored_session_id, messages = {} })
    return
  end
  table.insert(waiters, cb)
  if state ~= "stopped" then
    return
  end
  start_session()
end

function M.shutdown(cb)
  if cb then
    table.insert(shutdown_waiters, cb)
  end
  if state == "stopped" then
    notify_shutdown_waiters()
    return
  end
  if state == "stopping" or state == "closing" then
    return
  end
  if not M.is_active() then
    state = "stopping"
    process.stop()
    return
  end

  state = "closing"
  rpc.request("session.close", { session_id = session_id }, function()
    state = "stopping"
    process.stop()
  end, function(err)
    vim.notify("hermes: session.close failed: " .. (err.message or "unknown error"), vim.log.levels.WARN)
    state = "stopping"
    process.stop()
  end)
end

function M.new_session(cb)
  durable_state.clear(config.options.state_file)
  M.shutdown(function()
    M.ensure_session(cb or function() end)
  end)
end

return M

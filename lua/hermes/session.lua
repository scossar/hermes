local process = require("hermes.process")
local rpc = require("hermes.rpc")
local config = require("hermes.config")
local durable_state = require("hermes.state")

local M = {}

local session_id = nil
local stored_session_id = nil
local state = "stopped"
local waiters = {}
local shutdown_waiters = {}
local disconnect_handler = nil
local resume_handler = nil
local generation = 0
local process_generation = 0
local activation_details = nil
local details_delivered = false
local start_session

local function reset()
  session_id = nil
  stored_session_id = nil
  state = "stopped"
  activation_details = nil
  details_delivered = false
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

local function deliver_details()
  if details_delivered then
    return { session_id = session_id, stored_session_id = stored_session_id, messages = {} }
  end
  details_delivered = true
  return activation_details
end

local function request_session(my_generation)
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
  rpc.request(method, params, function(result)
    if my_generation ~= generation or (state ~= "creating" and state ~= "resuming") then
      return
    end
    if type(result) ~= "table" or type(result.session_id) ~= "string" or result.session_id == "" then
      fail_waiters("invalid session response")
      state = "stopping"
      process.stop()
      return
    end

    local durable_id = result.stored_session_id or result.session_key
    if not durable_id and type(result.resumed) == "string" then
      durable_id = result.resumed
    end
    if type(durable_id) ~= "string" or durable_id == "" then
      fail_waiters("session response omitted its durable id")
      state = "stopping"
      process.stop()
      return
    end

    local ok, save_err = durable_state.save(config.options.state_file, durable_id)
    if not ok then
      fail_waiters("could not persist session id: " .. (save_err or "unknown error"))
      state = "stopping"
      process.stop()
      return
    end

    session_id = result.session_id
    stored_session_id = durable_id
    activation_details = result
    details_delivered = false
    state = "active"
    if resume_handler then
      resume_handler(result, session_id)
    end
    notify_waiters(session_id, nil, deliver_details())
  end, function(err)
    if my_generation ~= generation or (state ~= "creating" and state ~= "resuming") then
      return
    end
    local message = tostring(err.message or "unknown error")
    if persisted_id and err.code == 4007 and message == "session not found" then
      durable_state.clear(config.options.state_file)
      request_session(my_generation)
      return
    end
    fail_waiters(string.format("%s failed: %s", method, message))
    state = "stopping"
    process.stop()
  end)
end

start_session = function()
  generation = generation + 1
  local my_generation = generation
  process_generation = process_generation + 1
  local my_process_generation = process_generation
  state = "connecting"
  local started = process.start(config.options.bridge_cmd, rpc.handle_message, function(code)
    if my_process_generation ~= process_generation then
      return
    end
    local was_active = state == "active"
    state = "exited"
    rpc.fail_pending({ code = -32000, message = "bridge process exited" })
    reset()
    if was_active and disconnect_handler then
      disconnect_handler()
    end
    if code ~= 0 or was_active then
      vim.notify("hermes: bridge disconnected", vim.log.levels.ERROR)
    end
    notify_shutdown_waiters()
    if #waiters > 0 and state == "stopped" then
      start_session()
    end
  end)
  if not started then
    reset()
    fail_waiters("could not start bridge process")
    return
  end
  request_session(my_generation)
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

function M.on_resume(handler)
  resume_handler = handler
end

function M.ensure_session(cb)
  if M.is_active() then
    cb(session_id, nil, deliver_details())
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
  if state == "stopping" or state == "closing" or state == "exited" then
    return
  end

  generation = generation + 1
  notify_waiters(nil, { message = "session stopped" })
  if not session_id then
    state = "stopping"
    process.stop()
    return
  end

  state = "closing"
  local closing_id = session_id
  rpc.request("session.close", { session_id = closing_id }, function()
    if state ~= "closing" then
      return
    end
    state = "stopping"
    process.stop()
  end, function(err)
    if state ~= "closing" then
      return
    end
    vim.notify("hermes: session.close failed: " .. (err.message or "unknown error"), vim.log.levels.WARN)
    state = "stopping"
    process.stop()
  end)
end

function M.new_session(cb)
  local ok, clear_err = durable_state.clear(config.options.state_file)
  if not ok then
    if cb then
      cb(nil, { message = clear_err or "could not clear durable session" })
    end
    return
  end
  M.shutdown(function()
    M.ensure_session(cb or function() end)
  end)
end

return M

local buffer = require("hermes.buffer")
local rpc = require("hermes.rpc")
local session = require("hermes.session")

local M = {}

local active_session_id = nil
local running = false
local saw_delta = false
local delimit_response = false

local function event_for_active_session(params)
  return running and params.session_id == active_session_id
end

function M.setup()
  rpc.on_event("message.delta", function(params)
    if not event_for_active_session(params) then
      return
    end
    local payload = params.payload or {}
    saw_delta = true
    buffer.append(payload.text or "")
  end)

  rpc.on_event("message.complete", function(params)
    if not event_for_active_session(params) then
      return
    end
    local payload = params.payload or {}
    if payload.text and payload.text ~= "" then
      buffer.replace_assistant(payload.text)
    end
    buffer.finish_assistant({ delimiter = delimit_response })
    running = false
    active_session_id = nil
  end)

  session.on_disconnect(function()
    if not running then
      return
    end
    buffer.append("_Connection lost before the response completed._")
    buffer.finish_assistant()
    M.reset()
  end)
end

local function ask(text, options)
  M.setup()
  options = options or {}
  text = vim.trim(text or "")
  if text == "" then
    vim.notify("hermes: prompt cannot be empty", vim.log.levels.WARN)
    return
  end
  if running then
    vim.notify("hermes: wait for the current response to finish", vim.log.levels.WARN)
    return
  end

  running = true
  active_session_id = nil
  saw_delta = false
  delimit_response = options.delimiter == true

  buffer.show()
  if not options.selection then
    buffer.append_user(text)
  end
  buffer.begin_assistant()

  session.ensure_session(function(session_id, err)
    if not session_id then
      buffer.append(string.format("_Could not create a Hermes session: %s_", (err and err.message) or "unknown error"))
      buffer.finish_assistant()
      running = false
      return
    end
    active_session_id = session_id

    rpc.request(
      "prompt.submit",
      {
        session_id = session_id,
        text = text,
      },
      nil,
      function(err)
        buffer.append(string.format("_Request failed: %s_", err.message or "unknown error"))
        buffer.finish_assistant()
        running = false
        active_session_id = nil
      end
    )
  end)
end

function M.ask(text)
  ask(text)
end

function M.ask_selection(text)
  ask(text, { selection = true, delimiter = true })
end

function M.is_running()
  return running
end

function M.stop()
  if running then
    buffer.append("_Stopped before the response completed._")
    buffer.finish_assistant()
  end
  M.reset()
end

function M.reset()
  active_session_id = nil
  running = false
  saw_delta = false
  delimit_response = false
end

return M

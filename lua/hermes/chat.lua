local buffer = require("hermes.buffer")
local rpc = require("hermes.rpc")
local session = require("hermes.session")
local history = require("hermes.history")
local events = require("hermes.events")
local interaction = require("hermes.interaction")

local M = {}

local active_session_id = nil
local running = false
local interrupting = false
local delimit_response = false
local turn_generation = 0
local hydrated = false
local hydrating = false
local pending_asks = {}

local function event_for_active_session(params)
  return running and params.session_id == active_session_id
end

local function append_status(text)
  buffer.append("\n\n" .. text)
end

local function finish_turn(options)
  events.end_turn()
  buffer.finish_assistant(options or { delimiter = delimit_response })
  running = false
  interrupting = false
  active_session_id = nil
end

function M.setup()
  rpc.on_event("message.delta", function(params)
    if not event_for_active_session(params) or interrupting then
      return
    end
    buffer.append(tostring((params.payload or {}).text or ""))
  end)

  rpc.on_event("message.complete", function(params)
    if not event_for_active_session(params) then
      return
    end
    local payload = params.payload or {}
    if interrupting then
      append_status("_Interrupted._")
    elseif payload.text and payload.text ~= "" then
      buffer.replace_assistant(payload.text)
    elseif payload.status and payload.status ~= "complete" then
      append_status(string.format("_Turn ended: %s._", payload.status))
    end
    finish_turn()
  end)

  session.on_disconnect(function()
    interaction.invalidate()
    if not running then
      return
    end
    append_status("_Connection lost before the response completed._")
    finish_turn()
  end)

  session.on_resume(function(details, sid)
    interaction.handle_pending(details, sid)
  end)
end

local function submit(text, options)
  running = true
  interrupting = false
  turn_generation = turn_generation + 1
  local my_generation = turn_generation
  delimit_response = options.delimiter == true
  events.begin_turn()

  if not options.selection then
    buffer.append_user(text)
  end
  buffer.begin_assistant()

  session.ensure_session(function(session_id, err)
    if my_generation ~= turn_generation or not running then
      return
    end
    if not session_id then
      append_status(string.format("_Could not create a Hermes session: %s_", (err and err.message) or "unknown error"))
      finish_turn()
      return
    end
    active_session_id = session_id
    rpc.request("prompt.submit", { session_id = session_id, text = text }, nil, function(request_err)
      if my_generation ~= turn_generation or not running then
        return
      end
      append_status(string.format("_Request failed: %s_", request_err.message or "unknown error"))
      finish_turn()
    end)
  end)
end

local function flush_pending()
  if running or not hydrated or #pending_asks == 0 then
    return
  end
  local item = table.remove(pending_asks, 1)
  submit(item.text, item.options)
end

local function ensure_hydrated(done)
  if hydrated then
    done()
    return
  end
  if hydrating then
    return
  end
  hydrating = true
  session.ensure_session(function(_, err, details)
    hydrating = false
    if err then
      buffer.append_block({ string.format("_Could not create a Hermes session: %s_", err.message or "unknown error") })
      pending_asks = {}
      vim.notify("hermes: " .. (err.message or "could not open session"), vim.log.levels.ERROR)
      return
    end
    if details and details.messages and #details.messages > 0 then
      history.render(details.messages)
    end
    hydrated = true
    done()
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
  if running or hydrating then
    vim.notify("hermes: wait for the current response to finish", vim.log.levels.WARN)
    return
  end

  buffer.show()
  table.insert(pending_asks, { text = text, options = options })
  ensure_hydrated(flush_pending)
end

function M.ask(text)
  ask(text)
end

function M.ask_selection(text)
  ask(text, { selection = true, delimiter = true })
end

function M.open()
  buffer.show()
  ensure_hydrated(function() end)
end

function M.is_running()
  return running or hydrating
end

function M.stop()
  interaction.invalidate()
  turn_generation = turn_generation + 1
  pending_asks = {}
  if running then
    append_status("_Stopped before the response completed._")
    finish_turn()
  end
  hydrated = false
  M.reset()
end

function M.interrupt()
  if not running or not active_session_id or interrupting then
    vim.notify("hermes: no active turn to interrupt", vim.log.levels.INFO)
    return
  end
  local interrupted_session = active_session_id
  local my_generation = turn_generation
  interrupting = true
  interaction.invalidate()
  events.end_turn()
  rpc.request("session.interrupt", { session_id = interrupted_session }, function()
    if my_generation ~= turn_generation or active_session_id ~= interrupted_session then
      return
    end
    -- Keep running=true until the interrupted turn's terminal message.complete
    -- arrives. That prevents a late completion from being mistaken for a new turn.
  end, function(err)
    if my_generation == turn_generation then
      interrupting = false
      vim.notify("hermes: interrupt failed: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

function M.reset()
  active_session_id = nil
  running = false
  interrupting = false
  delimit_response = false
  hydrated = false
  hydrating = false
  events.end_turn()
end

function M.reset_conversation()
  M.stop()
  buffer.clear()
  hydrated = true
end

return M

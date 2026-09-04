local M = {}

---@class HermesProtocolEvent : HermesEvent
---@field session_id? any
---@field sequence? any
---@field text? string
---@field request_id? any
---@field request? table
---@field activity_type? string
---@field payload? table
---@field wire_type? string
---@field status? string
---@field error? string
---@field partial? boolean
---@field recoverable? boolean

---@class HermesWireEvent
---@field type? any
---@field session_id? any
---@field seq? any
---@field payload? any

---@param payload table<string, any>
---@return boolean
local function valid_clarification_payload(payload)
  if payload.questions == nil then
    return true
  end
  if type(payload.questions) ~= "table" then
    return false
  end
  for _, question in ipairs(payload.questions) do
    if type(question) ~= "table" then
      return false
    end
  end
  return true
end

---@param params HermesWireEvent
---@return HermesProtocolEvent?
function M.to_event(params)
  if type(params) ~= "table" then
    return nil
  end
  local payload = type(params.payload) == "table" and params.payload or {}
  if params.type == "message.delta" then
    return {
      type = "message.delta",
      session_id = params.session_id,
      sequence = params.seq,
      text = tostring(payload.text or ""),
    }
  end
  local interaction_types = {
    ["approval.request"] = "approval.requested",
    ["clarify.request"] = "clarification.requested",
  }
  if interaction_types[params.type] then
    if params.type == "clarify.request" and not valid_clarification_payload(payload) then
      return {
        type = "protocol.unknown",
        wire_type = params.type,
        session_id = params.session_id,
        sequence = params.seq,
        payload = payload,
      }
    end
    return {
      type = interaction_types[params.type],
      session_id = params.session_id,
      sequence = params.seq,
      request_id = payload.request_id,
      request = payload,
    }
  end
  local activity_types = {
    ["reasoning.delta"] = true,
    ["thinking.delta"] = true,
    ["tool.start"] = true,
    ["tool.progress"] = true,
    ["tool.complete"] = true,
  }
  if activity_types[params.type] then
    return {
      type = "agent_activity.received",
      session_id = params.session_id,
      sequence = params.seq,
      activity_type = params.type,
      payload = payload,
    }
  end
  if params.type ~= "message.complete" then
    if type(params.type) ~= "string" then
      return nil
    end
    return {
      type = "protocol.unknown",
      wire_type = params.type,
      session_id = params.session_id,
      sequence = params.seq,
      payload = payload,
    }
  end
  local status = type(payload.status) == "string" and payload.status or "complete"
  local text = type(payload.text) == "string" and payload.text or nil
  local error_message
  if type(payload.error) == "string" then
    error_message = payload.error
  elseif type(payload.error) == "table" and type(payload.error.message) == "string" then
    error_message = payload.error.message
  end
  return {
    type = "message.completed",
    session_id = params.session_id,
    sequence = params.seq,
    status = status,
    text = text,
    error = error_message,
    partial = type(payload.partial) == "boolean" and payload.partial or nil,
    recoverable = type(payload.recoverable) == "boolean" and payload.recoverable or nil,
  }
end

return M

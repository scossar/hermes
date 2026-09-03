local process = require("hermes.process")

local M = {}

local next_id = 0
local pending = {} -- [id] = { on_result = fn, on_error = fn }
local event_handler = nil

local function response_error(err)
  if type(err) == "table" and type(err.code) == "number" and type(err.message) == "string" then
    return err
  end
  return { code = -32603, message = "malformed JSON-RPC error response" }
end

--- Send a JSON-RPC request. on_result(result) or on_error(err) is called.
function M.request(method, params, on_result, on_error)
  next_id = next_id + 1
  local id = next_id

  pending[id] = { on_result = on_result, on_error = on_error }

  process.send({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  })
end

--- Register the one general gateway event receiver.
function M.on_event(handler)
  assert(type(handler) == "function", "rpc.on_event expects one general event receiver")
  event_handler = handler
end

function M.fail_pending(err)
  local waiters = pending
  pending = {}
  for _, waiter in pairs(waiters) do
    if waiter.on_error then
      waiter.on_error(err)
    end
  end
end

--- process.lua's on_message callback. One frame in, dispatched by shape.
function M.handle_message(frame)
  if frame.id ~= nil then
    local waiter = pending[frame.id]
    if not waiter then
      return -- response to an event we're no longer tracking
    end
    pending[frame.id] = nil -- done with this id; free the slot

    if frame.error ~= nil then
      if waiter.on_error then
        waiter.on_error(response_error(frame.error))
      end
    elseif frame.result ~= nil then
      if waiter.on_result then
        waiter.on_result(frame.result)
      end
    elseif waiter.on_error then
      waiter.on_error({ code = -32603, message = "malformed JSON-RPC response" })
    end
    return
  end

  if frame.method ~= "event" or type(frame.params) ~= "table" then
    return
  end

  local params = frame.params
  if type(params.type) ~= "string" or (params.payload ~= nil and type(params.payload) ~= "table") then
    return
  end
  if event_handler then
    event_handler(params)
  end
end

return M

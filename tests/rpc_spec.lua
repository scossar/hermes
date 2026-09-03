local process = require("hermes.process")
local rpc = require("hermes.rpc")

describe("JSON-RPC dispatch", function()
  local original_send

  before_each(function()
    package.loaded["hermes.rpc"] = nil
    rpc = require("hermes.rpc")
    original_send = process.send
    process.send = function() end
  end)

  after_each(function()
    process.send = original_send
  end)

  it("forwards all protocol events through one general receiver", function()
    local received
    rpc.on_event(function(params)
      received = params
    end)

    rpc.handle_message({
      method = "event",
      params = { type = "message.delta", session_id = "live-1", seq = 1, payload = { text = "Hi" } },
    })

    assert.equals("message.delta", received.type)
    assert.equals("Hi", received.payload.text)
  end)

  it("ignores events whose params are not an object", function()
    local handled = false
    rpc.on_event(function()
      handled = true
    end)

    local ok = pcall(rpc.handle_message, { method = "event", params = true })

    assert.is_true(ok)
    assert.is_false(handled)
  end)

  it("ignores events whose payload is not an object", function()
    local handled = false
    rpc.on_event(function(params)
      handled = true
      return params.payload.text
    end)

    local ok = pcall(rpc.handle_message, {
      method = "event",
      params = { type = "message.delta", payload = true },
    })

    assert.is_true(ok)
    assert.is_false(handled)
  end)

  it("normalizes malformed response errors and releases the pending request", function()
    local request_id
    local received_error
    local results = 0
    process.send = function(frame)
      request_id = frame.id
    end
    rpc.request("test", {}, function()
      results = results + 1
    end, function(err)
      received_error = err
    end)

    local ok = pcall(rpc.handle_message, { id = request_id, error = true })
    rpc.handle_message({ id = request_id, result = "late result" })

    assert.is_true(ok)
    assert.is_table(received_error)
    assert.equals(-32603, received_error.code)
    assert.matches("malformed JSON%-RPC", received_error.message)
    assert.equals(0, results)
  end)

  it("accepts scalar JSON-RPC result payloads", function()
    local request_id
    local received_result
    process.send = function(frame)
      request_id = frame.id
    end
    rpc.request("test", {}, function(result)
      received_result = result
    end)

    rpc.handle_message({ id = request_id, result = true })

    assert.is_true(received_result)
  end)

  it("forwards sequence duplicates for the machine to decide", function()
    local count = 0
    rpc.on_event(function()
      count = count + 1
    end)
    local frame = { method = "event", params = { type = "message.delta", session_id = "live", seq = 1, payload = {} } }
    rpc.handle_message(frame)
    rpc.handle_message(frame)
    assert.equals(2, count)
  end)

  it("rejects event-specific receiver registration", function()
    local ok, err = pcall(rpc.on_event, "message.delta", function() end)

    assert.is_false(ok)
    assert.matches("one general event receiver", err)
  end)
end)

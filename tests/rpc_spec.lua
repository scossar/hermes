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

  it("ignores events whose params are not an object", function()
    local handled = false
    rpc.on_event("message.delta", function()
      handled = true
    end)

    local ok = pcall(rpc.handle_message, { method = "event", params = true })

    assert.is_true(ok)
    assert.is_false(handled)
  end)

  it("ignores events whose payload is not an object", function()
    local handled = false
    rpc.on_event("message.delta", function(params)
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
end)

local function load_runtime()
  local ok, runtime = pcall(require, "hermes.runtime")
  assert.is_true(ok)
  return runtime
end

describe("Neovim Hermes effect runtime", function()
  it("returns RPC failures with the same correlation envelope", function()
    local on_error
    local dispatched
    local runtime = load_runtime().new({
      process = {},
      rpc = {
        on_event = function() end,
        request = function(_, _, _, failure)
          on_error = failure
        end,
      },
      dispatch = function(event)
        dispatched = event
      end,
    })

    runtime:run({
      type = "rpc.request",
      operation_id = 9,
      method = "prompt.submit",
      params = {},
      connection_generation = 2,
      session_generation = 3,
      turn_generation = 4,
    })
    on_error({ code = 500, message = "failed" })

    assert.same({
      type = "operation.failed",
      operation_id = 9,
      connection_generation = 2,
      session_generation = 3,
      turn_generation = 4,
      error = { code = 500, message = "failed" },
      method = "prompt.submit",
    }, dispatched)
  end)

  it("translates session RPC results into semantic activation events", function()
    local on_result
    local dispatched
    local runtime = load_runtime().new({
      process = {},
      rpc = {
        on_event = function() end,
        request = function(_, _, success)
          on_result = success
        end,
      },
      dispatch = function(event)
        dispatched = event
      end,
    })

    runtime:run({
      type = "rpc.request",
      operation_id = 5,
      method = "session.resume",
      params = { session_id = "durable-1" },
      bridge_generation = 1,
      connection_generation = 2,
      session_generation = 3,
    })
    on_result({
      session_id = "live-1",
      session_key = "durable-1",
      messages = { { role = "user", text = "Earlier" } },
    })

    assert.same({
      type = "session.activated",
      operation_id = 5,
      bridge_generation = 1,
      connection_generation = 2,
      session_generation = 3,
      live_id = "live-1",
      durable_id = "durable-1",
      messages = { { role = "user", text = "Earlier" } },
      pending_approval = nil,
      pending_clarification = nil,
    }, dispatched)
  end)

  it("returns RPC results with the effect correlation envelope", function()
    local on_result
    local requested
    local dispatched
    local runtime = load_runtime().new({
      process = {},
      rpc = {
        on_event = function() end,
        request = function(method, params, success)
          requested = { method = method, params = params }
          on_result = success
        end,
      },
      dispatch = function(event)
        dispatched = event
      end,
    })

    runtime:run({
      type = "rpc.request",
      operation_id = 9,
      method = "prompt.submit",
      params = { session_id = "live-1", text = "Hello" },
      connection_generation = 2,
      session_generation = 3,
      turn_generation = 4,
    })
    on_result({ accepted = true })

    assert.same({
      method = "prompt.submit",
      params = { session_id = "live-1", text = "Hello" },
    }, requested)
    assert.same({
      type = "operation.succeeded",
      operation_id = 9,
      connection_generation = 2,
      session_generation = 3,
      turn_generation = 4,
      result = { accepted = true },
    }, dispatched)
  end)

  it("loads only the durable remote session identity from local storage", function()
    local dispatched
    local runtime = load_runtime().new({
      process = {},
      session_store = {
        load = function(path)
          assert.equals("session-store.json", path)
          return "durable-1"
        end,
      },
      session_store_file = "session-store.json",
      dispatch = function(event)
        dispatched = event
      end,
    })

    runtime:run({ type = "session_store.load", bridge_generation = 4, connection_generation = 7 })

    assert.same({
      type = "session_store.loaded",
      bridge_generation = 4,
      connection_generation = 7,
      durable_id = "durable-1",
    }, dispatched)
  end)

  it("normalizes every wire event before dispatching it", function()
    local receiver
    local dispatched
    local rpc = {
      on_event = function(handler)
        receiver = handler
      end,
      handle_message = function() end,
    }
    load_runtime().new({
      process = {},
      rpc = rpc,
      protocol = require("hermes.protocol"),
      dispatch = function(event)
        dispatched = event
      end,
    })

    receiver({
      type = "message.delta",
      session_id = "live-1",
      seq = 3,
      payload = { text = "Hi" },
    })

    assert.same({
      type = "message.delta",
      session_id = "live-1",
      sequence = 3,
      text = "Hi",
    }, dispatched)
  end)

  it("turns bridge callbacks into generation-scoped events", function()
    local dispatched = {}
    local started
    local runtime = load_runtime().new({
      process = {
        start = function(command, on_message, on_exit)
          started = { command = command, on_message = on_message, on_exit = on_exit }
          return true
        end,
      },
      bridge_command = { "node", "bridge.js" },
      dispatch = function(event)
        table.insert(dispatched, event)
      end,
    })

    runtime:run({ type = "bridge.start", bridge_generation = 4, connection_generation = 7 })
    started.on_exit(1)

    assert.same({ "node", "bridge.js" }, started.command)
    assert.same({
      { type = "bridge.started", bridge_generation = 4, connection_generation = 7 },
      { type = "bridge.exited", bridge_generation = 4, connection_generation = 7, code = 1 },
    }, dispatched)
  end)

  it("adds the exact gateway session creation metadata", function()
    local requested
    local runtime = load_runtime().new({
      process = {},
      rpc = {
        on_event = function() end,
        request = function(method, params)
          requested = { method = method, params = params }
        end,
      },
      request_context = function()
        return { cols = 132, cwd = "/repo", source = "hermes.nvim", title = "hermes.nvim session" }
      end,
      dispatch = function() end,
    })

    runtime:run({ type = "rpc.request", method = "session.create", params = {}, operation_id = 1 })

    assert.same({
      method = "session.create",
      params = { cols = 132, cwd = "/repo", source = "hermes.nvim", title = "hermes.nvim session" },
    }, requested)
  end)

  it("reports replacement persistence success and failure back to the machine", function()
    local dispatched = {}
    local should_succeed = false
    local runtime = load_runtime().new({
      process = {},
      session_store = {
        save = function(path, durable_id)
          assert.equals("session-store.json", path)
          assert.equals("durable-2", durable_id)
          if should_succeed then
            return true
          end
          return false, "permission denied"
        end,
      },
      session_store_file = "session-store.json",
      dispatch = function(event)
        table.insert(dispatched, event)
      end,
    })
    local effect = {
      type = "session_store.save",
      durable_id = "durable-2",
      operation_id = 7,
      session_generation = 3,
      replacement = true,
    }

    runtime:run(effect)
    should_succeed = true
    runtime:run(effect)

    assert.same({
      {
        type = "session_store.save_failed",
        operation_id = 7,
        session_generation = 3,
        replacement = true,
        error = "permission denied",
      },
      {
        type = "session_store.saved",
        operation_id = 7,
        session_generation = 3,
        replacement = true,
      },
    }, dispatched)
  end)

  it("turns malformed session success payloads into correlated failures", function()
    local success
    local dispatched
    local runtime = load_runtime().new({
      process = {},
      rpc = {
        on_event = function() end,
        request = function(_, _, callback)
          success = callback
        end,
      },
      dispatch = function(event)
        dispatched = event
      end,
    })
    runtime:run({
      type = "rpc.request",
      method = "session.create",
      params = {},
      operation_id = 4,
      bridge_generation = 1,
      connection_generation = 2,
      session_generation = 3,
    })

    assert.is_true(pcall(success, { session_id = "live-1" }))
    assert.same({
      type = "operation.failed",
      operation_id = 4,
      method = "session.create",
      bridge_generation = 1,
      connection_generation = 2,
      session_generation = 3,
      error = { code = -32603, message = "session response omitted its durable id" },
    }, dispatched)
  end)

  it("closes the live gateway session before stopping the bridge", function()
    local success
    local stopped = false
    local runtime = load_runtime().new({
      process = {
        stop = function()
          stopped = true
        end,
      },
      rpc = {
        on_event = function() end,
        request = function(method, params, callback)
          assert.equals("session.close", method)
          assert.same({ session_id = "live-1" }, params)
          success = callback
        end,
      },
      dispatch = function() end,
    })

    runtime:run({ type = "bridge.close_session", session_id = "live-1" })
    assert.is_false(stopped)
    success({})
    assert.is_true(stopped)
  end)
end)

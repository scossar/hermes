local function load_application()
  package.loaded["hermes.application"] = nil
  local ok, application = pcall(require, "hermes.application")
  assert.is_true(ok)
  return application
end

describe("production Hermes application", function()
  it("drives bridge, canonical hydration, prompt streaming, and completion through one controller", function()
    local requests = {}
    local receiver
    local projection_calls = {}
    local accepted
    local rpc = {
      on_event = function(handler)
        receiver = handler
      end,
      handle_message = function() end,
      request = function(method, params, success, failure)
        table.insert(requests, { method = method, params = params, success = success, failure = failure })
      end,
    }
    local app = load_application().new({
      process = {
        start = function()
          return true
        end,
        stop = function() end,
      },
      rpc = rpc,
      session_store = {
        load = function()
          return nil
        end,
        save = function()
          return true
        end,
      },
      protocol = require("hermes.protocol"),
      projection = {
        show = function()
          table.insert(projection_calls, "show")
        end,
        hydrate = function(messages)
          table.insert(projection_calls, { "hydrate", messages })
        end,
        append_user = function(text)
          table.insert(projection_calls, { "user", text })
        end,
        begin_assistant = function()
          table.insert(projection_calls, "begin")
        end,
        append_delta = function(text)
          table.insert(projection_calls, { "delta", text })
        end,
        finish = function(effect)
          table.insert(projection_calls, { "finish", effect.status, effect.text })
        end,
        clear_for_new_session = function() end,
      },
      agent_events = { begin_turn = function() end, end_turn = function() end, render = function() end },
      interaction = { invalidate = function() end },
      state_file = "state.json",
      bridge_command = { "node", "bridge.js" },
      request_context = function()
        return { cols = 100, cwd = "/repo", source = "hermes.nvim", title = "hermes.nvim session" }
      end,
    })

    app:open()
    assert.equals("session.create", requests[1].method)
    assert.same(
      { cols = 100, cwd = "/repo", source = "hermes.nvim", title = "hermes.nvim session" },
      requests[1].params
    )
    requests[1].success({
      session_id = "live-1",
      stored_session_id = "durable-1",
      messages = { { role = "assistant", text = "Earlier" } },
    })

    assert.is_true(app:submit("Hello", {
      on_accept = function(value)
        accepted = value
      end,
    }))
    assert.equals("prompt.submit", requests[2].method)
    requests[2].success({ accepted = true })
    receiver({ type = "message.delta", session_id = "live-1", seq = 1, payload = { text = "Hi" } })
    receiver({
      type = "message.complete",
      session_id = "live-1",
      seq = 2,
      payload = { status = "complete", text = "Hi" },
    })

    assert.is_true(accepted)
    assert.same({
      "show",
      { "hydrate", { { role = "assistant", text = "Earlier" } } },
      { "user", "Hello" },
      "begin",
      { "delta", "Hi" },
      { "finish", "complete", "Hi" },
    }, projection_calls)
    assert.equals("idle", app:model().turn.phase)
  end)
end)

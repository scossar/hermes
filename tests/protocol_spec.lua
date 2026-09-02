local function load_protocol()
  local ok, protocol = pcall(require, "hermes.protocol")
  assert.is_true(ok)
  return protocol
end

describe("Hermes protocol adapter", function()
  it("normalizes terminal wire messages without leaking wire payload structure", function()
    local event = load_protocol().to_event({
      type = "message.complete",
      session_id = "live-1",
      seq = 12,
      payload = {
        status = "error",
        text = "Partial answer",
        error = "provider failed",
        partial = true,
        recoverable = true,
      },
    })

    assert.same({
      type = "message.completed",
      session_id = "live-1",
      sequence = 12,
      status = "error",
      text = "Partial answer",
      error = "provider failed",
      partial = true,
      recoverable = true,
    }, event)
  end)

  it("normalizes streamed message deltas", function()
    local event = load_protocol().to_event({
      type = "message.delta",
      session_id = "live-1",
      seq = 11,
      payload = { text = "Hello" },
    })

    assert.same({
      type = "message.delta",
      session_id = "live-1",
      sequence = 11,
      text = "Hello",
    }, event)
  end)

  it("normalizes blocking interactions into domain events", function()
    local approval = load_protocol().to_event({
      type = "approval.request",
      session_id = "live-1",
      seq = 13,
      payload = { request_id = "approval-1", command = "do thing" },
    })
    local clarification = load_protocol().to_event({
      type = "clarify.request",
      session_id = "live-1",
      seq = 14,
      payload = { request_id = "clarify-1", question = "Which?" },
    })

    assert.equals("approval.requested", approval.type)
    assert.equals("approval-1", approval.request_id)
    assert.equals("do thing", approval.request.command)
    assert.equals("clarification.requested", clarification.type)
    assert.equals("clarify-1", clarification.request_id)
    assert.equals("Which?", clarification.request.question)
  end)

  it("keeps malformed clarification batches observable without producing an unsafe domain event", function()
    local event = load_protocol().to_event({
      type = "clarify.request",
      session_id = "live-1",
      seq = 15,
      payload = { request_id = "clarify-1", questions = { "not-an-object" } },
    })

    assert.same({
      type = "protocol.unknown",
      wire_type = "clarify.request",
      session_id = "live-1",
      sequence = 15,
      payload = { request_id = "clarify-1", questions = { "not-an-object" } },
    }, event)
  end)

  it("normalizes passive agent activity with stable tool identity", function()
    local event = load_protocol().to_event({
      type = "tool.progress",
      session_id = "live-1",
      seq = 14,
      payload = { tool_id = "tool-7", name = "web_search", preview = "working" },
    })

    assert.same({
      type = "agent_activity.received",
      session_id = "live-1",
      sequence = 14,
      activity_type = "tool.progress",
      payload = { tool_id = "tool-7", name = "web_search", preview = "working" },
    }, event)
  end)

  it("keeps unsupported wire events observable as safe unknown events", function()
    assert.same(
      {
        type = "protocol.unknown",
        wire_type = "sudo.request",
        session_id = "live-1",
        sequence = 15,
        payload = { request_id = "sudo-1" },
      },
      load_protocol().to_event({
        type = "sudo.request",
        session_id = "live-1",
        seq = 15,
        payload = { request_id = "sudo-1" },
      })
    )
  end)
end)

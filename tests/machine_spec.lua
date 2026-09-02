local function load_machine()
  local ok, machine = pcall(require, "hermes.machine")
  assert.is_true(ok)
  return machine
end

local function active_machine()
  local machine = load_machine().new()
  machine:dispatch({ type = "client.open_requested" })
  machine:dispatch({ type = "bridge.started", bridge_generation = 1 })
  machine:dispatch({
    type = "session_store.loaded",
    bridge_generation = 1,
    connection_generation = 1,
    durable_id = "durable-1",
  })
  machine:dispatch({
    type = "session.activated",
    bridge_generation = 1,
    connection_generation = 1,
    session_generation = 1,
    operation_id = 1,
    live_id = "live-1",
    durable_id = "durable-1",
    messages = {},
  })
  machine:dispatch({ type = "session_store.saved", operation_id = 1, session_generation = 1, activation = true })
  machine:dispatch({
    type = "projection.hydrated",
    projection_generation = 1,
    session_generation = 1,
    session_id = "live-1",
  })
  return machine
end

describe("portable Hermes client machine", function()
  it("fails a queued prompt and stops the bridge when session activation fails", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })
    machine:dispatch({ type = "bridge.started", bridge_generation = 1 })
    machine:dispatch({
      type = "session_store.loaded",
      bridge_generation = 1,
      connection_generation = 1,
    })

    local result = machine:dispatch({
      type = "operation.failed",
      operation_id = 1,
      method = "session.create",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      error = { message = "not connected" },
    })

    assert.is_true(result.accepted)
    assert.equals("stopping", machine.model.bridge.phase)
    assert.equals("disconnecting", machine.model.connection.phase)
    assert.equals("none", machine.model.session.phase)
    assert.equals("unhydrated", machine.model.projection.phase)
    assert.equals("idle", machine.model.turn.phase)
    assert.same({
      { type = "submission.settle", submission_id = "submission-1", accepted = false },
      { type = "projection.finish", status = "session_error", error = "not connected", delimiter = false },
      { type = "bridge.stop", bridge_generation = 1 },
    }, result.effects)
  end)

  it("starts a queued prompt only after canonical history is hydrated", function()
    local machine = load_machine().new()
    machine:dispatch({
      type = "prompt.submitted",
      submission_id = "submission-1",
      text = "Hello",
      presentation = { selection = false, delimiter = false },
    })
    machine:dispatch({ type = "bridge.started", bridge_generation = 1 })
    machine:dispatch({
      type = "session_store.loaded",
      bridge_generation = 1,
      connection_generation = 1,
    })

    local result = machine:dispatch({
      type = "session.activated",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      operation_id = 1,
      live_id = "live-1",
      durable_id = "durable-1",
      messages = { { role = "assistant", text = "Earlier" } },
    })

    assert.equals("queued", machine.model.turn.phase)
    assert.equals("session_store.save", result.effects[1].type)
    machine:dispatch({ type = "session_store.saved", operation_id = 1, session_generation = 1, activation = true })
    local hydrated = machine:dispatch({
      type = "projection.hydrated",
      projection_generation = 1,
      session_generation = 1,
      session_id = "live-1",
    })
    assert.equals("submitting", machine.model.turn.phase)
    assert.equals("rpc.request", hydrated.effects[#hydrated.effects].type)
  end)

  it("queues one prompt while the client establishes and hydrates a session", function()
    local machine = load_machine().new()

    local result = machine:dispatch({
      type = "prompt.submitted",
      submission_id = "submission-1",
      text = "Hello",
      presentation = { selection = false, delimiter = false },
    })

    assert.is_true(result.accepted)
    assert.equals("queued", machine.model.turn.phase)
    assert.same({
      submission_id = "submission-1",
      text = "Hello",
      presentation = { selection = false, delimiter = false },
    }, machine.model.turn.request)
    assert.same({
      { type = "projection.show" },
      {
        type = "bridge.start",
        bridge_generation = 1,
        connection_generation = 1,
      },
    }, result.effects)
  end)

  it("starts with independent bridge, connection, session, projection, turn, and interaction regions", function()
    local machine = load_machine().new()

    assert.same({ phase = "stopped", generation = 0 }, machine.model.bridge)
    assert.same({ phase = "disconnected", generation = 0 }, machine.model.connection)
    assert.same({
      phase = "none",
      generation = 0,
      live_id = nil,
      durable_id = nil,
      operation_id = nil,
      last_sequence = 0,
    }, machine.model.session)
    assert.same({ phase = "unhydrated", generation = 0, session_id = nil }, machine.model.projection)
    assert.same({
      phase = "idle",
      generation = 0,
      session_id = nil,
      submission_id = nil,
      operation_id = nil,
      delimiter = false,
      request = nil,
    }, machine.model.turn)
    assert.same({
      phase = "none",
      generation = 0,
      session_id = nil,
      request_id = nil,
      request = nil,
      operation_id = nil,
      question_index = nil,
      answers = nil,
      pending_answer = nil,
      cancelled = false,
    }, machine.model.interaction)
  end)

  it("starts the bridge before resolving a remote session", function()
    local machine = load_machine().new()

    local result = machine:dispatch({ type = "client.open_requested" })

    assert.is_true(result.accepted)
    assert.equals("starting", machine.model.bridge.phase)
    assert.equals(1, machine.model.bridge.generation)
    assert.equals("connecting", machine.model.connection.phase)
    assert.equals(1, machine.model.connection.generation)
    assert.equals("unhydrated", machine.model.projection.phase)
    assert.same({
      {
        type = "bridge.start",
        bridge_generation = 1,
        connection_generation = 1,
      },
      { type = "projection.show" },
    }, result.effects)
  end)

  it("resolves the durable session only for the current bridge incarnation", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "client.open_requested" })

    local stale = machine:dispatch({ type = "bridge.started", bridge_generation = 0 })
    local current = machine:dispatch({ type = "bridge.started", bridge_generation = 1 })

    assert.is_false(stale.accepted)
    assert.same({}, stale.effects)
    assert.is_true(current.accepted)
    assert.equals("running", machine.model.bridge.phase)
    assert.same({
      {
        type = "session_store.load",
        bridge_generation = 1,
        connection_generation = 1,
      },
    }, current.effects)
  end)

  it("resumes a durable session with a correlated operation", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "client.open_requested" })
    machine:dispatch({ type = "bridge.started", bridge_generation = 1 })

    local result = machine:dispatch({
      type = "session_store.loaded",
      bridge_generation = 1,
      connection_generation = 1,
      durable_id = "durable-1",
    })

    assert.is_true(result.accepted)
    assert.equals("resuming", machine.model.session.phase)
    assert.equals(1, machine.model.session.generation)
    assert.equals("durable-1", machine.model.session.durable_id)
    assert.same({
      {
        type = "rpc.request",
        operation_id = 1,
        method = "session.resume",
        params = { session_id = "durable-1" },
        bridge_generation = 1,
        connection_generation = 1,
        session_generation = 1,
      },
    }, result.effects)
  end)

  it("activates and hydrates only the current session operation", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "client.open_requested" })
    machine:dispatch({ type = "bridge.started", bridge_generation = 1 })
    machine:dispatch({
      type = "session_store.loaded",
      bridge_generation = 1,
      connection_generation = 1,
      durable_id = "durable-1",
    })

    local result = machine:dispatch({
      type = "session.activated",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      operation_id = 1,
      live_id = "live-1",
      durable_id = "durable-1",
      messages = { { role = "user", text = "Earlier" } },
    })

    assert.is_true(result.accepted)
    assert.equals("connecting", machine.model.connection.phase)
    assert.equals("persisting_activation", machine.model.session.phase)
    assert.equals("live-1", machine.model.session.live_id)
    assert.equals("unhydrated", machine.model.projection.phase)
    assert.equals("session_store.save", result.effects[1].type)
    local saved =
      machine:dispatch({ type = "session_store.saved", operation_id = 1, session_generation = 1, activation = true })
    assert.equals("hydrating", machine.model.projection.phase)
    assert.equals("projection.hydrate", saved.effects[1].type)
    machine:dispatch({
      type = "projection.hydrated",
      projection_generation = 1,
      session_generation = 1,
      session_id = "live-1",
    })
    assert.equals("ready", machine.model.connection.phase)
    assert.equals("ready", machine.model.projection.phase)
  end)

  it("submits a prompt through effects and records its correlation identity", function()
    local machine = active_machine()

    local result = machine:dispatch({
      type = "prompt.submitted",
      submission_id = "submission-1",
      text = "Hello",
      presentation = { selection = false, delimiter = false },
    })

    assert.is_true(result.accepted)
    assert.equals("submitting", machine.model.turn.phase)
    assert.equals(1, machine.model.turn.generation)
    assert.equals("live-1", machine.model.turn.session_id)
    assert.equals("submission-1", machine.model.turn.submission_id)
    assert.same({
      { type = "projection.append_user", text = "Hello" },
      { type = "projection.begin_assistant" },
      { type = "agent_events.begin_turn" },
      {
        type = "rpc.request",
        operation_id = 2,
        method = "prompt.submit",
        params = { session_id = "live-1", text = "Hello" },
        connection_generation = 1,
        session_generation = 1,
        turn_generation = 1,
      },
    }, result.effects)
  end)

  it("enters the running phase only when the current submission is accepted", function()
    local machine = active_machine()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })

    local stale = machine:dispatch({
      type = "operation.succeeded",
      operation_id = 999,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })
    local current = machine:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })

    assert.is_false(stale.accepted)
    assert.equals("running", machine.model.turn.phase)
    assert.is_true(current.accepted)
    assert.same({ { type = "submission.settle", submission_id = "submission-1", accepted = true } }, current.effects)
  end)

  it("treats a current streamed delta as authoritative prompt acceptance", function()
    local machine = active_machine()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })

    local result = machine:dispatch({
      type = "message.delta",
      session_id = "live-1",
      sequence = 10,
      text = "Hi",
    })

    assert.is_true(result.accepted)
    assert.equals("running", machine.model.turn.phase)
    assert.same({
      { type = "submission.settle", submission_id = "submission-1", accepted = true },
      { type = "projection.append_delta", text = "Hi" },
    }, result.effects)
  end)

  it("finishes the current turn from an authoritative terminal event", function()
    local machine = active_machine()
    machine:dispatch({
      type = "prompt.submitted",
      submission_id = "submission-1",
      text = "Hello",
      presentation = { delimiter = true },
    })
    machine:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })

    local result = machine:dispatch({
      type = "message.completed",
      session_id = "live-1",
      sequence = 11,
      status = "complete",
      text = "Final answer",
    })

    assert.is_true(result.accepted)
    assert.equals("idle", machine.model.turn.phase)
    assert.is_nil(machine.model.turn.session_id)
    assert.same({
      { type = "projection.finish", status = "complete", text = "Final answer", delimiter = true },
      { type = "agent_events.end_turn" },
    }, result.effects)
  end)

  it("settles and resets a rejected prompt operation", function()
    local machine = active_machine()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })

    local result = machine:dispatch({
      type = "operation.failed",
      operation_id = 2,
      method = "prompt.submit",
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
      error = { message = "session busy" },
    })

    assert.is_true(result.accepted)
    assert.equals("idle", machine.model.turn.phase)
    assert.same({
      { type = "submission.settle", submission_id = "submission-1", accepted = false },
      { type = "projection.finish", status = "request_error", error = "session busy", delimiter = false },
      { type = "agent_events.end_turn" },
    }, result.effects)
  end)

  it("forwards ordered activity only while the current turn is active", function()
    local machine = active_machine()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })

    local result = machine:dispatch({
      type = "agent_activity.received",
      session_id = "live-1",
      sequence = 10,
      activity_type = "tool.progress",
      payload = { tool_id = "tool-1" },
    })

    assert.is_true(result.accepted)
    assert.equals("running", machine.model.turn.phase)
    assert.same({
      { type = "submission.settle", submission_id = "submission-1", accepted = true },
      { type = "agent_events.render", activity_type = "tool.progress", payload = { tool_id = "tool-1" } },
    }, result.effects)
  end)

  it("settles only the correlated interaction response", function()
    local machine = active_machine()
    machine:dispatch({
      type = "approval.requested",
      session_id = "live-1",
      sequence = 20,
      request_id = "approval-1",
      request = { request_id = "approval-1" },
    })
    machine:dispatch({
      type = "approval.answered",
      interaction_generation = 1,
      request_id = "approval-1",
      choice = "once",
    })

    local result = machine:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      interaction_generation = 1,
      result = { resolved = 1 },
    })

    assert.is_true(result.accepted)
    assert.equals("none", machine.model.interaction.phase)
    assert.is_nil(machine.model.interaction.request)
    assert.same({}, result.effects)
  end)

  it("correlates an interaction response with the current request generation", function()
    local machine = active_machine()
    machine:dispatch({
      type = "approval.requested",
      session_id = "live-1",
      sequence = 20,
      request_id = "approval-1",
      request = { request_id = "approval-1" },
    })

    local result = machine:dispatch({
      type = "approval.answered",
      interaction_generation = 1,
      request_id = "approval-1",
      choice = "once",
    })

    assert.is_true(result.accepted)
    assert.equals("responding", machine.model.interaction.phase)
    assert.same({
      {
        type = "rpc.request",
        operation_id = 2,
        method = "approval.respond",
        params = { session_id = "live-1", request_id = "approval-1", choice = "once" },
        connection_generation = 1,
        session_generation = 1,
        interaction_generation = 1,
      },
    }, result.effects)
  end)

  it("admits a blocking interaction only for the active session", function()
    local machine = active_machine()

    local stale = machine:dispatch({
      type = "approval.requested",
      session_id = "other-session",
      sequence = 20,
      request_id = "approval-old",
      request = { request_id = "approval-old" },
    })
    local current = machine:dispatch({
      type = "approval.requested",
      session_id = "live-1",
      sequence = 20,
      request_id = "approval-1",
      request = { request_id = "approval-1", command = "do thing" },
    })

    assert.is_false(stale.accepted)
    assert.is_true(current.accepted)
    assert.equals("approval", machine.model.interaction.phase)
    assert.equals(1, machine.model.interaction.generation)
    assert.equals("approval-1", machine.model.interaction.request_id)
    assert.same({
      {
        type = "interaction.show_approval",
        interaction_generation = 1,
        session_id = "live-1",
        request = { request_id = "approval-1", command = "do thing" },
      },
    }, current.effects)
  end)

  it("keeps the old durable identity until a replacement is created and persisted", function()
    local machine = active_machine()

    local requested = machine:dispatch({ type = "client.new_session_requested" })
    assert.equals("replacing", machine.model.session.phase)
    assert.equals("durable-1", machine.model.session.durable_id)
    assert.equals("session.create", requested.effects[1].method)

    local created = machine:dispatch({
      type = "session.replacement_created",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 2,
      live_id = "live-2",
      durable_id = "durable-2",
      messages = {},
    })
    assert.equals("persisting_replacement", machine.model.session.phase)
    assert.equals("durable-1", machine.model.session.durable_id)
    assert.same({
      {
        type = "session_store.save",
        durable_id = "durable-2",
        operation_id = 2,
        session_generation = 2,
        replacement = true,
      },
    }, created.effects)

    machine:dispatch({
      type = "session_store.save_failed",
      operation_id = 2,
      session_generation = 2,
      error = "permission denied",
    })
    assert.equals("active", machine.model.session.phase)
    assert.equals("live-1", machine.model.session.live_id)
    assert.equals("durable-1", machine.model.session.durable_id)
  end)

  it("keeps an interrupted turn busy until its terminal event", function()
    local machine = active_machine()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Long task" })
    machine:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })

    local interrupted = machine:dispatch({ type = "client.interrupt_requested" })
    assert.equals("interrupting", machine.model.turn.phase)
    assert.equals("session.interrupt", interrupted.effects[1].method)

    machine:dispatch({
      type = "operation.succeeded",
      operation_id = 3,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })
    assert.equals("interrupting", machine.model.turn.phase)

    machine:dispatch({
      type = "message.completed",
      session_id = "live-1",
      sequence = 9,
      status = "interrupted",
    })
    assert.equals("idle", machine.model.turn.phase)
  end)

  it("settles an active submission when the current bridge disconnects", function()
    local machine = active_machine()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })

    local result = machine:dispatch({
      type = "bridge.exited",
      bridge_generation = 1,
      connection_generation = 1,
      code = 1,
    })

    assert.equals("stopped", machine.model.bridge.phase)
    assert.equals("disconnected", machine.model.connection.phase)
    assert.equals("none", machine.model.session.phase)
    assert.equals("idle", machine.model.turn.phase)
    assert.same({
      { type = "submission.settle", submission_id = "submission-1", accepted = false },
      { type = "projection.finish", status = "disconnected", delimiter = false },
      { type = "agent_events.end_turn" },
      { type = "interaction.invalidate" },
      { type = "notify", level = "error", message = "bridge disconnected" },
    }, result.effects)
  end)

  it("restores a pending interaction returned with canonical session history", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "client.open_requested" })
    machine:dispatch({ type = "bridge.started", bridge_generation = 1 })
    machine:dispatch({ type = "session_store.loaded", bridge_generation = 1, connection_generation = 1 })

    machine:dispatch({
      type = "session.activated",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      operation_id = 1,
      live_id = "live-1",
      durable_id = "durable-1",
      messages = {},
      pending_approval = { request_id = "approval-1", command = "do thing" },
    })
    machine:dispatch({ type = "session_store.saved", operation_id = 1, session_generation = 1, activation = true })
    local result = machine:dispatch({
      type = "projection.hydrated",
      projection_generation = 1,
      session_generation = 1,
      session_id = "live-1",
    })

    assert.equals("approval", machine.model.interaction.phase)
    assert.equals("approval-1", machine.model.interaction.request_id)
    assert.same({
      type = "interaction.show_approval",
      interaction_generation = 1,
      session_id = "live-1",
      request = { request_id = "approval-1", command = "do thing" },
    }, result.effects[#result.effects])
  end)

  it("clears a stale durable resume before creating a replacement", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "client.open_requested" })
    machine:dispatch({ type = "bridge.started", bridge_generation = 1 })
    machine:dispatch({
      type = "session_store.loaded",
      bridge_generation = 1,
      connection_generation = 1,
      durable_id = "stale-id",
    })

    local failed = machine:dispatch({
      type = "operation.failed",
      operation_id = 1,
      method = "session.resume",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      error = { code = 4007, message = "session not found" },
    })
    assert.equals("clearing_stale", machine.model.session.phase)
    assert.equals("stale-id", machine.model.session.durable_id)
    assert.same({
      type = "session_store.clear",
      operation_id = 1,
      session_generation = 1,
    }, failed.effects[1])

    local cleared = machine:dispatch({
      type = "session_store.cleared",
      operation_id = 1,
      session_generation = 1,
    })
    assert.equals("creating", machine.model.session.phase)
    assert.is_nil(machine.model.session.durable_id)
    assert.equals("session.create", cleared.effects[1].method)
  end)

  it("settles a queued prompt when the bridge cannot start", function()
    local machine = load_machine().new()
    machine:dispatch({ type = "prompt.submitted", submission_id = "submission-1", text = "Hello" })
    local result = machine:dispatch({
      type = "bridge.start_failed",
      bridge_generation = 1,
      connection_generation = 1,
      error = "could not start bridge process",
    })
    assert.equals("stopped", machine.model.bridge.phase)
    assert.equals("idle", machine.model.turn.phase)
    assert.same({
      { type = "submission.settle", submission_id = "submission-1", accepted = false },
      {
        type = "projection.finish",
        status = "session_error",
        error = "could not start bridge process",
        delimiter = false,
      },
    }, result.effects)
  end)

  it("recovers from a failed interaction response", function()
    local machine = active_machine()
    machine:dispatch({
      type = "approval.requested",
      session_id = "live-1",
      sequence = 20,
      request_id = "approval-1",
      request = { request_id = "approval-1" },
    })
    machine:dispatch({
      type = "approval.answered",
      interaction_generation = 1,
      request_id = "approval-1",
      choice = "once",
    })
    local result = machine:dispatch({
      type = "operation.failed",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      interaction_generation = 1,
      error = { message = "expired" },
    })
    assert.equals("none", machine.model.interaction.phase)
    assert.same(
      { type = "notify", level = "error", message = "interaction response failed: expired" },
      result.effects[1]
    )
  end)
end)

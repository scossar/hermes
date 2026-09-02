local machine = require("hermes.machine")
local controller = require("hermes.controller")
local runtime = require("hermes.runtime")

local function activation_subject(options)
  options = options or {}
  local subject = machine.new()
  subject:dispatch({ type = "client.open_requested" })
  subject:dispatch({ type = "bridge.started", bridge_generation = 1, connection_generation = 1 })
  subject:dispatch({
    type = "session_store.loaded",
    bridge_generation = 1,
    connection_generation = 1,
    durable_id = options.durable_id,
  })
  local activated = subject:dispatch({
    type = "session.activated",
    bridge_generation = 1,
    connection_generation = 1,
    session_generation = 1,
    operation_id = 1,
    live_id = "live-1",
    durable_id = options.durable_id or "durable-1",
    messages = options.messages or {},
    pending_clarification = options.pending_clarification,
    pending_approval = options.pending_approval,
  })
  return subject, activated
end

local function ready_machine(options)
  local subject = activation_subject(options)
  subject:dispatch({
    type = "session_store.saved",
    operation_id = 1,
    session_generation = 1,
    activation = true,
  })
  subject:dispatch({
    type = "projection.hydrated",
    projection_generation = 1,
    session_generation = 1,
    session_id = "live-1",
  })
  return subject
end

local function effect_types(effects)
  local result = {}
  for _, effect in ipairs(effects) do
    table.insert(result, effect.type)
  end
  return result
end

describe("independent review blockers", function()
  it("rejects replacement while a blocking interaction is open or responding", function()
    local pending = { request_id = "a1", command = "run" }
    local waiting = ready_machine({ pending_approval = pending })
    assert.is_false(waiting:dispatch({ type = "client.new_session_requested" }).accepted)
    assert.equals("approval", waiting.model.interaction.phase)
    assert.equals(1, waiting.model.session.generation)

    waiting:dispatch({
      type = "approval.answered",
      interaction_generation = 1,
      request_id = "a1",
      choice = "once",
    })
    assert.equals("responding", waiting.model.interaction.phase)
    assert.is_false(waiting:dispatch({ type = "client.new_session_requested" }).accepted)
    assert.equals(1, waiting.model.session.generation)
  end)

  it("rejects malformed clarification questions without mutating state", function()
    local subject = ready_machine()
    local before = vim.deepcopy(subject.model)
    local ok, result = pcall(function()
      return subject:dispatch({
        type = "clarification.requested",
        session_id = "live-1",
        sequence = 1,
        request_id = "c1",
        request = { request_id = "c1", questions = { 1 } },
      })
    end)
    assert.is_true(ok)
    assert.is_false(result.accepted)
    assert.same(before, subject.model)
  end)

  it("fails activation safely when resumed clarification data is malformed", function()
    local subject, result = activation_subject({
      pending_clarification = { request_id = "c1", questions = { 1 } },
    })

    assert.is_true(result.accepted)
    assert.equals("stopping", subject.model.bridge.phase)
    assert.equals("disconnecting", subject.model.connection.phase)
    assert.equals("none", subject.model.session.phase)
    assert.equals("none", subject.model.interaction.phase)
    assert.same({
      {
        type = "notify",
        level = "error",
        message = "could not activate session: malformed activation payload",
      },
      { type = "bridge.close_session", session_id = "live-1" },
    }, result.effects)
  end)

  it("keeps activity rendering active until interrupted turn completion", function()
    local subject = ready_machine()
    subject:dispatch({ type = "prompt.submitted", submission_id = "s1", text = "hello" })
    subject:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })
    local result = subject:dispatch({ type = "client.interrupt_requested" })
    assert.same({ "rpc.request", "interaction.invalidate" }, effect_types(result.effects))
  end)

  it("stays stopping until process exit and rejects an immediate reopen", function()
    local subject = ready_machine()
    local stopped = subject:dispatch({ type = "client.stop_requested" })
    assert.is_true(stopped.accepted)
    assert.equals("stopping", subject.model.bridge.phase)
    assert.equals("disconnecting", subject.model.connection.phase)
    assert.is_false(subject:dispatch({ type = "client.open_requested" }).accepted)

    local exited = subject:dispatch({
      type = "bridge.exited",
      bridge_generation = 1,
      connection_generation = 1,
    })
    assert.is_true(exited.accepted)
    assert.equals("stopped", subject.model.bridge.phase)
    assert.same({}, exited.effects)
  end)

  it("keeps open idempotent after the session is ready", function()
    local subject = ready_machine()
    local result = subject:dispatch({ type = "client.open_requested" })
    assert.is_true(result.accepted)
    assert.equals("ready", subject.model.projection.phase)
    assert.same({ { type = "projection.show" } }, result.effects)
  end)

  it("persists initial identity before readiness and hydration", function()
    local subject, activated = activation_subject({ messages = { { role = "assistant", text = "old" } } })
    assert.equals("persisting_activation", subject.model.session.phase)
    assert.equals("connecting", subject.model.connection.phase)
    assert.equals("unhydrated", subject.model.projection.phase)
    assert.same({
      {
        type = "session_store.save",
        durable_id = "durable-1",
        operation_id = 1,
        session_generation = 1,
        activation = true,
      },
    }, activated.effects)

    local saved = subject:dispatch({
      type = "session_store.saved",
      operation_id = 1,
      session_generation = 1,
      activation = true,
    })
    assert.equals("active", subject.model.session.phase)
    assert.equals("hydrating", subject.model.projection.phase)
    assert.same({
      {
        type = "projection.hydrate",
        messages = { { role = "assistant", text = "old" } },
        projection_generation = 1,
        session_generation = 1,
        session_id = "live-1",
      },
    }, saved.effects)
  end)

  it("fails queued work and closes a newly activated session when persistence fails", function()
    local subject = machine.new()
    subject:dispatch({ type = "prompt.submitted", submission_id = "s1", text = "hello" })
    subject:dispatch({ type = "bridge.started", bridge_generation = 1, connection_generation = 1 })
    subject:dispatch({ type = "session_store.loaded", bridge_generation = 1, connection_generation = 1 })
    subject:dispatch({
      type = "session.activated",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      operation_id = 1,
      live_id = "live-new",
      durable_id = "durable-new",
      messages = {},
    })
    local failed = subject:dispatch({
      type = "session_store.save_failed",
      operation_id = 1,
      session_generation = 1,
      activation = true,
      error = "denied",
    })
    assert.equals("stopping", subject.model.bridge.phase)
    assert.equals(0, subject.model.session.last_sequence)
    assert.same({
      "submission.settle",
      "projection.finish",
      "notify",
      "bridge.close_session",
    }, effect_types(failed.effects))
  end)

  it("waits for correlated hydration before starting queued work", function()
    local subject = machine.new()
    subject:dispatch({ type = "prompt.submitted", submission_id = "s1", text = "hello" })
    subject:dispatch({ type = "bridge.started", bridge_generation = 1, connection_generation = 1 })
    subject:dispatch({ type = "session_store.loaded", bridge_generation = 1, connection_generation = 1 })
    subject:dispatch({
      type = "session.activated",
      bridge_generation = 1,
      connection_generation = 1,
      session_generation = 1,
      operation_id = 1,
      live_id = "live-1",
      durable_id = "durable-1",
      messages = {},
    })
    local saved =
      subject:dispatch({ type = "session_store.saved", operation_id = 1, session_generation = 1, activation = true })
    assert.equals("queued", subject.model.turn.phase)
    assert.same({ "projection.hydrate" }, effect_types(saved.effects))
    assert.is_false(subject:dispatch({
      type = "projection.hydrated",
      projection_generation = 0,
      session_generation = 1,
      session_id = "live-1",
    }).accepted)
    local hydrated = subject:dispatch({
      type = "projection.hydrated",
      projection_generation = 1,
      session_generation = 1,
      session_id = "live-1",
    })
    assert.equals("submitting", subject.model.turn.phase)
    assert.same(
      { "projection.append_user", "projection.begin_assistant", "agent_events.begin_turn", "rpc.request" },
      effect_types(hydrated.effects)
    )
  end)

  it("recovers controller dispatching and preserves queued events when an effect throws", function()
    local fail = true
    local subject
    subject = controller.new({
      machine = machine.new(),
      run_effect = function(effect)
        if effect.type == "bridge.start" and fail then
          fail = false
          subject:dispatch({ type = "bridge.started", bridge_generation = 1, connection_generation = 1 })
          error("effect exploded")
        end
      end,
    })
    assert.is_false(pcall(function()
      subject:dispatch({ type = "client.open_requested" })
    end))
    assert.is_false(subject.dispatching)
    assert.is_true(subject:dispatch({ type = "client.open_requested" }).accepted)
    assert.equals("running", subject:model().bridge.phase)
  end)

  it("lets interrupt failure return to running and accepts ordered streaming while interrupting", function()
    local subject = ready_machine()
    subject:dispatch({ type = "prompt.submitted", submission_id = "s1", text = "hello" })
    subject:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })
    subject:dispatch({ type = "client.interrupt_requested" })
    local delta =
      subject:dispatch({ type = "message.delta", session_id = "live-1", sequence = 1, text = "still arriving" })
    assert.is_true(delta.accepted)
    local failed = subject:dispatch({
      type = "operation.failed",
      method = "session.interrupt",
      operation_id = 3,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
      error = { message = "temporary" },
    })
    assert.equals("running", subject.model.turn.phase)
    assert.same({ { type = "notify", level = "error", message = "interrupt failed: temporary" } }, failed.effects)
    assert.is_true(subject:dispatch({ type = "client.interrupt_requested" }).accepted)
  end)

  it("advances sequence for unknown events only in the active session", function()
    local subject = ready_machine()
    local current =
      subject:dispatch({ type = "protocol.unknown", session_id = "live-1", sequence = 7, wire_type = "future.event" })
    assert.is_true(current.accepted)
    assert.equals(7, subject.model.session.last_sequence)
    assert.same({}, current.effects)
    assert.is_false(subject:dispatch({ type = "protocol.unknown", session_id = "other", sequence = 8 }).accepted)
  end)

  it("settles replacement on stop and bridge exit and resets the sequence watermark", function()
    for _, terminal_event in ipairs({
      { type = "client.stop_requested" },
      { type = "bridge.exited", bridge_generation = 1, connection_generation = 1 },
    }) do
      local subject = ready_machine()
      subject.model.session.last_sequence = 44
      subject:dispatch({ type = "client.new_session_requested" })
      local result = subject:dispatch(terminal_event)
      assert.equals(0, subject.model.session.last_sequence)
      assert.same("session_transition.settle", result.effects[1].type)
      assert.is_false(result.effects[1].accepted)
    end
  end)

  it("closes detached sessions when replacement fails or commits", function()
    local failed = ready_machine()
    failed:dispatch({ type = "client.new_session_requested" })
    failed:dispatch({
      type = "session.replacement_created",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 2,
      live_id = "live-2",
      durable_id = "durable-2",
    })
    local failure =
      failed:dispatch({ type = "session_store.save_failed", operation_id = 2, session_generation = 2, error = "no" })
    assert.equals("active", failed.model.session.phase)
    assert.equals("live-1", failed.model.session.live_id)
    assert.equals("session.close_detached", failure.effects[2].type)
    assert.equals("live-2", failure.effects[2].session_id)

    local committed = ready_machine()
    committed:dispatch({ type = "client.new_session_requested" })
    committed:dispatch({
      type = "session.replacement_created",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 2,
      live_id = "live-2",
      durable_id = "durable-2",
    })
    local result =
      committed:dispatch({ type = "session_store.saved", operation_id = 2, session_generation = 2, replacement = true })
    assert.equals("none", committed.model.interaction.phase)
    assert.same({
      "projection.clear_for_new_session",
      "interaction.invalidate",
      "session.close_detached",
      "session_transition.settle",
    }, effect_types(result.effects))
    assert.equals("live-1", result.effects[3].session_id)
  end)

  it("owns progression through a two-question clarification batch", function()
    local subject = ready_machine()
    local request = {
      request_id = "c1",
      answers = { locked = "given" },
      questions = {
        { qid = "locked", question = "locked" },
        { qid = "q1", question = "first" },
        { qid = "q2", question = "second" },
      },
    }
    local shown = subject:dispatch({
      type = "clarification.requested",
      session_id = "live-1",
      sequence = 1,
      request_id = "c1",
      request = request,
    })
    assert.equals("q1", shown.effects[1].question.qid)
    local answer1 = subject:dispatch({
      type = "clarification.answered",
      interaction_generation = 1,
      request_id = "c1",
      question_id = "q1",
      answer = "one",
    })
    assert.equals("clarify.respond", answer1.effects[1].method)
    local next_question = subject:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      interaction_generation = 1,
      result = { status = "pending" },
    })
    assert.equals("clarification", subject.model.interaction.phase)
    assert.equals("q2", next_question.effects[1].question.qid)
    subject:dispatch({
      type = "clarification.answered",
      interaction_generation = 1,
      request_id = "c1",
      question_id = "q2",
      answer = "two",
    })
    subject:dispatch({
      type = "operation.succeeded",
      operation_id = 3,
      connection_generation = 1,
      session_generation = 1,
      interaction_generation = 1,
      result = { status = "resolved" },
    })
    assert.equals("none", subject.model.interaction.phase)
  end)

  it("sanitizes malformed terminal fields", function()
    local subject = ready_machine()
    subject:dispatch({ type = "prompt.submitted", submission_id = "s", text = "go" })
    local ok, result = pcall(function()
      return subject:dispatch({
        type = "message.completed",
        session_id = "live-1",
        sequence = 1,
        status = {},
        text = true,
        error = { bad = true },
      })
    end)
    assert.is_true(ok)
    assert.same({ type = "projection.finish", status = "complete", delimiter = false }, result.effects[2])
  end)

  it("keeps the transition system independent of Neovim globals", function()
    local subject = ready_machine()
    local original_vim = _G.vim
    _G.vim = nil
    local ok, result = pcall(function()
      return subject:dispatch({ type = "client.new_session_requested" })
    end)
    _G.vim = original_vim
    assert.is_true(ok)
    assert.is_true(result.accepted)
  end)

  it("cancels a clarification batch as one correlated response", function()
    local subject = ready_machine()
    subject:dispatch({
      type = "clarification.requested",
      session_id = "live-1",
      sequence = 1,
      request_id = "c1",
      request = { request_id = "c1", questions = { { qid = "q1" }, { qid = "q2" } } },
    })
    local result = subject:dispatch({
      type = "clarification.answered",
      interaction_generation = 1,
      request_id = "c1",
      question_id = "q1",
      answer = "",
      cancelled = true,
    })
    assert.same({ session_id = "live-1", request_id = "c1", answer = "" }, result.effects[1].params)
    subject:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      interaction_generation = 1,
      result = {},
    })
    assert.equals("none", subject.model.interaction.phase)
  end)
end)

describe("runtime review blockers", function()
  it("dispatches hydration completion and failure with correlation", function()
    local dispatched = {}
    local should_fail = false
    local subject = runtime.new({
      process = {},
      projection = {
        hydrate = function()
          if should_fail then
            error("render failed")
          end
        end,
      },
      dispatch = function(event)
        table.insert(dispatched, event)
      end,
    })
    local effect = {
      type = "projection.hydrate",
      messages = {},
      projection_generation = 4,
      session_generation = 3,
      session_id = "live",
    }
    subject:run(effect)
    should_fail = true
    subject:run(effect)
    assert.equals("projection.hydrated", dispatched[1].type)
    assert.equals("projection.hydration_failed", dispatched[2].type)
    assert.equals(4, dispatched[2].projection_generation)
  end)

  it("reads bridge and state configuration at effect execution time", function()
    local command = { "node", "old.js" }
    local state_file = "old.json"
    local seen = {}
    local subject = runtime.new({
      process = {
        start = function(value)
          seen.command = value
          return true
        end,
      },
      session_store = {
        load = function(value)
          seen.state_file = value
        end,
      },
      bridge_command_provider = function()
        return command
      end,
      state_file_provider = function()
        return state_file
      end,
      dispatch = function() end,
    })
    command = { "node", "new.js" }
    state_file = "new.json"
    subject:run({ type = "bridge.start", bridge_generation = 1, connection_generation = 1 })
    subject:run({ type = "session_store.load", bridge_generation = 1, connection_generation = 1 })
    assert.same({ "node", "new.js" }, seen.command)
    assert.equals("new.json", seen.state_file)
  end)

  it("fails pending RPC state on bridge exit and stop after model reset dispatch", function()
    local exit
    local order = {}
    local subject = runtime.new({
      process = {
        start = function(_, _, callback)
          exit = callback
          return true
        end,
        stop = function()
          table.insert(order, "process.stop")
        end,
      },
      rpc = {
        on_event = function() end,
        fail_pending = function()
          table.insert(order, "fail_pending")
        end,
      },
      dispatch = function(event)
        table.insert(order, event.type)
      end,
    })
    subject:run({ type = "bridge.start", bridge_generation = 1, connection_generation = 1 })
    exit(1)
    subject:run({ type = "bridge.stop" })
    assert.same({ "bridge.started", "bridge.exited", "fail_pending", "fail_pending", "process.stop" }, order)
  end)

  it("closes detached sessions without stopping the bridge", function()
    local stopped = false
    local requested
    local subject = runtime.new({
      process = {
        stop = function()
          stopped = true
        end,
      },
      rpc = {
        on_event = function() end,
        request = function(method, params)
          requested = { method, params }
        end,
      },
      dispatch = function() end,
    })
    subject:run({ type = "session.close_detached", session_id = "abandoned" })
    assert.same({ "session.close", { session_id = "abandoned" } }, requested)
    assert.is_false(stopped)
  end)
end)

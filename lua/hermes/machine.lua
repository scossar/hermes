local M = {}
local Machine = {}
Machine.__index = Machine

local function deep_copy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[deep_copy(key, seen)] = deep_copy(item, seen)
  end
  return copy
end

local function initial_model()
  return {
    bridge = {
      phase = "stopped",
      generation = 0,
    },
    connection = {
      phase = "disconnected",
      generation = 0,
    },
    session = {
      phase = "none",
      generation = 0,
      live_id = nil,
      durable_id = nil,
      operation_id = nil,
      last_sequence = 0,
    },
    projection = {
      phase = "unhydrated",
      generation = 0,
      session_id = nil,
    },
    turn = {
      phase = "idle",
      generation = 0,
      session_id = nil,
      submission_id = nil,
      operation_id = nil,
      delimiter = false,
      request = nil,
    },
    interaction = {
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
    },
  }
end

local function accepted(effects)
  return { accepted = true, effects = effects or {} }
end

local function rejected()
  return { accepted = false, effects = {} }
end

local function reset_turn(turn)
  turn.phase = "idle"
  turn.session_id = nil
  turn.submission_id = nil
  turn.operation_id = nil
  turn.delimiter = false
  turn.request = nil
end

local function reset_interaction(interaction)
  interaction.phase = "none"
  interaction.session_id = nil
  interaction.request_id = nil
  interaction.request = nil
  interaction.operation_id = nil
  interaction.question_index = nil
  interaction.answers = nil
  interaction.pending_answer = nil
  interaction.cancelled = false
end

local function reset_session_runtime(session)
  session.phase = "none"
  session.live_id = nil
  session.operation_id = nil
  session.last_sequence = 0
end

local function reset_projection(projection)
  projection.phase = "unhydrated"
  projection.session_id = nil
end

local function queued_failure(model, effects, status, message)
  if model.turn.phase == "queued" then
    local request = model.turn.request
    table.insert(effects, { type = "submission.settle", submission_id = request.submission_id, accepted = false })
    table.insert(effects, {
      type = "projection.finish",
      status = status,
      error = message,
      delimiter = request.presentation.delimiter == true,
    })
  end
end

local function begin_hydration(self, messages)
  local model = self.model
  model.projection.generation = model.projection.generation + 1
  model.projection.phase = "hydrating"
  model.projection.session_id = model.session.live_id
  local queued_selection = model.turn.phase == "queued"
    and model.turn.request.presentation
    and model.turn.request.presentation.selection == true
  return {
    type = "projection.hydrate",
    messages = messages or {},
    projection_generation = model.projection.generation,
    session_generation = model.session.generation,
    session_id = model.session.live_id,
    preserve_existing = queued_selection and #(messages or {}) == 0 or nil,
  }
end

local function current_sequence(model, event)
  return model.session.phase == "active"
    and event.session_id == model.session.live_id
    and type(event.sequence) == "number"
    and event.sequence > model.session.last_sequence
end

local function clarification_question(interaction)
  local request = interaction.request or {}
  local questions = type(request.questions) == "table" and request.questions or nil
  if not questions or #questions == 0 then
    return request
  end
  local answers = interaction.answers or {}
  local index = interaction.question_index or 1
  while questions[index] and answers[questions[index].qid] ~= nil do
    index = index + 1
  end
  interaction.question_index = index
  return questions[index]
end

local function valid_clarification_request(request)
  if type(request) ~= "table" then
    return false
  end
  if request.questions == nil then
    return true
  end
  if type(request.questions) ~= "table" then
    return false
  end
  for _, question in ipairs(request.questions) do
    if type(question) ~= "table" then
      return false
    end
  end
  return true
end

local function valid_activation_payload(event)
  if event.messages ~= nil then
    if type(event.messages) ~= "table" then
      return false
    end
    for _, message in ipairs(event.messages) do
      if type(message) ~= "table" then
        return false
      end
    end
  end
  if
    event.pending_approval ~= nil
    and (type(event.pending_approval) ~= "table" or event.pending_approval.request_id == nil)
  then
    return false
  end
  if
    event.pending_clarification ~= nil
    and (
      type(event.pending_clarification) ~= "table"
      or event.pending_clarification.request_id == nil
      or not valid_clarification_request(event.pending_clarification)
    )
  then
    return false
  end
  return true
end

local function clarification_effect(interaction)
  local question = clarification_question(interaction)
  if not question then
    return nil
  end
  return {
    type = "interaction.show_clarification",
    interaction_generation = interaction.generation,
    session_id = interaction.session_id,
    request = interaction.request,
    question = question,
  }
end

function Machine:next_operation_id()
  self.operation_sequence = self.operation_sequence + 1
  return self.operation_sequence
end

function Machine:start_turn(request, effects)
  local model = self.model
  local turn = model.turn
  turn.phase = "submitting"
  turn.generation = turn.generation + 1
  turn.session_id = model.session.live_id
  turn.submission_id = request.submission_id
  turn.operation_id = self:next_operation_id()
  turn.delimiter = request.presentation and request.presentation.delimiter == true or false
  turn.request = nil
  if not (request.presentation and request.presentation.selection) then
    table.insert(effects, { type = "projection.append_user", text = request.text })
  end
  table.insert(effects, { type = "projection.begin_assistant" })
  table.insert(effects, { type = "agent_events.begin_turn" })
  table.insert(effects, {
    type = "rpc.request",
    operation_id = turn.operation_id,
    method = "prompt.submit",
    params = { session_id = model.session.live_id, text = request.text },
    connection_generation = model.connection.generation,
    session_generation = model.session.generation,
    turn_generation = turn.generation,
  })
end

function Machine:dispatch(event)
  if event.type == "bridge.start_failed" then
    local model = self.model
    if
      model.bridge.phase ~= "starting"
      or event.bridge_generation ~= model.bridge.generation
      or event.connection_generation ~= model.connection.generation
    then
      return rejected()
    end
    local effects = {}
    if model.turn.phase == "queued" then
      local request = model.turn.request
      table.insert(effects, { type = "submission.settle", submission_id = request.submission_id, accepted = false })
      table.insert(effects, {
        type = "projection.finish",
        status = "session_error",
        error = tostring(event.error or "could not start bridge process"),
        delimiter = request.presentation.delimiter == true,
      })
    end
    model.bridge.phase = "stopped"
    model.connection.phase = "disconnected"
    model.session.phase = "none"
    model.projection.phase = "unhydrated"
    reset_turn(model.turn)
    reset_interaction(model.interaction)
    return accepted(effects)
  elseif event.type == "session_store.clear_failed" then
    local model = self.model
    local session = model.session
    if
      session.phase ~= "clearing_stale"
      or event.operation_id ~= session.operation_id
      or event.session_generation ~= session.generation
    then
      return rejected()
    end
    local message = tostring(event.error or "unknown error")
    local effects = { { type = "notify", level = "error", message = "could not clear stale session: " .. message } }
    if model.turn.phase == "queued" then
      local request = model.turn.request
      table.insert(effects, 1, { type = "submission.settle", submission_id = request.submission_id, accepted = false })
      table.insert(effects, 2, {
        type = "projection.finish",
        status = "session_error",
        error = message,
        delimiter = request.presentation.delimiter == true,
      })
    end
    model.bridge.phase = "stopping"
    model.connection.phase = "disconnecting"
    session.phase = "none"
    session.live_id = nil
    session.operation_id = nil
    model.projection.phase = "unhydrated"
    reset_turn(model.turn)
    table.insert(effects, { type = "bridge.stop", bridge_generation = model.bridge.generation })
    return accepted(effects)
  elseif event.type == "client.stop_requested" then
    local model = self.model
    if model.bridge.phase == "stopped" or model.bridge.phase == "stopping" then
      return accepted()
    end
    local effects = {}
    if model.session.phase == "replacing" or model.session.phase == "persisting_replacement" then
      table.insert(effects, { type = "session_transition.settle", accepted = false, error = "stopped" })
    end
    if model.turn.phase ~= "idle" then
      local submission_id = model.turn.submission_id or (model.turn.request and model.turn.request.submission_id)
      table.insert(effects, { type = "submission.settle", submission_id = submission_id, accepted = false })
      table.insert(effects, { type = "projection.finish", status = "stopped", delimiter = model.turn.delimiter })
      table.insert(effects, { type = "agent_events.end_turn" })
    end
    table.insert(effects, { type = "interaction.invalidate" })
    if model.session.live_id then
      table.insert(effects, { type = "bridge.close_session", session_id = model.session.live_id })
    else
      table.insert(effects, { type = "bridge.stop", bridge_generation = model.bridge.generation })
    end
    model.bridge.phase = "stopping"
    model.connection.phase = "disconnecting"
    reset_session_runtime(model.session)
    reset_projection(model.projection)
    reset_turn(model.turn)
    reset_interaction(model.interaction)
    self.replacement = nil
    self.activation = nil
    return accepted(effects)
  elseif event.type == "client.interrupt_requested" then
    local model = self.model
    local turn = model.turn
    if turn.phase ~= "running" or turn.session_id ~= model.session.live_id then
      return rejected()
    end
    turn.phase = "interrupting"
    turn.operation_id = self:next_operation_id()
    reset_interaction(model.interaction)
    return accepted({
      {
        type = "rpc.request",
        operation_id = turn.operation_id,
        method = "session.interrupt",
        params = { session_id = turn.session_id },
        connection_generation = model.connection.generation,
        session_generation = model.session.generation,
        turn_generation = turn.generation,
      },
      { type = "interaction.invalidate" },
    })
  elseif event.type == "bridge.exited" then
    local model = self.model
    if
      event.bridge_generation ~= model.bridge.generation
      or event.connection_generation ~= model.connection.generation
      or model.bridge.phase == "stopped"
    then
      return rejected()
    end
    local expected_stop = model.bridge.phase == "stopping"
    local effects = {}
    if model.session.phase == "replacing" or model.session.phase == "persisting_replacement" then
      table.insert(effects, { type = "session_transition.settle", accepted = false, error = "bridge disconnected" })
    end
    if model.turn.phase ~= "idle" then
      local submission_id = model.turn.submission_id or (model.turn.request and model.turn.request.submission_id)
      table.insert(effects, { type = "submission.settle", submission_id = submission_id, accepted = false })
      table.insert(effects, { type = "projection.finish", status = "disconnected", delimiter = model.turn.delimiter })
      table.insert(effects, { type = "agent_events.end_turn" })
    end
    if not expected_stop then
      table.insert(effects, { type = "interaction.invalidate" })
      table.insert(effects, { type = "notify", level = "error", message = "bridge disconnected" })
    end
    model.bridge.phase = "stopped"
    model.connection.phase = "disconnected"
    reset_session_runtime(model.session)
    reset_projection(model.projection)
    reset_turn(model.turn)
    reset_interaction(model.interaction)
    self.replacement = nil
    self.activation = nil
    return accepted(effects)
  elseif event.type == "client.new_session_requested" then
    local model = self.model
    local session = model.session
    if
      model.connection.phase ~= "ready"
      or session.phase ~= "active"
      or model.turn.phase ~= "idle"
      or model.interaction.phase ~= "none"
    then
      return rejected()
    end
    session.generation = session.generation + 1
    session.phase = "replacing"
    session.operation_id = self:next_operation_id()
    self.replacement = {
      old_live_id = session.live_id,
      old_durable_id = session.durable_id,
      old_interaction = deep_copy(model.interaction),
    }
    return accepted({
      {
        type = "rpc.request",
        operation_id = session.operation_id,
        method = "session.create",
        params = {},
        replacement = true,
        connection_generation = model.connection.generation,
        session_generation = session.generation,
      },
    })
  elseif event.type == "session.replacement_created" then
    local model = self.model
    local session = model.session
    if
      session.phase ~= "replacing"
      or event.operation_id ~= session.operation_id
      or event.connection_generation ~= model.connection.generation
      or event.session_generation ~= session.generation
      or type(event.live_id) ~= "string"
      or event.live_id == ""
      or type(event.durable_id) ~= "string"
      or event.durable_id == ""
    then
      return rejected()
    end
    session.phase = "persisting_replacement"
    self.replacement.new_live_id = event.live_id
    self.replacement.new_durable_id = event.durable_id
    self.replacement.messages = event.messages or {}
    return accepted({
      {
        type = "session_store.save",
        durable_id = event.durable_id,
        operation_id = event.operation_id,
        session_generation = event.session_generation,
        replacement = true,
      },
    })
  elseif event.type == "session_store.saved" then
    local model = self.model
    local session = model.session
    if event.activation then
      if
        session.phase ~= "persisting_activation"
        or event.operation_id ~= session.operation_id
        or event.session_generation ~= session.generation
      then
        return rejected()
      end
      session.phase = "active"
      session.operation_id = nil
      session.last_sequence = 0
      local activation = self.activation or {}
      self.pending_activation = activation
      self.activation = nil
      return accepted({ begin_hydration(self, activation.messages or {}) })
    end
    if
      not event.replacement
      or session.phase ~= "persisting_replacement"
      or event.operation_id ~= session.operation_id
      or event.session_generation ~= session.generation
    then
      return rejected()
    end
    local replacement = self.replacement
    session.phase = "active"
    session.live_id = replacement.new_live_id
    session.durable_id = replacement.new_durable_id
    session.operation_id = nil
    session.last_sequence = 0
    self.replacement = nil
    model.projection.phase = "ready"
    model.projection.session_id = replacement.new_live_id
    reset_interaction(model.interaction)
    return accepted({
      { type = "projection.clear_for_new_session" },
      { type = "interaction.invalidate" },
      { type = "session.close_detached", session_id = replacement.old_live_id },
      { type = "session_transition.settle", accepted = true, live_id = replacement.new_live_id },
    })
  elseif event.type == "session_store.save_failed" then
    local model = self.model
    local session = model.session
    if event.activation then
      if
        session.phase ~= "persisting_activation"
        or event.operation_id ~= session.operation_id
        or event.session_generation ~= session.generation
      then
        return rejected()
      end
      local message = tostring(event.error or "unknown error")
      local effects = {}
      queued_failure(model, effects, "session_error", message)
      table.insert(effects, { type = "notify", level = "error", message = "could not persist session: " .. message })
      table.insert(effects, { type = "bridge.close_session", session_id = session.live_id })
      model.bridge.phase = "stopping"
      model.connection.phase = "disconnecting"
      reset_session_runtime(session)
      reset_projection(model.projection)
      reset_turn(model.turn)
      reset_interaction(model.interaction)
      self.activation = nil
      return accepted(effects)
    end
    if
      not self.replacement
      or session.phase ~= "persisting_replacement"
      or event.operation_id ~= session.operation_id
      or event.session_generation ~= session.generation
    then
      return rejected()
    end
    session.phase = "active"
    session.live_id = self.replacement.old_live_id
    session.durable_id = self.replacement.old_durable_id
    session.operation_id = nil
    model.interaction = self.replacement.old_interaction
    local abandoned = self.replacement.new_live_id
    self.replacement = nil
    return accepted({
      {
        type = "notify",
        level = "error",
        message = "could not persist replacement session: " .. tostring(event.error or "unknown error"),
      },
      { type = "session.close_detached", session_id = abandoned },
      { type = "session_transition.settle", accepted = false, error = tostring(event.error or "unknown error") },
    })
  elseif event.type == "session_store.cleared" then
    local model = self.model
    local session = model.session
    if
      session.phase ~= "clearing_stale"
      or event.operation_id ~= session.operation_id
      or event.session_generation ~= session.generation
    then
      return rejected()
    end
    session.durable_id = nil
    session.generation = session.generation + 1
    session.phase = "creating"
    session.operation_id = self:next_operation_id()
    return accepted({
      {
        type = "rpc.request",
        operation_id = session.operation_id,
        method = "session.create",
        params = {},
        bridge_generation = model.bridge.generation,
        connection_generation = model.connection.generation,
        session_generation = session.generation,
      },
    })
  elseif event.type == "client.open_requested" then
    local model = self.model
    if model.bridge.phase == "stopping" then
      return rejected()
    end
    if model.connection.phase == "ready" and model.session.phase == "active" and model.projection.phase == "ready" then
      return accepted({ { type = "projection.show" } })
    end
    local effects = {}
    if model.bridge.phase == "stopped" then
      model.bridge.generation = model.bridge.generation + 1
      model.bridge.phase = "starting"
      model.connection.generation = model.connection.generation + 1
      model.connection.phase = "connecting"
      table.insert(effects, {
        type = "bridge.start",
        bridge_generation = model.bridge.generation,
        connection_generation = model.connection.generation,
      })
    end
    table.insert(effects, { type = "projection.show" })
    return accepted(effects)
  elseif event.type == "bridge.started" then
    local model = self.model
    if model.bridge.phase ~= "starting" or event.bridge_generation ~= model.bridge.generation then
      return rejected()
    end
    model.bridge.phase = "running"
    return accepted({
      {
        type = "session_store.load",
        bridge_generation = model.bridge.generation,
        connection_generation = model.connection.generation,
      },
    })
  elseif event.type == "session_store.loaded" then
    local model = self.model
    if
      model.bridge.phase ~= "running"
      or event.bridge_generation ~= model.bridge.generation
      or event.connection_generation ~= model.connection.generation
    then
      return rejected()
    end
    model.session.generation = model.session.generation + 1
    model.session.last_sequence = 0
    model.session.durable_id = event.durable_id
    local method = event.durable_id and "session.resume" or "session.create"
    model.session.phase = event.durable_id and "resuming" or "creating"
    model.session.operation_id = self:next_operation_id()
    return accepted({
      {
        type = "rpc.request",
        operation_id = model.session.operation_id,
        method = method,
        params = event.durable_id and { session_id = event.durable_id } or {},
        bridge_generation = model.bridge.generation,
        connection_generation = model.connection.generation,
        session_generation = model.session.generation,
      },
    })
  elseif event.type == "session.activated" then
    local model = self.model
    local session = model.session
    if
      (session.phase ~= "creating" and session.phase ~= "resuming")
      or event.bridge_generation ~= model.bridge.generation
      or event.connection_generation ~= model.connection.generation
      or event.session_generation ~= session.generation
      or event.operation_id ~= session.operation_id
      or type(event.live_id) ~= "string"
      or event.live_id == ""
      or type(event.durable_id) ~= "string"
      or event.durable_id == ""
    then
      return rejected()
    end
    if not valid_activation_payload(event) then
      local effects = {}
      queued_failure(model, effects, "session_error", "malformed activation payload")
      table.insert(effects, {
        type = "notify",
        level = "error",
        message = "could not activate session: malformed activation payload",
      })
      table.insert(effects, { type = "bridge.close_session", session_id = event.live_id })
      model.bridge.phase = "stopping"
      model.connection.phase = "disconnecting"
      reset_session_runtime(model.session)
      reset_projection(model.projection)
      reset_turn(model.turn)
      reset_interaction(model.interaction)
      self.activation = nil
      self.pending_activation = nil
      return accepted(effects)
    end
    session.phase = "persisting_activation"
    session.live_id = event.live_id
    session.durable_id = event.durable_id
    session.last_sequence = 0
    self.activation = {
      messages = event.messages or {},
      pending_approval = event.pending_approval,
      pending_clarification = event.pending_clarification,
    }
    return accepted({
      {
        type = "session_store.save",
        durable_id = event.durable_id,
        operation_id = event.operation_id,
        session_generation = event.session_generation,
        activation = true,
      },
    })
  elseif event.type == "projection.hydrated" then
    local model = self.model
    if
      model.session.phase ~= "active"
      or model.projection.phase ~= "hydrating"
      or event.projection_generation ~= model.projection.generation
      or event.session_generation ~= model.session.generation
      or event.session_id ~= model.session.live_id
    then
      return rejected()
    end
    model.connection.phase = "ready"
    model.projection.phase = "ready"
    local effects = {}
    local activation = self.pending_activation or {}
    self.pending_activation = nil
    local pending = activation.pending_approval or activation.pending_clarification
    if type(pending) == "table" and pending.request_id ~= nil then
      local interaction = model.interaction
      interaction.generation = interaction.generation + 1
      interaction.phase = activation.pending_approval and "approval" or "clarification"
      interaction.session_id = model.session.live_id
      interaction.request_id = pending.request_id
      interaction.request = pending
      interaction.answers = type(pending.answers) == "table" and deep_copy(pending.answers) or {}
      interaction.question_index = 1
      local effect = activation.pending_approval
          and {
            type = "interaction.show_approval",
            interaction_generation = interaction.generation,
            session_id = interaction.session_id,
            request = pending,
          }
        or clarification_effect(interaction)
      if effect then
        table.insert(effects, effect)
      end
    end
    if model.turn.phase == "queued" then
      self:start_turn(model.turn.request, effects)
    end
    return accepted(effects)
  elseif event.type == "projection.hydration_failed" then
    local model = self.model
    if
      model.projection.phase ~= "hydrating"
      or event.projection_generation ~= model.projection.generation
      or event.session_generation ~= model.session.generation
      or event.session_id ~= model.session.live_id
    then
      return rejected()
    end
    local message = tostring(event.error or "unknown error")
    local effects = {}
    queued_failure(model, effects, "session_error", message)
    table.insert(effects, { type = "notify", level = "error", message = "could not hydrate session: " .. message })
    table.insert(effects, { type = "bridge.close_session", session_id = model.session.live_id })
    model.bridge.phase = "stopping"
    model.connection.phase = "disconnecting"
    reset_session_runtime(model.session)
    reset_projection(model.projection)
    reset_turn(model.turn)
    reset_interaction(model.interaction)
    self.pending_activation = nil
    return accepted(effects)
  elseif event.type == "prompt.submitted" then
    local model = self.model
    local turn = model.turn
    if
      model.bridge.phase == "stopping"
      or turn.phase ~= "idle"
      or type(event.text) ~= "string"
      or event.text == ""
      or event.submission_id == nil
    then
      return rejected()
    end
    if model.connection.phase ~= "ready" or model.session.phase ~= "active" or model.projection.phase ~= "ready" then
      turn.phase = "queued"
      turn.request = {
        submission_id = event.submission_id,
        text = event.text,
        presentation = event.presentation or {},
      }
      local effects = { { type = "projection.show" } }
      if model.bridge.phase == "stopped" then
        model.bridge.generation = model.bridge.generation + 1
        model.bridge.phase = "starting"
        model.connection.generation = model.connection.generation + 1
        model.connection.phase = "connecting"
        table.insert(effects, {
          type = "bridge.start",
          bridge_generation = model.bridge.generation,
          connection_generation = model.connection.generation,
        })
      end
      return accepted(effects)
    end
    local effects = {}
    self:start_turn({
      submission_id = event.submission_id,
      text = event.text,
      presentation = event.presentation or {},
    }, effects)
    return accepted(effects)
  elseif event.type == "operation.failed" then
    local model = self.model
    local session = model.session
    local interaction = model.interaction
    if
      interaction.phase == "responding"
      and event.operation_id == interaction.operation_id
      and event.connection_generation == model.connection.generation
      and event.session_generation == model.session.generation
      and event.interaction_generation == interaction.generation
    then
      local message = type(event.error) == "table" and event.error.message or "unknown error"
      reset_interaction(interaction)
      return accepted({
        { type = "notify", level = "error", message = "interaction response failed: " .. tostring(message) },
      })
    end
    local turn = model.turn
    if
      turn.phase == "interrupting"
      and event.method == "session.interrupt"
      and event.operation_id == turn.operation_id
      and event.connection_generation == model.connection.generation
      and event.session_generation == model.session.generation
      and event.turn_generation == turn.generation
    then
      local message = type(event.error) == "table" and event.error.message or "unknown error"
      turn.phase = "running"
      turn.operation_id = nil
      return accepted({ { type = "notify", level = "error", message = "interrupt failed: " .. tostring(message) } })
    end
    if
      session.phase == "resuming"
      and event.operation_id == session.operation_id
      and event.bridge_generation == model.bridge.generation
      and event.connection_generation == model.connection.generation
      and event.session_generation == session.generation
      and type(event.error) == "table"
      and event.error.code == 4007
      and event.error.message == "session not found"
    then
      session.phase = "clearing_stale"
      return accepted({
        {
          type = "session_store.clear",
          operation_id = session.operation_id,
          session_generation = session.generation,
        },
      })
    end
    if
      session.phase == "replacing"
      and self.replacement
      and event.operation_id == session.operation_id
      and event.connection_generation == model.connection.generation
      and event.session_generation == session.generation
    then
      local message = type(event.error) == "table" and event.error.message or "unknown error"
      session.phase = "active"
      session.live_id = self.replacement.old_live_id
      session.durable_id = self.replacement.old_durable_id
      session.operation_id = nil
      self.replacement = nil
      return accepted({
        { type = "notify", level = "error", message = "could not create replacement session: " .. message },
        { type = "session_transition.settle", accepted = false, error = message },
      })
    end
    if
      (session.phase == "creating" or session.phase == "resuming")
      and event.operation_id == session.operation_id
      and event.bridge_generation == model.bridge.generation
      and event.connection_generation == model.connection.generation
      and event.session_generation == session.generation
    then
      local message = type(event.error) == "table" and event.error.message or nil
      local effects = {}
      if model.turn.phase == "queued" then
        table.insert(effects, {
          type = "submission.settle",
          submission_id = model.turn.request.submission_id,
          accepted = false,
        })
        table.insert(effects, {
          type = "projection.finish",
          status = "session_error",
          error = message or "unknown error",
          delimiter = model.turn.request.presentation.delimiter == true,
        })
      end
      reset_turn(model.turn)
      reset_interaction(model.interaction)
      model.projection.phase = "unhydrated"
      session.phase = "none"
      session.live_id = nil
      session.operation_id = nil
      model.connection.phase = "disconnecting"
      model.bridge.phase = "stopping"
      table.insert(effects, { type = "bridge.stop", bridge_generation = model.bridge.generation })
      return accepted(effects)
    end
    turn = model.turn
    if
      turn.phase == "submitting"
      and event.method == "prompt.submit"
      and event.operation_id == turn.operation_id
      and event.connection_generation == model.connection.generation
      and event.session_generation == model.session.generation
      and event.turn_generation == turn.generation
    then
      local message = type(event.error) == "table" and event.error.message or nil
      local effects = {
        { type = "submission.settle", submission_id = turn.submission_id, accepted = false },
        {
          type = "projection.finish",
          status = "request_error",
          error = message or "unknown error",
          delimiter = turn.delimiter,
        },
        { type = "agent_events.end_turn" },
      }
      reset_turn(turn)
      return accepted(effects)
    end
    return rejected()
  elseif event.type == "operation.succeeded" then
    local model = self.model
    local interaction = model.interaction
    if
      interaction.phase == "responding"
      and event.operation_id == interaction.operation_id
      and event.connection_generation == model.connection.generation
      and event.session_generation == model.session.generation
      and event.interaction_generation == interaction.generation
    then
      if interaction.cancelled then
        reset_interaction(interaction)
        return accepted()
      end
      if interaction.request and type(interaction.request.questions) == "table" then
        if type(event.result) == "table" and event.result.status == "expired" then
          reset_interaction(interaction)
          return accepted()
        end
        local answered = interaction.pending_answer
        if answered and answered.question_id ~= nil then
          interaction.answers[answered.question_id] = answered.answer
        end
        interaction.question_index = (interaction.question_index or 1) + 1
        interaction.operation_id = nil
        interaction.pending_answer = nil
        local next_effect = clarification_effect(interaction)
        if next_effect then
          interaction.phase = "clarification"
          return accepted({ next_effect })
        end
      end
      reset_interaction(interaction)
      return accepted()
    end
    local turn = model.turn
    if
      turn.phase == "interrupting"
      and event.operation_id == turn.operation_id
      and event.connection_generation == model.connection.generation
      and event.session_generation == model.session.generation
      and event.turn_generation == turn.generation
    then
      turn.operation_id = nil
      return accepted()
    end
    if
      turn.phase ~= "submitting"
      or event.operation_id ~= turn.operation_id
      or event.connection_generation ~= model.connection.generation
      or event.session_generation ~= model.session.generation
      or event.turn_generation ~= turn.generation
    then
      return rejected()
    end
    turn.phase = "running"
    turn.operation_id = nil
    return accepted({
      { type = "submission.settle", submission_id = turn.submission_id, accepted = true },
    })
  elseif event.type == "message.delta" then
    local model = self.model
    local turn = model.turn
    if
      model.session.phase ~= "active"
      or event.session_id ~= model.session.live_id
      or (turn.phase ~= "submitting" and turn.phase ~= "running" and turn.phase ~= "interrupting")
      or type(event.sequence) ~= "number"
      or event.sequence <= model.session.last_sequence
    then
      return rejected()
    end
    model.session.last_sequence = event.sequence
    local effects = {}
    if turn.phase == "submitting" then
      turn.phase = "running"
      turn.operation_id = nil
      table.insert(effects, { type = "submission.settle", submission_id = turn.submission_id, accepted = true })
    end
    table.insert(effects, { type = "projection.append_delta", text = event.text or "" })
    return accepted(effects)
  elseif event.type == "agent_activity.received" then
    local model = self.model
    local turn = model.turn
    if
      model.session.phase ~= "active"
      or event.session_id ~= model.session.live_id
      or (turn.phase ~= "submitting" and turn.phase ~= "running" and turn.phase ~= "interrupting")
      or type(event.sequence) ~= "number"
      or event.sequence <= model.session.last_sequence
    then
      return rejected()
    end
    model.session.last_sequence = event.sequence
    local effects = {}
    if turn.phase == "submitting" then
      turn.phase = "running"
      turn.operation_id = nil
      table.insert(effects, { type = "submission.settle", submission_id = turn.submission_id, accepted = true })
    end
    table.insert(effects, {
      type = "agent_events.render",
      activity_type = event.activity_type,
      payload = event.payload or {},
    })
    return accepted(effects)
  elseif event.type == "message.completed" then
    local model = self.model
    local turn = model.turn
    if
      model.session.phase ~= "active"
      or event.session_id ~= model.session.live_id
      or (turn.phase ~= "submitting" and turn.phase ~= "running" and turn.phase ~= "interrupting")
      or type(event.sequence) ~= "number"
      or event.sequence <= model.session.last_sequence
    then
      return rejected()
    end
    model.session.last_sequence = event.sequence
    local finish = {
      type = "projection.finish",
      status = type(event.status) == "string" and event.status or "complete",
      text = type(event.text) == "string" and event.text or nil,
      delimiter = turn.delimiter,
    }
    if type(event.error) == "string" then
      finish.error = event.error
    elseif type(event.error) == "table" and type(event.error.message) == "string" then
      finish.error = event.error.message
    end
    if event.partial ~= nil then
      finish.partial = event.partial
    end
    if event.recoverable ~= nil then
      finish.recoverable = event.recoverable
    end
    local effects = {}
    if turn.phase == "submitting" then
      table.insert(effects, { type = "submission.settle", submission_id = turn.submission_id, accepted = true })
    end
    table.insert(effects, finish)
    table.insert(effects, { type = "agent_events.end_turn" })
    reset_turn(turn)
    return accepted(effects)
  elseif event.type == "protocol.unknown" then
    local model = self.model
    if not current_sequence(model, event) then
      return rejected()
    end
    model.session.last_sequence = event.sequence
    return accepted()
  elseif event.type == "approval.requested" or event.type == "clarification.requested" then
    local model = self.model
    if
      model.session.phase ~= "active"
      or event.session_id ~= model.session.live_id
      or type(event.sequence) ~= "number"
      or event.sequence <= model.session.last_sequence
      or event.request_id == nil
      or (event.type == "clarification.requested" and not valid_clarification_request(event.request))
    then
      return rejected()
    end
    model.session.last_sequence = event.sequence
    local interaction = model.interaction
    interaction.generation = interaction.generation + 1
    interaction.phase = event.type == "approval.requested" and "approval" or "clarification"
    interaction.session_id = event.session_id
    interaction.request_id = event.request_id
    interaction.request = event.request
    interaction.answers = type((event.request or {}).answers) == "table" and deep_copy(event.request.answers) or {}
    interaction.question_index = 1
    local effect = event.type == "approval.requested"
        and {
          type = "interaction.show_approval",
          interaction_generation = interaction.generation,
          session_id = event.session_id,
          request = event.request,
        }
      or clarification_effect(interaction)
    return accepted(effect and { effect } or {})
  elseif event.type == "approval.answered" or event.type == "clarification.answered" then
    local model = self.model
    local interaction = model.interaction
    local expected_phase = event.type == "approval.answered" and "approval" or "clarification"
    if
      interaction.phase ~= expected_phase
      or model.session.phase ~= "active"
      or event.interaction_generation ~= interaction.generation
      or event.request_id ~= interaction.request_id
      or interaction.session_id ~= model.session.live_id
    then
      return rejected()
    end
    interaction.phase = "responding"
    interaction.operation_id = self:next_operation_id()
    local params = {
      session_id = interaction.session_id,
      request_id = interaction.request_id,
    }
    local method
    if event.type == "approval.answered" then
      method = "approval.respond"
      params.choice = event.choice
    else
      method = "clarify.respond"
      params.answer = event.answer or ""
      interaction.cancelled = event.cancelled == true
      if not interaction.cancelled then
        params.question_id = event.question_id
        interaction.pending_answer = { question_id = event.question_id, answer = event.answer or "" }
      end
    end
    return accepted({
      {
        type = "rpc.request",
        operation_id = interaction.operation_id,
        method = method,
        params = params,
        connection_generation = model.connection.generation,
        session_generation = model.session.generation,
        interaction_generation = interaction.generation,
      },
    })
  end
  return rejected()
end

function M.new()
  return setmetatable({
    model = initial_model(),
    operation_sequence = 0,
    replacement = nil,
  }, Machine)
end

return M

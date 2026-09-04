---@alias HermesNotificationLevel "error"|"warn"|"info"

---@class HermesRequestContext
---@field cols integer
---@field cwd string
---@field source string
---@field title string

---@class HermesProtocolAdapter
---@field to_event fun(params: HermesWireEvent): HermesProtocolEvent?

---@class HermesRuntimeProductionOptions
---@field process table
---@field dispatch? fun(event: HermesEvent): HermesTransitionResult?
---@field rpc? table
---@field protocol? HermesProtocolAdapter
---@field session_store? table
---@field session_store_file? string
---@field session_store_file_provider? fun(): string
---@field bridge_command? string[]
---@field bridge_command_provider? fun(): string[]
---@field request_context? fun(): HermesRequestContext
---@field projection? table
---@field agent_events? table
---@field interaction? table
---@field submission_settle? fun(submission_id: HermesId, accepted: boolean)
---@field session_transition_settle? fun(accepted: boolean, live_id?: string, error?: string)
---@field notify? fun(message: string, level: HermesNotificationLevel)

---@class HermesRuntimeOptions : HermesRuntimeProductionOptions
---@field dispatch fun(event: HermesEvent): HermesTransitionResult?

local M = {}

---@class HermesRuntime
---@field process table
---@field rpc? table
---@field protocol? HermesProtocolAdapter
---@field session_store? table
---@field session_store_file? string
---@field session_store_file_provider? fun(): string
---@field bridge_command? string[]
---@field bridge_command_provider? fun(): string[]
---@field request_context fun(): HermesRequestContext
---@field projection table
---@field agent_events table
---@field interaction table
---@field submission_settle fun(submission_id: HermesId, accepted: boolean)
---@field session_transition_settle fun(accepted: boolean, live_id?: string, error?: string)
---@field notify fun(message: string, level: HermesNotificationLevel)
---@field dispatch fun(event: HermesEvent): HermesTransitionResult?
local Runtime = {}
Runtime.__index = Runtime

---@param value any
---@return string?
local function nonempty_string(value)
  return type(value) == "string" and value ~= "" and value or nil
end

---@param effect HermesEffect
---@param message string
---@return string
local function failed_turn_text(effect, message)
  local lines = { "> [!WARNING]", "> **Hermes turn failed**", ">", "> " .. message:gsub("\n", "\n> ") }
  if effect.recoverable then
    vim.list_extend(
      lines,
      { ">", "> The conversation is still available. Retry the request or send a shorter follow-up." }
    )
  end
  return table.concat(lines, "\n")
end

---@param effect HermesEffect
function Runtime:run(effect)
  if effect.type == "rpc.request" then
    local params = effect.params or {}
    if effect.method == "session.create" then
      params = vim.tbl_extend("force", {}, self.request_context(), params)
    end
    self.rpc.request(effect.method, params, function(result)
      if effect.method == "session.create" or effect.method == "session.resume" then
        if type(result) ~= "table" or type(result.session_id) ~= "string" or result.session_id == "" then
          self.dispatch({
            type = "operation.failed",
            operation_id = effect.operation_id,
            method = effect.method,
            bridge_generation = effect.bridge_generation,
            connection_generation = effect.connection_generation,
            session_generation = effect.session_generation,
            error = { code = -32603, message = "invalid session response" },
          })
          return
        end
        local durable_id = result.stored_session_id or result.session_key
        if not durable_id and type(result.resumed) == "string" then
          durable_id = result.resumed
        end
        if type(durable_id) ~= "string" or durable_id == "" then
          self.dispatch({
            type = "operation.failed",
            operation_id = effect.operation_id,
            method = effect.method,
            bridge_generation = effect.bridge_generation,
            connection_generation = effect.connection_generation,
            session_generation = effect.session_generation,
            error = { code = -32603, message = "session response omitted its durable id" },
          })
          return
        end
        self.dispatch({
          type = effect.replacement and "session.replacement_created" or "session.activated",
          operation_id = effect.operation_id,
          bridge_generation = effect.bridge_generation,
          connection_generation = effect.connection_generation,
          session_generation = effect.session_generation,
          live_id = result.session_id,
          durable_id = durable_id,
          messages = result.messages or {},
          pending_approval = result.pending_approval,
          pending_clarification = result.pending_clarify,
        })
        return
      end
      local event = {
        type = "operation.succeeded",
        operation_id = effect.operation_id,
        connection_generation = effect.connection_generation,
        session_generation = effect.session_generation,
        result = result,
      }
      if effect.turn_generation ~= nil then
        event.turn_generation = effect.turn_generation
      end
      if effect.interaction_generation ~= nil then
        event.interaction_generation = effect.interaction_generation
      end
      self.dispatch(event)
    end, function(err)
      local event = {
        type = "operation.failed",
        operation_id = effect.operation_id,
        connection_generation = effect.connection_generation,
        session_generation = effect.session_generation,
        error = err,
        method = effect.method,
      }
      if effect.turn_generation ~= nil then
        event.turn_generation = effect.turn_generation
      end
      if effect.interaction_generation ~= nil then
        event.interaction_generation = effect.interaction_generation
      end
      if effect.bridge_generation ~= nil then
        event.bridge_generation = effect.bridge_generation
      end
      self.dispatch(event)
    end)
  elseif effect.type == "session_store.load" then
    local session_store_file = self.session_store_file_provider and self.session_store_file_provider()
      or self.session_store_file
    self.dispatch({
      type = "session_store.loaded",
      bridge_generation = effect.bridge_generation,
      connection_generation = effect.connection_generation,
      durable_id = self.session_store.load(session_store_file),
    })
  elseif effect.type == "session_store.save" then
    local session_store_file = self.session_store_file_provider and self.session_store_file_provider()
      or self.session_store_file
    local ok, err = self.session_store.save(session_store_file, effect.durable_id)
    self.dispatch({
      type = ok and "session_store.saved" or "session_store.save_failed",
      operation_id = effect.operation_id,
      session_generation = effect.session_generation,
      replacement = effect.replacement,
      activation = effect.activation,
      error = ok and nil or err,
    })
  elseif effect.type == "session_store.clear" then
    local session_store_file = self.session_store_file_provider and self.session_store_file_provider()
      or self.session_store_file
    local ok, err = self.session_store.clear(session_store_file)
    self.dispatch({
      type = ok and "session_store.cleared" or "session_store.clear_failed",
      operation_id = effect.operation_id,
      session_generation = effect.session_generation,
      error = ok and nil or err,
    })
  elseif effect.type == "bridge.start" then
    local on_message = self.rpc and self.rpc.handle_message or function() end
    local command = self.bridge_command_provider and self.bridge_command_provider() or self.bridge_command
    local started = self.process.start(command, on_message, function(code)
      self.dispatch({
        type = "bridge.exited",
        bridge_generation = effect.bridge_generation,
        connection_generation = effect.connection_generation,
        code = code,
      })
      if self.rpc and self.rpc.fail_pending then
        self.rpc.fail_pending({ code = -32000, message = "bridge disconnected" })
      end
    end)
    if started then
      self.dispatch({
        type = "bridge.started",
        bridge_generation = effect.bridge_generation,
        connection_generation = effect.connection_generation,
      })
    else
      self.dispatch({
        type = "bridge.start_failed",
        bridge_generation = effect.bridge_generation,
        connection_generation = effect.connection_generation,
        error = "could not start bridge process",
      })
    end
  elseif effect.type == "bridge.close_session" then
    local finished = false
    local timer = assert(vim.uv.new_timer(), "could not create bridge close timer")
    local function finish()
      if finished then
        return
      end
      finished = true
      timer:stop()
      timer:close()
      if self.rpc and self.rpc.fail_pending then
        self.rpc.fail_pending({ code = -32000, message = "bridge stopped" })
      end
      self.process.stop()
    end
    timer:start(1000, 0, vim.schedule_wrap(finish))
    self.rpc.request("session.close", { session_id = effect.session_id }, finish, function(err)
      self.notify("session.close failed: " .. tostring((err or {}).message or "unknown error"), "warn")
      finish()
    end)
  elseif effect.type == "bridge.stop" then
    if self.rpc and self.rpc.fail_pending then
      self.rpc.fail_pending({ code = -32000, message = "bridge stopped" })
    end
    self.process.stop()
  elseif effect.type == "session.close_detached" then
    self.rpc.request("session.close", { session_id = effect.session_id }, function() end, function(err)
      self.notify("session.close failed: " .. tostring((err or {}).message or "unknown error"), "warn")
    end)
  elseif effect.type == "projection.show" then
    self.projection.show()
  elseif effect.type == "projection.hydrate" then
    local ok, err = true, nil
    if not effect.preserve_existing then
      ok, err = pcall(self.projection.hydrate, effect.messages or {})
    end
    self.dispatch({
      type = ok and "projection.hydrated" or "projection.hydration_failed",
      projection_generation = effect.projection_generation,
      session_generation = effect.session_generation,
      session_id = effect.session_id,
      error = ok and nil or tostring(err),
    })
  elseif effect.type == "projection.clear_for_new_session" then
    self.projection.clear_for_new_session()
  elseif effect.type == "projection.append_user" then
    self.projection.append_user(effect.text)
  elseif effect.type == "projection.begin_assistant" then
    self.projection.begin_assistant()
  elseif effect.type == "projection.append_delta" then
    self.projection.append_delta(effect.text)
  elseif effect.type == "projection.finish" then
    self.projection.finish(effect)
  elseif effect.type == "submission.settle" then
    self.submission_settle(effect.submission_id, effect.accepted)
  elseif effect.type == "session_transition.settle" then
    self.session_transition_settle(effect.accepted, effect.live_id, effect.error)
  elseif effect.type == "agent_events.begin_turn" then
    self.agent_events.begin_turn()
  elseif effect.type == "agent_events.end_turn" then
    self.agent_events.end_turn()
  elseif effect.type == "agent_events.render" then
    self.agent_events.render(effect.activity_type, effect.payload)
  elseif effect.type == "interaction.invalidate" then
    self.interaction.invalidate()
  elseif effect.type == "interaction.show_approval" then
    self.interaction.show_approval(effect.request, function(choice)
      self.dispatch({
        type = "approval.answered",
        interaction_generation = effect.interaction_generation,
        request_id = effect.request.request_id,
        choice = choice,
      })
    end)
  elseif effect.type == "interaction.show_clarification" then
    self.interaction.show_clarification(effect.question or effect.request, function(answer)
      self.dispatch({
        type = "clarification.answered",
        interaction_generation = effect.interaction_generation,
        request_id = effect.request.request_id,
        question_id = answer.question_id or (effect.question and effect.question.qid),
        answer = answer.answer,
        cancelled = answer.cancelled,
      })
    end)
  elseif effect.type == "notify" then
    self.notify(effect.message, effect.level)
  end
end

---@param options HermesRuntimeOptions
---@return HermesRuntime
function M.new(options)
  assert(type(options) == "table", "runtime options are required")
  assert(options.process, "runtime requires process adapter")
  assert(type(options.dispatch) == "function", "runtime requires dispatch")
  local runtime = setmetatable({
    process = options.process,
    rpc = options.rpc,
    protocol = options.protocol,
    session_store = options.session_store,
    session_store_file = options.session_store_file,
    session_store_file_provider = options.session_store_file_provider,
    bridge_command = options.bridge_command,
    bridge_command_provider = options.bridge_command_provider,
    request_context = options.request_context or function()
      return {
        cols = vim.o.columns,
        cwd = vim.fn.getcwd(),
        source = "hermes.nvim",
        title = "hermes.nvim session",
      }
    end,
    projection = options.projection or {},
    agent_events = options.agent_events or {},
    interaction = options.interaction or {},
    submission_settle = options.submission_settle or function() end,
    session_transition_settle = options.session_transition_settle or function() end,
    notify = options.notify or function() end,
    dispatch = options.dispatch,
  }, Runtime)
  if runtime.rpc and runtime.protocol then
    runtime.rpc.on_event(function(params)
      local event = runtime.protocol.to_event(params)
      if event then
        runtime.dispatch(event)
      end
    end)
  end
  return runtime
end

---@return HermesRuntimeProductionOptions
function M.production_options()
  local buffer = require("hermes.buffer")
  local history = require("hermes.history")
  local events = require("hermes.events")
  local interaction = require("hermes.interaction")
  local config = require("hermes.config")
  return {
    process = require("hermes.process"),
    rpc = require("hermes.rpc"),
    protocol = require("hermes.protocol"),
    session_store = require("hermes.session_store"),
    session_store_file_provider = function()
      return config.options.session_store_file
    end,
    bridge_command_provider = function()
      return config.options.bridge_cmd
    end,
    projection = {
      show = buffer.show,
      hydrate = history.render,
      clear_for_new_session = buffer.clear,
      append_user = buffer.append_user,
      begin_assistant = buffer.begin_assistant,
      append_delta = buffer.append,
      finish = function(effect)
        if effect.status == "error" then
          local completion_text = nonempty_string(effect.text)
          local message = nonempty_string(effect.error)
            or completion_text
            or "The turn failed without an error message."
          local warning = failed_turn_text(effect, message)
          if effect.partial then
            if completion_text and completion_text ~= message then
              buffer.replace_assistant(completion_text)
            end
            buffer.append("\n\n" .. warning)
          else
            buffer.replace_assistant(warning)
          end
          vim.notify("hermes: turn failed: " .. message, vim.log.levels.ERROR)
        elseif effect.status == "interrupted" then
          if nonempty_string(effect.text) then
            buffer.replace_assistant(effect.text)
          else
            buffer.append("\n\n_Interrupted._")
          end
        elseif effect.status == "disconnected" then
          buffer.append("\n\n_Connection lost before the response completed._")
        elseif effect.status == "stopped" then
          buffer.append("\n\n_Stopped before the response completed._")
        elseif effect.status == "request_error" then
          buffer.append("\n\n_Request failed: " .. tostring(effect.error or "unknown error") .. "_")
        elseif effect.status == "session_error" then
          buffer.append("\n\n_Could not create a Hermes session: " .. tostring(effect.error or "unknown error") .. "_")
        elseif nonempty_string(effect.text) then
          buffer.replace_assistant(effect.text)
        elseif effect.status and effect.status ~= "complete" then
          buffer.append("\n\n_Turn ended: " .. effect.status .. "._")
        end
        buffer.finish_assistant({ delimiter = effect.delimiter })
      end,
    },
    agent_events = events,
    interaction = interaction,
    notify = function(message, level)
      local levels = { error = vim.log.levels.ERROR, warn = vim.log.levels.WARN, info = vim.log.levels.INFO }
      vim.notify("hermes: " .. message, levels[level] or vim.log.levels.INFO)
    end,
  }
end

return M

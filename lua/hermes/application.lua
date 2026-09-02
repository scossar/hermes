local machine = require("hermes.machine")
local controller = require("hermes.controller")
local runtime = require("hermes.runtime")

local M = {}
local Application = {}
Application.__index = Application

function Application:model()
  return self.controller:model()
end

function Application:dispatch(event)
  return self.controller:dispatch(event)
end

function Application:open()
  return self:dispatch({ type = "client.open_requested" }).accepted
end

function Application:submit(text, options)
  options = options or {}
  text = text or ""
  if vim.trim(text) == "" then
    self.notify("prompt cannot be empty", "warn")
    return false
  end
  if not options.preserve_whitespace then
    text = vim.trim(text)
  end
  if
    self:model().turn.phase ~= "idle"
    or self:model().session.phase == "replacing"
    or self:model().session.phase == "persisting_replacement"
  then
    self.notify("wait for the current response to finish", "warn")
    return false
  end
  self.submission_sequence = self.submission_sequence + 1
  local submission_id = self.submission_sequence
  if options.on_accept then
    self.submissions[submission_id] = options.on_accept
  end
  local result = self:dispatch({
    type = "prompt.submitted",
    submission_id = submission_id,
    text = text,
    presentation = {
      selection = options.selection == true,
      delimiter = options.delimiter == true,
    },
  })
  if not result.accepted then
    self.submissions[submission_id] = nil
  end
  return result.accepted
end

function Application:interrupt()
  return self:dispatch({ type = "client.interrupt_requested" }).accepted
end

function Application:stop()
  return self:dispatch({ type = "client.stop_requested" }).accepted
end

function Application:new_session(callback)
  if self.session_transition_callback then
    return false
  end
  self.session_transition_callback = callback or function() end
  local accepted = self:dispatch({ type = "client.new_session_requested" }).accepted
  if not accepted then
    self.session_transition_callback = nil
  end
  return accepted
end

function Application:is_running()
  local turn = self:model().turn.phase
  local projection = self:model().projection.phase
  return turn ~= "idle" or projection == "hydrating"
end

function M.new(options)
  options = options or {}
  local app = setmetatable({
    submissions = {},
    submission_sequence = 0,
    notify = options.client_notify or function(message, level)
      local levels = { warn = vim.log.levels.WARN, error = vim.log.levels.ERROR, info = vim.log.levels.INFO }
      vim.notify("hermes: " .. message, levels[level] or vim.log.levels.INFO)
    end,
  }, Application)
  local state_machine = machine.new()
  local effect_runtime
  local app_controller = controller.new({
    machine = state_machine,
    run_effect = function(effect)
      effect_runtime:run(effect)
    end,
  })
  app.controller = app_controller
  options.dispatch = function(event)
    return app_controller:dispatch(event)
  end
  options.submission_settle = function(submission_id, accepted)
    local callback = app.submissions[submission_id]
    app.submissions[submission_id] = nil
    if callback then
      callback(accepted)
    end
  end
  options.session_transition_settle = function(accepted, live_id, err)
    local callback = app.session_transition_callback
    app.session_transition_callback = nil
    if callback then
      callback(accepted and live_id or nil, accepted and nil or { message = err or "unknown error" })
    end
  end
  options.notify = options.notify or app.notify
  effect_runtime = runtime.new(options)
  app.runtime = effect_runtime
  return app
end

local singleton

function M.get(options)
  if not singleton then
    singleton = M.new(options or require("hermes.runtime").production_options())
  end
  return singleton
end

function M.reset()
  singleton = nil
end

return M

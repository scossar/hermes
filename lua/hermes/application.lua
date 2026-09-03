local machine = require("hermes.machine")
local controller = require("hermes.controller")
local runtime = require("hermes.runtime")

local M = {}
local Application = {}
Application.__index = Application

local function default_notify(message, level)
  local levels = {
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
    info = vim.log.levels.INFO,
  }
  vim.notify("hermes: " .. message, levels[level] or vim.log.levels.INFO)
end

local function new_application(options)
  return setmetatable({
    submissions = {},
    submission_sequence = 0,
    notify = options.client_notify or default_notify,
  }, Application)
end

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

function Application:settle_submission(submission_id, accepted)
  local callback = self.submissions[submission_id]
  self.submissions[submission_id] = nil
  if callback then
    callback(accepted)
  end
end

function Application:settle_session_transition(accepted, live_id, err)
  local callback = self.session_transition_callback
  self.session_transition_callback = nil
  if not callback then
    return
  end

  if accepted then
    callback(live_id, nil)
  else
    callback(nil, { message = err or "unknown error" })
  end
end

local function runtime_options(options, app)
  local result = vim.tbl_extend("force", {}, options)
  result.dispatch = function(event)
    return app:dispatch(event)
  end
  result.submission_settle = function(submission_id, accepted)
    app:settle_submission(submission_id, accepted)
  end
  result.session_transition_settle = function(accepted, live_id, err)
    app:settle_session_transition(accepted, live_id, err)
  end
  result.notify = result.notify or app.notify
  return result
end

function M.new(options)
  options = options or {}
  local app = new_application(options)
  app.controller = controller.new({
    machine = machine.new(),
    run_effect = function(effect)
      app.runtime:run(effect)
    end,
  })
  app.runtime = runtime.new(runtime_options(options, app))
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

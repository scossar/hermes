local M = {}
local Controller = {}
Controller.__index = Controller

function Controller:model()
  return self.machine.model
end

function Controller:dispatch(event)
  table.insert(self.event_queue, event)
  if self.dispatching then
    return { accepted = true, queued = true, effects = {} }
  end

  self.dispatching = true
  local first_result
  local ok, err = xpcall(function()
    while #self.event_queue > 0 do
      local next_event = table.remove(self.event_queue, 1)
      local result = self.machine:dispatch(next_event)
      first_result = first_result or result
      for _, effect in ipairs(result.effects) do
        self.run_effect(effect)
      end
    end
  end, debug.traceback)
  self.dispatching = false
  if not ok then
    error(err, 0)
  end
  return first_result
end

function M.new(options)
  assert(type(options) == "table" and options.machine, "controller requires a machine")
  assert(type(options.run_effect) == "function", "controller requires an effect runner")
  return setmetatable({
    machine = options.machine,
    run_effect = options.run_effect,
    event_queue = {},
    dispatching = false,
  }, Controller)
end

return M

local machine = require("hermes.machine")

local function assert_subset(expected, actual, path)
  assert.is_table(actual, path)
  for key, value in pairs(expected) do
    local child_path = path .. "." .. tostring(key)
    if type(value) == "table" then
      assert_subset(value, actual[key], child_path)
    else
      assert.equals(value, actual[key], child_path)
    end
  end
end

local function effect_types(effects)
  local result = {}
  for _, effect in ipairs(effects) do
    table.insert(result, effect.type)
  end
  return result
end

local function ready_machine()
  local subject = machine.new()
  subject:dispatch({ type = "client.open_requested" })
  subject:dispatch({ type = "bridge.started", bridge_generation = 1 })
  subject:dispatch({ type = "session_store.loaded", bridge_generation = 1, connection_generation = 1 })
  subject:dispatch({
    type = "session.activated",
    bridge_generation = 1,
    connection_generation = 1,
    session_generation = 1,
    operation_id = 1,
    live_id = "live-1",
    durable_id = "durable-1",
  })
  subject:dispatch({ type = "session_store.saved", operation_id = 1, session_generation = 1, activation = true })
  subject:dispatch({
    type = "projection.hydrated",
    projection_generation = 1,
    session_generation = 1,
    session_id = "live-1",
  })
  return subject
end

local function scenario_machine(prefix)
  local subject = prefix and ready_machine() or machine.new()
  if prefix == "running" then
    subject:dispatch({ type = "prompt.submitted", submission_id = "s1", text = "hello" })
    subject:dispatch({
      type = "operation.succeeded",
      operation_id = 2,
      connection_generation = 1,
      session_generation = 1,
      turn_generation = 1,
    })
  end
  return subject
end

describe("language-neutral client conformance scenarios", function()
  local path = vim.fn.getcwd() .. "/tests/conformance/client_scenarios.json"
  local scenarios = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  for _, scenario in ipairs(scenarios) do
    it(scenario.name, function()
      local subject = scenario_machine(scenario.prefix)
      for index, step in ipairs(scenario.steps) do
        local result = subject:dispatch(step.event)
        assert.equals(step.accepted, result.accepted, scenario.name .. " step " .. index .. " accepted")
        assert.same(step.effects, effect_types(result.effects), scenario.name .. " step " .. index .. " effects")
        if step.model then
          assert_subset(step.model, subject.model, "model after step " .. index)
        end
      end
      assert_subset(scenario.model, subject.model, "model")
    end)
  end
end)

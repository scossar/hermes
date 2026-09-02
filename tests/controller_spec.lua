local machine = require("hermes.machine")

local function load_controller()
  local ok, controller = pcall(require, "hermes.controller")
  assert.is_true(ok)
  return controller
end

describe("Hermes application controller", function()
  it("serializes events dispatched synchronously by effect handlers", function()
    local seen = {}
    local controller
    controller = load_controller().new({
      machine = machine.new(),
      run_effect = function(effect)
        table.insert(seen, effect.type)
        if effect.type == "bridge.start" then
          controller:dispatch({
            type = "bridge.started",
            bridge_generation = effect.bridge_generation,
          })
        end
      end,
    })

    controller:dispatch({ type = "client.open_requested" })

    assert.same({ "bridge.start", "projection.show", "session_store.load" }, seen)
    assert.equals("running", controller:model().bridge.phase)
  end)

  it("restores dispatching and remains usable when a transition throws", function()
    local should_throw = true
    local fake_machine = { model = {} }
    function fake_machine:dispatch()
      if should_throw then
        should_throw = false
        error("transition exploded")
      end
      return { accepted = true, effects = {} }
    end
    local subject = load_controller().new({ machine = fake_machine, run_effect = function() end })
    assert.is_false(pcall(function()
      subject:dispatch({ type = "bad" })
    end))
    assert.is_false(subject.dispatching)
    assert.is_true(subject:dispatch({ type = "good" }).accepted)
  end)
end)

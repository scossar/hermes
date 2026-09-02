local application = require("hermes.application")

local function load_session(fake)
  application.get = function()
    return fake
  end
  package.loaded["hermes.session"] = nil
  return require("hermes.session")
end

describe("hermes session compatibility facade", function()
  local original_get

  before_each(function()
    original_get = application.get
  end)

  after_each(function()
    application.get = original_get
    package.loaded["hermes.session"] = nil
  end)

  it("projects active and durable identity from the application model", function()
    local session = load_session({
      model = function()
        return { session = { phase = "active", live_id = "live-1", durable_id = "durable-1" } }
      end,
    })
    assert.is_true(session.is_active())
    assert.equals("live-1", session.current_session_id())
    assert.equals("durable-1", session.current_stored_session_id())
  end)

  it("serves already-active compatibility callers without owning state", function()
    local fake = {
      model = function()
        return { session = { phase = "active", live_id = "live-1", durable_id = "durable-1" } }
      end,
    }
    local session = load_session(fake)
    local result
    session.ensure_session(function(id, err, details)
      result = { id = id, err = err, details = details }
    end)
    assert.equals("live-1", result.id)
    assert.is_nil(result.err)
    assert.same({}, result.details.messages)
  end)

  it("routes inactive activation through the application", function()
    local opened = 0
    local fake = {
      model = function()
        return { session = { phase = "none" } }
      end,
      open = function()
        opened = opened + 1
      end,
    }
    local session = load_session(fake)
    local err
    session.ensure_session(function(_, value)
      err = value
    end)
    assert.equals(1, opened)
    assert.matches("asynchronous", err.message)
  end)

  it("routes shutdown through the application and settles its callback", function()
    local stopped = 0
    local done = false
    local session = load_session({
      stop = function()
        stopped = stopped + 1
      end,
    })
    session.shutdown(function()
      done = true
    end)
    assert.equals(1, stopped)
    assert.is_true(done)
  end)

  it("routes replacement creation through the application", function()
    local callback
    local session = load_session({
      new_session = function(_, cb)
        callback = cb
        return true
      end,
    })
    local supplied = function() end
    assert.is_true(session.new_session(supplied))
    assert.equals(supplied, callback)
  end)
end)

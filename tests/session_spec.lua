local process = require("hermes.process")
local rpc = require("hermes.rpc")
local session = require("hermes.session")
local config = require("hermes.config")

local function reset_modules()
  package.loaded["hermes.session"] = nil
  session = require("hermes.session")
end

describe("hermes session lifecycle", function()
  local original_start
  local original_request
  local original_send
  local original_stop
  local original_notify
  local original_state_file

  before_each(function()
    reset_modules()
    original_start = process.start
    original_request = rpc.request
    original_send = process.send
    original_stop = process.stop
    original_notify = vim.notify
    original_state_file = config.options.state_file
    config.options.state_file = vim.fn.tempname()
    vim.notify = function() end
  end)

  after_each(function()
    process.start = original_start
    rpc.request = original_request
    process.send = original_send
    process.stop = original_stop
    vim.notify = original_notify
    vim.fn.delete(config.options.state_file)
    config.options.state_file = original_state_file
  end)

  it("queues callers while one session is being created", function()
    local start_count = 0
    local create_result
    process.start = function()
      start_count = start_count + 1
      return true
    end
    rpc.request = function(method, _, on_result)
      assert.equals("session.create", method)
      create_result = on_result
    end

    local results = {}
    session.ensure_session(function(id)
      table.insert(results, id)
    end)
    session.ensure_session(function(id)
      table.insert(results, id)
    end)
    create_result({ session_id = "live-id", stored_session_id = "stored-id" })

    assert.equals(1, start_count)
    assert.same({ "live-id", "live-id" }, results)
  end)

  it("clears the live session when the bridge exits", function()
    local on_exit
    process.start = function(_, _, exit_cb)
      on_exit = exit_cb
      return true
    end
    rpc.request = function(_, _, on_result)
      on_result({ session_id = "live-id", stored_session_id = "stored-id" })
    end

    session.ensure_session(function() end)
    assert.is_true(session.is_active())
    on_exit(1)
    assert.is_false(session.is_active())
  end)

  it("notifies listeners when an active bridge disconnects", function()
    local on_exit
    process.start = function(_, _, exit_cb)
      on_exit = exit_cb
      return true
    end
    rpc.request = function(_, _, on_result)
      on_result({ session_id = "live-id", stored_session_id = "stored-id" })
    end

    local disconnected = false
    session.on_disconnect(function()
      disconnected = true
    end)
    session.ensure_session(function() end)
    on_exit(1)

    assert.is_true(disconnected)
  end)

  it("reports session creation failure to every waiting caller", function()
    local create_error
    process.start = function()
      return true
    end
    rpc.request = function(_, _, _, on_error)
      create_error = on_error
    end

    local errors = {}
    session.ensure_session(function(_, err)
      table.insert(errors, err.message)
    end)
    session.ensure_session(function(_, err)
      table.insert(errors, err.message)
    end)
    create_error({ message = "not connected" })

    assert.same({
      "session.create failed: not connected",
      "session.create failed: not connected",
    }, errors)
    assert.is_false(session.is_active())
  end)

  it("settles an initial bridge failure and allows a later retry", function()
    local exits = {}
    local requests = {}
    local notifications = {}
    local starts = 0
    process.start = function(_, _, on_exit)
      starts = starts + 1
      table.insert(exits, on_exit)
      return true
    end
    process.send = function(message)
      table.insert(requests, message)
    end
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    local errors = {}
    session.ensure_session(function(_, err)
      table.insert(errors, err and err.message)
    end)
    session.ensure_session(function(_, err)
      table.insert(errors, err and err.message)
    end)

    assert.equals(1, starts)
    exits[1](1)
    assert.same(
      { "session.create failed: bridge process exited", "session.create failed: bridge process exited" },
      errors
    )
    assert.equals(1, starts)
    assert.same({ "hermes: session.create failed: bridge process exited" }, notifications)

    local recovered
    session.ensure_session(function(id, err)
      assert.is_nil(err)
      recovered = id
    end)
    assert.equals(2, starts)
    rpc.handle_message({
      id = requests[2].id,
      result = { session_id = "live-id", stored_session_id = "stored-id" },
    })

    assert.equals("live-id", recovered)
    assert.is_true(session.is_active())
  end)

  it("queues an immediate retry until the previous bridge exits", function()
    local exits = {}
    local create_error
    local starts = 0
    process.start = function(_, _, on_exit)
      starts = starts + 1
      table.insert(exits, on_exit)
      return true
    end
    process.stop = function() end
    rpc.request = function(_, _, _, on_error)
      create_error = on_error
    end

    session.ensure_session(function() end)
    create_error({ message = "first failed" })
    session.ensure_session(function() end)
    assert.equals(1, starts)

    exits[1](0)
    assert.equals(2, starts)
  end)

  it("resumes the persisted durable session before creating a new one", function()
    require("hermes.state").save(config.options.state_file, "stored-id")
    process.start = function()
      return true
    end
    local request
    rpc.request = function(method, params, on_result)
      request = { method = method, params = params }
      on_result({
        session_id = "live-id",
        session_key = "stored-id",
        resumed = "stored-id",
        messages = { { role = "user", text = "Earlier" } },
      })
    end

    local result
    session.ensure_session(function(id, err, details)
      result = { id = id, err = err, details = details }
    end)

    assert.equals("session.resume", request.method)
    assert.equals("stored-id", request.params.session_id)
    assert.equals("hermes.nvim", request.params.source)
    assert.equals("live-id", result.id)
    assert.equals("Earlier", result.details.messages[1].text)
  end)

  it("persists the durable id returned by session.create", function()
    process.start = function()
      return true
    end
    rpc.request = function(method, _, on_result)
      assert.equals("session.create", method)
      on_result({ session_id = "live-id", stored_session_id = "stored-id" })
    end

    session.ensure_session(function() end)

    assert.equals("stored-id", require("hermes.state").load(config.options.state_file))
  end)

  it("forces bridge shutdown when session.close does not answer", function()
    local stopped = false
    process.start = function()
      return true
    end
    process.stop = function()
      stopped = true
    end
    rpc.request = function(method, _, on_result)
      if method == "session.create" then
        on_result({ session_id = "live-id", stored_session_id = "stored-id" })
      end
    end

    session.ensure_session(function() end)
    session.shutdown()
    vim.wait(1500, function()
      return stopped
    end)

    assert.is_true(stopped)
  end)
end)

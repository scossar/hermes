local buffer = require("hermes.buffer")
local chat = require("hermes.chat")
local rpc = require("hermes.rpc")
local session = require("hermes.session")

describe("hermes basic chat", function()
  local original_ensure_session
  local original_request
  local original_on_disconnect
  local notifications
  local original_notify

  before_each(function()
    buffer.reset()
    chat.reset()
    chat.setup()
    original_ensure_session = session.ensure_session
    original_request = rpc.request
    original_on_disconnect = session.on_disconnect
    original_notify = vim.notify
    notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end
  end)

  after_each(function()
    session.ensure_session = original_ensure_session
    rpc.request = original_request
    session.on_disconnect = original_on_disconnect
    vim.notify = original_notify
    chat.reset()
    buffer.reset()
  end)

  it("submits a prompt and streams only events from its session", function()
    session.ensure_session = function(cb)
      cb("runtime-session")
    end

    local submitted
    rpc.request = function(method, params)
      submitted = { method = method, params = params }
    end

    chat.ask("Hello")
    rpc.handle_message({
      method = "event",
      params = {
        type = "message.delta",
        session_id = "other-session",
        payload = { text = "ignore me" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "message.delta",
        session_id = "runtime-session",
        payload = { text = "Hi" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "message.delta",
        session_id = "runtime-session",
        payload = { text = " there" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "message.complete",
        session_id = "runtime-session",
        payload = { text = "Hi there", status = "complete" },
      },
    })

    assert.same({
      method = "prompt.submit",
      params = { session_id = "runtime-session", text = "Hello" },
    }, submitted)
    assert.same({
      "## You",
      "",
      "Hello",
      "",
      "## Hermes",
      "",
      "Hi there",
    }, vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false))
    assert.is_false(chat.is_running())
  end)

  it("uses complete text when the server emitted no deltas", function()
    session.ensure_session = function(cb)
      cb("runtime-session")
    end
    rpc.request = function() end

    chat.ask("Hello")
    rpc.handle_message({
      method = "event",
      params = {
        type = "message.complete",
        session_id = "runtime-session",
        payload = { text = "Complete response", status = "complete" },
      },
    })

    assert.same({
      "## You",
      "",
      "Hello",
      "",
      "## Hermes",
      "",
      "Complete response",
    }, vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false))
  end)

  it("rejects a second prompt while session creation is pending", function()
    session.ensure_session = function() end

    chat.ask("First")
    chat.ask("Second")

    assert.is_true(chat.is_running())
    assert.matches("wait for the current response", notifications[#notifications])
    assert.same(
      { "## You", "", "First", "", "## Hermes", "", "" },
      vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false)
    )
  end)

  it("recovers when the bridge disconnects during a response", function()
    local disconnect
    session.on_disconnect = function(cb)
      disconnect = cb
    end
    chat.setup()
    session.ensure_session = function(cb)
      cb("runtime-session")
    end
    rpc.request = function() end

    chat.ask("Hello")
    disconnect()

    assert.is_false(chat.is_running())
    assert.matches(
      "Connection lost",
      table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    )
  end)

  it("recovers when session creation fails", function()
    session.ensure_session = function(cb)
      cb(nil, { message = "connection failed" })
    end

    chat.ask("Hello")

    assert.is_false(chat.is_running())
    assert.matches(
      "connection failed",
      table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    )
  end)
end)

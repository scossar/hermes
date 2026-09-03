local buffer = require("hermes.buffer")
local application = require("hermes.application")
local process = require("hermes.process")
local rpc = require("hermes.rpc")
local session_store = require("hermes.session_store")

local function app()
  return application.get()
end

local function transcript()
  return table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
end

describe("Hermes application integration", function()
  local original = {}
  local requests
  local receiver
  local on_exit
  local notifications

  before_each(function()
    original.start = process.start
    original.stop = process.stop
    original.request = rpc.request
    original.on_event = rpc.on_event
    original.load = session_store.load
    original.save = session_store.save
    original.notify = vim.notify
    requests = {}
    notifications = {}
    process.start = function(_, _, exit_callback)
      on_exit = exit_callback
      return true
    end
    process.stop = function() end
    rpc.on_event = function(handler)
      receiver = handler
    end
    rpc.request = function(method, params, success, failure)
      table.insert(requests, { method = method, params = params, success = success, failure = failure })
    end
    session_store.load = function()
      return nil
    end
    session_store.save = function()
      return true
    end
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
    application.reset()
    buffer.reset()
  end)

  after_each(function()
    process.start = original.start
    process.stop = original.stop
    rpc.request = original.request
    rpc.on_event = original.on_event
    session_store.load = original.load
    session_store.save = original.save
    vim.notify = original.notify
    application.reset()
    buffer.reset()
  end)

  local function activate(messages)
    assert.equals("session.create", requests[1].method)
    requests[1].success({ session_id = "live-1", stored_session_id = "durable-1", messages = messages or {} })
  end

  local function begin(prompt, options)
    assert.is_true(app():submit(prompt, options))
    activate()
    assert.equals("prompt.submit", requests[2].method)
  end

  local function event(kind, seq, payload, sid)
    receiver({ type = kind, session_id = sid or "live-1", seq = seq, payload = payload or {} })
  end

  it("submits a prompt and streams only events from its session", function()
    begin("Hello")
    event("message.delta", 1, { text = "ignore" }, "other")
    event("message.delta", 2, { text = "Hi" })
    event("message.complete", 3, { text = "Hi there", status = "complete" })
    assert.same({ session_id = "live-1", text = "Hello" }, requests[2].params)
    assert.matches("Hi there", transcript())
    assert.is_nil(transcript():match("ignore"))
    assert.is_false(app():is_running())
  end)

  it("keeps trimming direct prompts", function()
    begin("  indented prompt  \n")
    assert.equals("indented prompt", requests[2].params.text)
  end)

  it("uses complete text when the server emitted no deltas", function()
    begin("Hello")
    event("message.complete", 1, { text = "Complete response", status = "complete" })
    assert.matches("Complete response", transcript())
  end)

  it("sends selected text without duplicating it and delimits the response", function()
    local bufnr = buffer.ensure_buffer()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Selected prompt" })
    assert.is_true(app():submit("Selected prompt", { selection = true, delimiter = true }))
    activate()
    event("message.complete", 1, { text = "Selected response", status = "complete" })
    assert.equals(1, select(2, transcript():gsub("Selected prompt", "")))
    assert.matches("%-%-%-", transcript())
  end)

  it("replaces streamed text with the authoritative completed response", function()
    begin("Hello")
    event("message.delta", 1, { text = "Draft answer" })
    event("message.complete", 2, { text = "Final corrected answer", status = "complete" })
    assert.matches("Final corrected answer", transcript())
    assert.is_nil(transcript():match("Draft answer"))
  end)

  it("surfaces a recoverable turn error in the transcript", function()
    begin("Long task")
    event("message.complete", 1, {
      status = "error",
      error = "Response truncated due to output length limit",
      recoverable = true,
    })
    assert.matches("Hermes turn failed", transcript())
    assert.matches("conversation is still available", transcript())
    assert.equals(vim.log.levels.ERROR, notifications[#notifications].level)
  end)

  it("preserves streamed output when a recoverable error omits completion text", function()
    begin("Long task")
    event("message.delta", 1, { text = "Useful partial result" })
    event("message.complete", 2, { status = "error", error = "stream failed", partial = true, recoverable = true })
    assert.matches("Useful partial result", transcript())
    assert.matches("stream failed", transcript())
  end)

  it("uses authoritative partial completion text before the error warning", function()
    begin("Long task")
    event("message.delta", 1, { text = "Draft partial" })
    event(
      "message.complete",
      2,
      { text = "Authoritative partial", status = "error", error = "provider failed", partial = true }
    )
    assert.matches("Authoritative partial", transcript())
    assert.is_nil(transcript():match("Draft partial"))
  end)

  it("finishes safely when error fields are malformed", function()
    begin("Long task")
    assert.is_true(
      pcall(event, "message.complete", 1, { text = { "bad" }, status = "error", error = "", partial = true })
    )
    assert.matches("without an error message", transcript())
    assert.is_false(app():is_running())
  end)

  it("rejects a second prompt while session creation is pending", function()
    assert.is_true(app():submit("First"))
    assert.is_false(app():submit("Second"))
    assert.is_true(app():is_running())
  end)

  it("recovers when the bridge disconnects during a response", function()
    begin("Hello")
    on_exit(1)
    assert.is_false(app():is_running())
    assert.matches("Connection lost", transcript())
  end)

  it("can be stopped during an active response", function()
    begin("Hello")
    app():stop()
    assert.is_false(app():is_running())
    assert.matches("Stopped", transcript())
  end)

  it("interrupts an active turn without closing the session", function()
    begin("Long task")
    requests[2].success({ accepted = true })
    app():interrupt()
    assert.equals("session.interrupt", requests[3].method)
    requests[3].success({ status = "interrupted" })
    assert.is_true(app():is_running())
    event("message.complete", 1, { status = "interrupted" })
    assert.is_false(app():is_running())
    assert.matches("Interrupted", transcript())
  end)

  it("recovers when session creation fails", function()
    assert.is_true(app():submit("Hello"))
    requests[1].failure({ message = "connection failed" })
    assert.is_false(app():is_running())
    assert.matches("connection failed", transcript())
  end)

  it("hydrates the scratch buffer when opening a resumed session", function()
    session_store.load = function()
      return "durable-1"
    end
    app():open()
    requests[1].success({
      session_id = "live-1",
      stored_session_id = "durable-1",
      messages = {
        { role = "user", text = "Earlier question" },
        { role = "assistant", text = "Earlier answer" },
      },
    })
    assert.matches("Earlier question", transcript())
    assert.matches("Earlier answer", transcript())
  end)
end)

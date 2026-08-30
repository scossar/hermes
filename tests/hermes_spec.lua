local hermes = require("hermes")

describe("hermes.nvim", function()
  it("can be set up with default options", function()
    hermes.setup()
    local config = require("hermes.config")
    assert.is_true(config.options.enabled)
    assert.equals("http://127.0.0.1:9119", config.options.bridge_cmd[3])
    assert.matches("/bridge/dist/bridge.js$", config.options.bridge_cmd[2])
  end)

  it("merges user options with defaults", function()
    hermes.setup({ enabled = false })
    local config = require("hermes.config")
    assert.is_false(config.options.enabled)
  end)

  it("sends non-empty prompts to the chat module", function()
    local chat = require("hermes.chat")
    local original_ask = chat.ask
    local prompt
    chat.ask = function(text)
      prompt = text
    end

    hermes.ask("test prompt")

    chat.ask = original_ask
    assert.equals("test prompt", prompt)
  end)

  it("preserves the conversation when a new session cannot be created", function()
    local chat = require("hermes.chat")
    local session = require("hermes.session")
    local original_reset = chat.reset_conversation
    local original_new_session = session.new_session
    local original_notify = vim.notify
    local reset = false
    chat.reset_conversation = function()
      reset = true
    end
    session.new_session = function(callback)
      callback(nil, { message = "could not clear durable session" })
    end
    vim.notify = function() end

    hermes.new_session()

    chat.reset_conversation = original_reset
    session.new_session = original_new_session
    vim.notify = original_notify
    assert.is_false(reset)
  end)

  it("blocks prompts only while a new session is pending", function()
    local chat = require("hermes.chat")
    local session = require("hermes.session")
    local original_new_session = session.new_session
    local original_ensure_session = session.ensure_session
    local original_notify = vim.notify
    local new_session_callback
    local ensure_calls = 0
    local notifications = {}
    chat.reset_conversation()
    session.new_session = function(callback)
      new_session_callback = callback
    end
    session.ensure_session = function()
      ensure_calls = ensure_calls + 1
    end
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()
    hermes.ask("racing prompt")

    assert.equals(0, ensure_calls)
    assert.matches("new session", notifications[#notifications])

    new_session_callback(nil, { message = "could not clear durable session" })
    hermes.ask("prompt after failure")

    session.new_session = original_new_session
    session.ensure_session = original_ensure_session
    vim.notify = original_notify
    chat.stop()
    assert.equals(1, ensure_calls)
  end)

  it("rejects overlapping new sessions until the active replacement succeeds", function()
    local chat = require("hermes.chat")
    local session = require("hermes.session")
    local original_new_session = session.new_session
    local original_ensure_session = session.ensure_session
    local original_notify = vim.notify
    local new_session_callbacks = {}
    local ensure_calls = 0
    local notifications = {}
    chat.reset_conversation()
    session.new_session = function(callback)
      table.insert(new_session_callbacks, callback)
    end
    session.ensure_session = function()
      ensure_calls = ensure_calls + 1
    end
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()
    hermes.new_session()
    hermes.ask("prompt while replacement is pending")

    assert.equals(1, #new_session_callbacks)
    assert.equals(0, ensure_calls)
    assert.matches("new session", notifications[#notifications])

    new_session_callbacks[1]("replacement-session")
    hermes.ask("prompt after replacement")

    session.new_session = original_new_session
    session.ensure_session = original_ensure_session
    vim.notify = original_notify
    chat.stop()
    assert.equals(1, ensure_calls)
  end)

  it("initializes public operations once and still applies later setup options", function()
    local chat = require("hermes.chat")
    local interaction = require("hermes.interaction")
    local events = require("hermes.events")
    local config = require("hermes.config")
    local original = {
      chat_setup = chat.setup,
      chat_open = chat.open,
      interaction_setup = interaction.setup,
      events_setup = events.setup,
    }
    local calls = { chat = 0, interaction = 0, events = 0, open = 0 }
    chat.setup = function()
      calls.chat = calls.chat + 1
    end
    chat.open = function()
      calls.open = calls.open + 1
    end
    interaction.setup = function()
      calls.interaction = calls.interaction + 1
    end
    events.setup = function()
      calls.events = calls.events + 1
    end
    package.loaded["hermes"] = nil
    local fresh_hermes = require("hermes")

    fresh_hermes.open()
    fresh_hermes.setup({ enabled = false })
    fresh_hermes.setup({ enabled = true })

    chat.setup = original.chat_setup
    chat.open = original.chat_open
    interaction.setup = original.interaction_setup
    events.setup = original.events_setup
    package.loaded["hermes"] = nil
    hermes = require("hermes")

    assert.same({ chat = 1, interaction = 1, events = 1, open = 1 }, calls)
    assert.is_true(config.options.enabled)
  end)
end)

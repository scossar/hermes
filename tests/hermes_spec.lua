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

  it("preserves the existing nil return after sending a selection", function()
    local chat = require("hermes.chat")
    local selection = require("hermes.selection")
    local original_ask_selection = chat.ask_selection
    local original_current = selection.current
    local submitted
    chat.ask_selection = function(text)
      submitted = text
      return true
    end
    selection.current = function()
      return "Selected text"
    end

    local result = hermes.ask_selection()

    chat.ask_selection = original_ask_selection
    selection.current = original_current
    assert.is_nil(result)
    assert.equals("Selected text", submitted)
  end)

  it("opens the composer through the public API", function()
    local composer = require("hermes.composer")
    local original_open = composer.open
    local open_calls = 0
    composer.open = function()
      open_calls = open_calls + 1
    end

    hermes.compose()

    composer.open = original_open
    assert.equals(1, open_calls)
  end)

  it("preserves the conversation when a new session cannot be created", function()
    local chat = require("hermes.chat")
    local original_reset = chat.reset_conversation
    local original_new_session = chat.new_session
    local original_notify = vim.notify
    local reset = false
    chat.reset_conversation = function()
      reset = true
    end
    chat.new_session = function(callback)
      callback(nil, { message = "could not persist replacement" })
      return true
    end
    vim.notify = function() end

    hermes.new_session()

    chat.reset_conversation = original_reset
    chat.new_session = original_new_session
    vim.notify = original_notify
    assert.is_false(reset)
  end)

  it("reports a rejected new-session transition", function()
    local chat = require("hermes.chat")
    local original_new_session = chat.new_session
    local original_notify = vim.notify
    local notifications = {}
    chat.new_session = function()
      return false
    end
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()

    chat.new_session = original_new_session
    vim.notify = original_notify
    assert.matches("new session", notifications[#notifications])
  end)

  it("rejects overlapping new sessions until the active replacement succeeds", function()
    local chat = require("hermes.chat")
    local original_new_session = chat.new_session
    local original_notify = vim.notify
    local calls = 0
    local notifications = {}
    chat.new_session = function()
      calls = calls + 1
      return calls == 1
    end
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()
    hermes.new_session()

    chat.new_session = original_new_session
    vim.notify = original_notify
    assert.equals(2, calls)
    assert.matches("new session", notifications[#notifications])
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

    assert.same({ chat = 1, interaction = 0, events = 0, open = 1 }, calls)
    assert.is_true(config.options.enabled)
  end)
end)

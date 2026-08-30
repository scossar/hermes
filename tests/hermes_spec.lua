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

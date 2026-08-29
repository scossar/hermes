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
end)

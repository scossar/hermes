local hermes = require("hermes")
local application = require("hermes.application")

local function stub_application(subject)
  local original_get = application.get
  application.get = function()
    return subject
  end
  return function()
    application.get = original_get
  end
end

describe("hermes.nvim", function()
  it("does not retain the legacy chat compatibility module", function()
    assert.equals(0, vim.fn.filereadable("lua/hermes/chat.lua"))
  end)

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

  it("sends non-empty prompts directly to the application", function()
    local prompt
    local restore = stub_application({
      submit = function(_, text)
        prompt = text
      end,
    })

    hermes.ask("test prompt")

    restore()
    assert.equals("test prompt", prompt)
  end)

  it("preserves the existing nil return after sending a selection", function()
    local selection = require("hermes.selection")
    local original_current = selection.current
    local submitted
    local submitted_options
    local restore = stub_application({
      submit = function(_, text, options)
        submitted = text
        submitted_options = options
        return true
      end,
    })
    selection.current = function()
      return "Selected text"
    end

    local result = hermes.ask_selection()

    restore()
    selection.current = original_current
    assert.is_nil(result)
    assert.equals("Selected text", submitted)
    assert.same({ selection = true, delimiter = true }, submitted_options)
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

  it("reports a failed new-session transition", function()
    local original_notify = vim.notify
    local notifications = {}
    local restore = stub_application({
      new_session = function(_, callback)
        callback(nil, { message = "could not persist replacement" })
        return true
      end,
    })
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()

    restore()
    vim.notify = original_notify
    assert.matches("could not persist replacement", notifications[#notifications])
  end)

  it("reports a rejected new-session transition", function()
    local original_notify = vim.notify
    local notifications = {}
    local restore = stub_application({
      new_session = function()
        return false
      end,
    })
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()

    restore()
    vim.notify = original_notify
    assert.matches("new session", notifications[#notifications])
  end)

  it("rejects overlapping new sessions until the active replacement succeeds", function()
    local original_notify = vim.notify
    local calls = 0
    local notifications = {}
    local restore = stub_application({
      new_session = function()
        calls = calls + 1
        return calls == 1
      end,
    })
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()
    hermes.new_session()

    restore()
    vim.notify = original_notify
    assert.equals(2, calls)
    assert.matches("new session", notifications[#notifications])
  end)

  it("initializes public operations once and still applies later setup options", function()
    local config = require("hermes.config")
    local open_calls = 0
    local restore = stub_application({
      open = function()
        open_calls = open_calls + 1
      end,
    })
    package.loaded["hermes"] = nil
    local fresh_hermes = require("hermes")

    fresh_hermes.open()
    fresh_hermes.setup({ enabled = false })
    fresh_hermes.setup({ enabled = true })

    restore()
    package.loaded["hermes"] = nil
    hermes = require("hermes")

    assert.equals(1, open_calls)
    assert.is_true(config.options.enabled)
  end)
end)

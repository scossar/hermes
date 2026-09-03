local hermes = require("hermes")
local application = require("hermes.application")
local composer = require("hermes.composer")
local selection = require("hermes.selection")

local original

local function stub_application(subject)
  application.get = function()
    return subject
  end
end

describe("hermes.nvim", function()
  before_each(function()
    original = {
      application_get = application.get,
      composer_open = composer.open,
      selection_current = selection.current,
      notify = vim.notify,
      hermes_module = package.loaded["hermes"],
    }
  end)

  after_each(function()
    application.get = original.application_get
    composer.open = original.composer_open
    selection.current = original.selection_current
    vim.notify = original.notify
    package.loaded["hermes"] = original.hermes_module
    hermes = original.hermes_module
  end)

  it("does not retain the legacy chat compatibility module", function()
    assert.same({}, vim.api.nvim_get_runtime_file("lua/hermes/chat.lua", false))
  end)

  it("does not retain the legacy session compatibility module", function()
    assert.same({}, vim.api.nvim_get_runtime_file("lua/hermes/session.lua", false))
  end)

  it("can be set up with default options", function()
    hermes.setup()
    local config = require("hermes.config")
    assert.is_string(config.options.session_store_file)
    assert.is_nil(config.options.state_file)
    assert.equals("http://127.0.0.1:9119", config.options.bridge_cmd[3])
    assert.matches("/bridge/dist/bridge.js$", config.options.bridge_cmd[2])
  end)

  it("merges user options with defaults", function()
    hermes.setup({ composer_height = 14 })
    local config = require("hermes.config")
    assert.equals(14, config.options.composer_height)
  end)

  it("sends non-empty prompts directly to the application", function()
    local prompt
    stub_application({
      submit = function(_, text)
        prompt = text
      end,
    })

    hermes.ask("test prompt")

    assert.equals("test prompt", prompt)
  end)

  it("preserves the existing nil return after sending a selection", function()
    local submitted
    local submitted_options
    stub_application({
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

    assert.is_nil(result)
    assert.equals("Selected text", submitted)
    assert.same({ selection = true, delimiter = true }, submitted_options)
  end)

  it("opens the composer through the public API", function()
    local open_calls = 0
    composer.open = function()
      open_calls = open_calls + 1
    end

    hermes.compose()

    assert.equals(1, open_calls)
  end)

  it("stops through the application", function()
    local stop_calls = 0
    stub_application({
      stop = function()
        stop_calls = stop_calls + 1
      end,
    })

    hermes.stop()

    assert.equals(1, stop_calls)
  end)

  it("does not notify when the application accepts an interrupt", function()
    local notifications = {}
    stub_application({
      interrupt = function()
        return true
      end,
    })
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end

    hermes.interrupt()

    assert.same({}, notifications)
  end)

  it("notifies when the application rejects an interrupt", function()
    local notifications = {}
    stub_application({
      interrupt = function()
        return false
      end,
    })
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end

    hermes.interrupt()

    assert.equals(1, #notifications)
    assert.equals("hermes: no active turn to interrupt", notifications[1].message)
    assert.equals(vim.log.levels.INFO, notifications[1].level)
  end)

  it("reports a failed new-session transition", function()
    local notifications = {}
    stub_application({
      new_session = function(_, callback)
        callback(nil, { message = "could not persist replacement" })
        return true
      end,
    })
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()

    assert.matches("could not persist replacement", notifications[#notifications])
  end)

  it("reports a rejected new-session transition", function()
    local notifications = {}
    stub_application({
      new_session = function()
        return false
      end,
    })
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    hermes.new_session()

    assert.matches("new session", notifications[#notifications])
  end)

  it("rejects overlapping new sessions until the active replacement succeeds", function()
    local calls = 0
    local notifications = {}
    stub_application({
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

    assert.equals(2, calls)
    assert.matches("new session", notifications[#notifications])
  end)

  it("applies defaults before the first public operation and accepts later setup options", function()
    local config = require("hermes.config")
    local open_calls = 0
    stub_application({
      open = function()
        open_calls = open_calls + 1
      end,
    })
    package.loaded["hermes"] = nil
    local fresh_hermes = require("hermes")

    fresh_hermes.open()
    fresh_hermes.setup({ composer_height = 12 })
    fresh_hermes.setup({ composer_height = 14 })

    assert.equals(1, open_calls)
    assert.equals(14, config.options.composer_height)
  end)
end)

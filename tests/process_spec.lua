local process = require("hermes.process")

describe("hermes bridge process", function()
  local original_system
  local original_notify

  before_each(function()
    package.loaded["hermes.process"] = nil
    process = require("hermes.process")
    original_system = vim.system
    original_notify = vim.notify
  end)

  after_each(function()
    vim.system = original_system
    vim.notify = original_notify
  end)

  it("leaves bridge failure reporting to the session lifecycle", function()
    local system_options
    local system_exit
    local exited
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end
    vim.system = function(_, options, on_exit)
      system_options = options
      system_exit = on_exit
      return { write = function() end }
    end

    process.start({ "bridge" }, function() end, function(code)
      exited = code
    end)
    system_options.stderr(nil, "bridge failed: connection refused\n")
    system_exit({ code = 1 })
    vim.wait(100, function()
      return exited ~= nil
    end)

    assert.equals(1, exited)
    assert.same({}, notifications)
  end)
end)

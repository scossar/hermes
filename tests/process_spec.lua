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

  it("rejects decoded bridge frames that are not tables", function()
    local system_options
    local received = false
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end
    vim.system = function(_, options)
      system_options = options
      return { write = function() end }
    end

    process.start({ "bridge" }, function()
      received = true
    end)
    system_options.stdout(nil, "null\n")
    vim.wait(100, function()
      return #notifications > 0
    end)

    assert.is_false(received)
    assert.matches("invalid JSON frame", notifications[1])
  end)

  it("returns false when vim.system raises during startup", function()
    vim.system = function()
      error("ENOENT: node executable not found")
    end

    local ok, started = pcall(process.start, { "node", "bridge.js" }, function() end)

    assert.is_true(ok)
    assert.is_false(started)
  end)
end)

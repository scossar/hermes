describe("transcript commands", function()
  local original_hermes
  local original_notify
  local calls
  local command_names = {
    "Hermes",
    "HermesStop",
    "HermesCompose",
    "HermesInterrupt",
    "HermesNew",
    "HermesSendSelection",
    "HermesSaveTranscript",
    "HermesSaveSelection",
  }

  before_each(function()
    original_hermes = package.loaded["hermes"]
    original_notify = vim.notify
    calls = {}
    package.loaded["hermes"] = {
      save_transcript = function(...)
        calls.transcript = { ... }
      end,
      save_selection = function(...)
        calls.selection = { ... }
      end,
    }
    vim.g.loaded_hermes = nil
    vim.cmd("runtime plugin/hermes.lua")
  end)

  after_each(function()
    for _, name in ipairs(command_names) do
      pcall(vim.api.nvim_del_user_command, name)
    end
    vim.g.loaded_hermes = nil
    package.loaded["hermes"] = original_hermes
    vim.notify = original_notify
  end)

  it("registers and dispatches HermesSaveTranscript arguments", function()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    assert.is_not_nil(commands.HermesSaveTranscript)

    vim.cmd("HermesSaveTranscript /tmp chat")

    assert.same({ "/tmp", "chat" }, calls.transcript)
  end)

  it("registers HermesSaveSelection as a range command", function()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    assert.is_not_nil(commands.HermesSaveSelection)
    assert.equals(".", commands.HermesSaveSelection.range)

    vim.cmd("1,1HermesSaveSelection /tmp excerpt")

    assert.same({ "/tmp", "excerpt" }, calls.selection)
  end)

  it("joins every argument after the path into the filename", function()
    vim.cmd("HermesSaveTranscript /tmp This is a test")

    assert.same({ "/tmp", "This is a test" }, calls.transcript)
  end)

  it("requires both a path and a filename", function()
    local notifications = {}
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end

    vim.cmd("HermesSaveTranscript /tmp")

    assert.is_nil(calls.transcript)
    assert.matches("path filename$", notifications[1].message)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
  end)
end)

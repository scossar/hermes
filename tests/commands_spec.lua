describe("transcript commands", function()
  local original_hermes
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
  end)

  it("registers and dispatches HermesSaveTranscript arguments", function()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    assert.is_not_nil(commands.HermesSaveTranscript)

    vim.cmd("HermesSaveTranscript /tmp chat append")

    assert.same({ "/tmp", "chat", "append" }, calls.transcript)
  end)

  it("registers HermesSaveSelection as a range command", function()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    assert.is_not_nil(commands.HermesSaveSelection)
    assert.equals(".", commands.HermesSaveSelection.range)

    vim.cmd("1,1HermesSaveSelection /tmp excerpt overwrite")

    assert.same({ "/tmp", "excerpt", "overwrite" }, calls.selection)
  end)
end)

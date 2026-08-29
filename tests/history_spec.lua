local buffer = require("hermes.buffer")
local history = require("hermes.history")

describe("session history rendering", function()
  before_each(function()
    buffer.reset()
  end)

  after_each(function()
    buffer.reset()
  end)

  it("renders user and assistant messages into the scratch transcript", function()
    history.render({
      { role = "user", text = "Earlier question" },
      { role = "assistant", text = "Earlier answer" },
    })

    assert.same({
      "## You",
      "",
      "Earlier question",
      "",
      "## Hermes",
      "",
      "Earlier answer",
      "",
      "---",
    }, vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false))
  end)

  it("renders persisted reasoning and tool rows without treating them as chat", function()
    history.render({
      { role = "assistant", text = "", reasoning = "Considered options" },
      { role = "tool", name = "web_search", context = "query docs" },
    })

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("Reasoning", text)
    assert.matches("Considered options", text)
    assert.matches("web_search", text)
  end)
end)

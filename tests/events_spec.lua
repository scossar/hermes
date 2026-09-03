local buffer = require("hermes.buffer")
local events = require("hermes.events")

describe("tool and reasoning event projection", function()
  before_each(function()
    buffer.reset()
    events.begin_turn()
  end)

  after_each(function()
    events.end_turn()
    buffer.reset()
  end)

  it("renders streamed reasoning in a disclosure block", function()
    events.render("reasoning.delta", { text = "Considering" })
    events.render("reasoning.delta", { text = " options" })

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("<summary>Reasoning</summary>", text)
    assert.matches("Considering options", text)
  end)

  it("renders tool start, progress, and completion as one updated row", function()
    events.render("tool.start", { tool_id = "tool-1", name = "web_search", context = "query docs" })
    events.render("tool.progress", { tool_id = "tool-1", name = "web_search", preview = "found docs" })
    events.render("tool.complete", {
      tool_id = "tool-1",
      name = "web_search",
      summary = "3 results",
      duration_s = 1.2,
    })

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("web_search", text)
    assert.matches("3 results", text)
    assert.equals(1, select(2, text:gsub("web_search", "")))
  end)

  it("keeps tool and reasoning rows separate from the streamed answer", function()
    buffer.append_user("Question")
    buffer.begin_assistant()
    events.render("reasoning.delta", { text = "Thought" })
    events.render("tool.start", { tool_id = "tool-1", name = "read_file" })
    buffer.append("Answer")
    buffer.replace_assistant("Final answer")
    buffer.finish_assistant()

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("Thought", text)
    assert.matches("read_file", text)
    assert.matches("Final answer", text)
    assert.is_nil(text:match("read_file.*Final answer.*read_file"))
  end)

  it("ignores activity after the turn ends", function()
    events.end_turn()
    events.render("reasoning.delta", { text = "stale" })

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.is_nil(text:match("stale"))
  end)
end)

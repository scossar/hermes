local buffer = require("hermes.buffer")
local events = require("hermes.events")
local rpc = require("hermes.rpc")
local session = require("hermes.session")

describe("tool and reasoning events", function()
  local original_session_id

  before_each(function()
    buffer.reset()
    original_session_id = session.current_session_id
    session.current_session_id = function()
      return "live-session"
    end
    events.setup()
    events.begin_turn()
  end)

  after_each(function()
    session.current_session_id = original_session_id
    buffer.reset()
  end)

  it("renders streamed reasoning in a disclosure block", function()
    rpc.handle_message({
      method = "event",
      params = {
        type = "reasoning.delta",
        session_id = "live-session",
        payload = { text = "Considering" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "reasoning.delta",
        session_id = "live-session",
        payload = { text = " options" },
      },
    })

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("<summary>Reasoning</summary>", text)
    assert.matches("Considering options", text)
  end)

  it("renders tool start, progress, and completion as one updated row", function()
    rpc.handle_message({
      method = "event",
      params = {
        type = "tool.start",
        session_id = "live-session",
        payload = { tool_id = "tool-1", name = "web_search", context = "query docs" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "tool.progress",
        session_id = "live-session",
        payload = { tool_id = "tool-1", name = "web_search", preview = "found docs" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "tool.complete",
        session_id = "live-session",
        payload = { tool_id = "tool-1", name = "web_search", summary = "3 results", duration_s = 1.2 },
      },
    })

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("web_search", text)
    assert.matches("3 results", text)
    assert.equals(1, select(2, text:gsub("web_search", "")))
  end)

  it("keeps tool and reasoning rows separate from the streamed answer", function()
    buffer.append_user("Question")
    buffer.begin_assistant()
    rpc.handle_message({
      method = "event",
      params = {
        type = "reasoning.delta",
        session_id = "live-session",
        payload = { text = "Thought" },
      },
    })
    rpc.handle_message({
      method = "event",
      params = {
        type = "tool.start",
        session_id = "live-session",
        payload = { tool_id = "tool-1", name = "read_file" },
      },
    })
    buffer.append("Answer")
    buffer.replace_assistant("Final answer")
    buffer.finish_assistant()

    local text = table.concat(vim.api.nvim_buf_get_lines(buffer.ensure_buffer(), 0, -1, false), "\n")
    assert.matches("Thought", text)
    assert.matches("read_file", text)
    assert.matches("Final answer", text)
    assert.is_nil(text:match("read_file.*Final answer.*read_file"))
  end)
end)

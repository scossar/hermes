local interaction = require("hermes.interaction")
local rpc = require("hermes.rpc")
local session = require("hermes.session")

local function pick(items, options, callback)
  assert.is_table(items)
  assert.is_string(options.prompt)
  callback(items[1])
end

local function input(options, callback)
  assert.is_string(options.prompt)
  callback("typed answer")
end

describe("interactive Hermes prompts", function()
  local original_select
  local original_input
  local original_request
  local original_session_id

  before_each(function()
    original_select = vim.ui.select
    original_input = vim.ui.input
    original_request = rpc.request
    original_session_id = session.current_session_id
    vim.ui.select = pick
    vim.ui.input = input
    session.current_session_id = function()
      return "live-session"
    end
    interaction.setup()
  end)

  after_each(function()
    vim.ui.select = original_select
    vim.ui.input = original_input
    rpc.request = original_request
    session.current_session_id = original_session_id
  end)

  it("answers approval requests with a selected choice", function()
    local sent
    rpc.request = function(method, params)
      sent = { method = method, params = params }
    end

    rpc.handle_message({
      method = "event",
      params = {
        type = "approval.request",
        session_id = "live-session",
        payload = {
          request_id = "approval-1",
          command = "rm file",
          description = "Remove a file",
          choices = { "once", "deny" },
        },
      },
    })

    assert.same({
      method = "approval.respond",
      params = {
        session_id = "live-session",
        request_id = "approval-1",
        choice = "once",
      },
    }, sent)
  end)

  it("answers a single clarification question", function()
    local sent
    rpc.request = function(method, params)
      sent = { method = method, params = params }
    end

    rpc.handle_message({
      method = "event",
      params = {
        type = "clarify.request",
        session_id = "live-session",
        payload = { request_id = "clarify-1", question = "Which file?" },
      },
    })

    assert.same({
      method = "clarify.respond",
      params = {
        session_id = "live-session",
        request_id = "clarify-1",
        answer = "typed answer",
      },
    }, sent)
  end)

  it("locks each answer in a batch clarification", function()
    local sent = {}
    rpc.request = function(method, params, on_result)
      table.insert(sent, { method = method, params = params })
      if on_result then
        on_result({ status = "ok" })
      end
    end

    rpc.handle_message({
      method = "event",
      params = {
        type = "clarify.request",
        session_id = "live-session",
        payload = {
          request_id = "clarify-batch",
          questions = {
            { qid = "q1", question = "First?", choices = { "one" } },
            { qid = "q2", question = "Second?" },
          },
        },
      },
    })

    assert.equals(2, #sent)
    assert.equals("q1", sent[1].params.question_id)
    assert.equals("one", sent[1].params.answer)
    assert.equals("q2", sent[2].params.question_id)
    assert.equals("typed answer", sent[2].params.answer)
  end)

  it("cancels an entire clarification batch without opening later questions", function()
    local prompts = 0
    vim.ui.select = function(_, _, callback)
      prompts = prompts + 1
      callback(nil)
    end
    local sent
    rpc.request = function(method, params)
      sent = { method = method, params = params }
    end

    rpc.handle_message({
      method = "event",
      params = {
        type = "clarify.request",
        session_id = "live-session",
        payload = {
          request_id = "batch",
          questions = {
            { qid = "q1", question = "First?", choices = { "one" } },
            { qid = "q2", question = "Second?", choices = { "two" } },
          },
        },
      },
    })

    assert.equals(1, prompts)
    assert.is_nil(sent.params.question_id)
    assert.equals("", sent.params.answer)
  end)
end)

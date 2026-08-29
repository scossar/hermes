local rpc = require("hermes.rpc")
local session = require("hermes.session")

local M = {}

local function respond(method, payload)
  payload.session_id = session.current_session_id()
  rpc.request(method, payload, nil, function(err)
    vim.notify(string.format("hermes: %s failed: %s", method, err.message or "unknown error"), vim.log.levels.ERROR)
  end)
end

local function ask_question(request_id, question, question_id, done)
  local choices = question.choices
  local function answer(value)
    if value == nil then
      value = ""
    end
    respond("clarify.respond", {
      request_id = request_id,
      question_id = question_id,
      answer = value,
    })
    done()
  end

  if question.multi_select and choices and #choices > 0 then
    vim.ui.input({
      prompt = (question.question or "Choose one or more values") .. " (comma-separated) ",
      default = table.concat(choices, ", "),
    }, answer)
  elseif choices and #choices > 0 then
    vim.ui.select(choices, { prompt = question.question or "Hermes needs clarification" }, answer)
  else
    vim.ui.input({ prompt = (question.question or "Hermes needs clarification") .. " " }, answer)
  end
end

local function handle_clarify(params)
  local payload = params.payload or {}
  local questions = payload.questions
  if questions and #questions > 0 then
    local index = 1
    local function next_question()
      local question = questions[index]
      if not question then
        return
      end
      index = index + 1
      ask_question(payload.request_id, question, question.qid, next_question)
    end
    next_question()
    return
  end

  ask_question(payload.request_id, {
    question = payload.question,
    choices = payload.choices,
    multi_select = payload.multi_select,
  }, nil, function() end)
end

local function handle_approval(params)
  local payload = params.payload or {}
  local choices = payload.choices or { "once", "session", "always", "deny" }
  local prompt = payload.description or "Hermes requests command approval"
  if payload.command and payload.command ~= "" then
    prompt = string.format("%s\n%s", prompt, payload.command)
  end
  vim.ui.select(choices, { prompt = prompt }, function(choice)
    respond("approval.respond", {
      request_id = payload.request_id,
      choice = choice or "deny",
    })
  end)
end

function M.setup()
  rpc.on_event("approval.request", handle_approval)
  rpc.on_event("clarify.request", handle_clarify)
end

return M

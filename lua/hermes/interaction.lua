local rpc = require("hermes.rpc")
local session = require("hermes.session")
local approval = require("hermes.approval")

local M = {}

local epoch = 0

local function current(sid, my_epoch)
  return my_epoch == epoch and sid and sid == session.current_session_id()
end

local function respond(method, sid, my_epoch, payload, on_result)
  if not current(sid, my_epoch) then
    return
  end
  payload.session_id = sid
  rpc.request(method, payload, function(result)
    if current(sid, my_epoch) and on_result then
      on_result(result or {})
    end
  end, function(err)
    if current(sid, my_epoch) then
      vim.notify(string.format("hermes: %s failed: %s", method, err.message or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

local function choose_answer(question, callback)
  local choices = question.choices
  if type(choices) ~= "table" then
    choices = nil
  end
  if question.multi_select and choices and #choices > 0 then
    local items = vim.list_extend({ "Done" }, choices)
    local selected = {}
    local function choose()
      vim.ui.select(items, { prompt = question.question or "Choose one or more values" }, function(choice)
        if choice == nil then
          callback(nil)
        elseif choice == "Done" then
          callback(vim.json.encode(selected))
        else
          table.insert(selected, choice)
          choose()
        end
      end)
    end
    choose()
  elseif choices and #choices > 0 then
    vim.ui.select(choices, { prompt = question.question or "Hermes needs clarification" }, callback)
  else
    vim.ui.input({ prompt = (question.question or "Hermes needs clarification") .. " " }, callback)
  end
end

local function handle_clarify(params)
  local sid = params.session_id
  if sid ~= session.current_session_id() then
    return
  end
  local my_epoch = epoch
  local payload = params.payload or {}
  local questions = payload.questions
  if type(questions) == "table" and #questions > 0 then
    local index = 1
    local locked = type(payload.answers) == "table" and payload.answers or {}
    local function next_question()
      if not current(sid, my_epoch) then
        return
      end
      local question = questions[index]
      if not question then
        return
      end
      if locked[question.qid] ~= nil then
        index = index + 1
        next_question()
        return
      end
      choose_answer(question, function(answer)
        if answer == nil then
          respond("clarify.respond", sid, my_epoch, { request_id = payload.request_id, answer = "" })
          return
        end
        respond("clarify.respond", sid, my_epoch, {
          request_id = payload.request_id,
          question_id = question.qid,
          answer = answer,
        }, function(result)
          if result.status == "expired" then
            return
          end
          index = index + 1
          next_question()
        end)
      end)
    end
    next_question()
    return
  end

  choose_answer(payload, function(answer)
    respond("clarify.respond", sid, my_epoch, {
      request_id = payload.request_id,
      answer = answer or "",
    })
  end)
end

local function handle_approval(params)
  local sid = params.session_id
  if sid ~= session.current_session_id() then
    return
  end
  local my_epoch = epoch
  local payload = params.payload or {}
  approval.open(payload, function(choice)
    respond("approval.respond", sid, my_epoch, {
      request_id = payload.request_id,
      choice = choice,
    }, function(result)
      if result.resolved == 0 then
        vim.notify("hermes: approval was no longer pending", vim.log.levels.WARN)
      end
    end)
  end)
end

function M.setup()
  rpc.on_event("approval.request", handle_approval)
  rpc.on_event("clarify.request", handle_clarify)
end

function M.handle_pending(details, sid)
  if type(details) ~= "table" then
    return
  end
  if details.pending_approval then
    handle_approval({ session_id = sid, payload = details.pending_approval })
  end
  if details.pending_clarify then
    handle_clarify({ session_id = sid, payload = details.pending_clarify })
  end
end

function M.invalidate()
  epoch = epoch + 1
  approval.close()
end

-- Passive UI ports used by the controller runtime. These functions collect a
-- user decision but never send RPC or decide whether the request is current.
function M.show_approval(request, callback)
  approval.open(request or {}, callback)
end

function M.show_clarification(request, callback)
  request = request or {}
  local question = request
  if type(request.questions) == "table" and request.questions[1] then
    question = request.questions[1]
  end
  choose_answer(question, function(answer)
    callback({ question_id = question.qid, answer = answer or "", cancelled = answer == nil })
  end)
end

return M

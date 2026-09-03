local approval = require("hermes.approval")

local M = {}

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

function M.invalidate()
  approval.close()
end

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

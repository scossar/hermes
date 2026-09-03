local interaction = require("hermes.interaction")
local approval = require("hermes.approval")

local function pick(items, options, callback)
  assert.is_table(items)
  assert.is_string(options.prompt)
  callback(items[1])
end

local function input(options, callback)
  assert.is_string(options.prompt)
  callback("typed answer")
end

describe("interactive Hermes UI ports", function()
  local original_select
  local original_input

  before_each(function()
    approval.close()
    original_select = vim.ui.select
    original_input = vim.ui.input
    vim.ui.select = pick
    vim.ui.input = input
  end)

  after_each(function()
    approval.close()
    vim.ui.select = original_select
    vim.ui.input = original_input
  end)

  it("returns an approval choice from the dedicated approval window", function()
    local choice
    interaction.show_approval({
      request_id = "approval-1",
      command = "rm file",
      description = "Remove a file",
      choices = { "once", "deny" },
    }, function(value)
      choice = value
    end)

    assert.equals("hermes://approval", vim.api.nvim_buf_get_name(0))
    assert.matches("Remove a file", table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), 1, true)
    vim.api.nvim_feedkeys("1", "x", false)

    assert.equals("once", choice)
  end)

  it("returns a typed clarification answer", function()
    local answer
    interaction.show_clarification({ qid = "q1", question = "Which file?" }, function(value)
      answer = value
    end)

    assert.same({ question_id = "q1", answer = "typed answer", cancelled = false }, answer)
  end)

  it("returns cancellation without inventing an answer", function()
    vim.ui.select = function(_, _, callback)
      callback(nil)
    end
    local answer
    interaction.show_clarification({ qid = "q1", question = "Continue?", choices = { "yes" } }, function(value)
      answer = value
    end)

    assert.same({ question_id = "q1", answer = "", cancelled = true }, answer)
  end)

  it("invalidates an open approval", function()
    interaction.show_approval({ description = "Pending", choices = { "once", "deny" } }, function() end)
    local approval_buffer = vim.api.nvim_get_current_buf()

    interaction.invalidate()

    assert.is_false(vim.api.nvim_buf_is_valid(approval_buffer))
  end)
end)

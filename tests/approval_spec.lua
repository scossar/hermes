local approval = require("hermes.approval")

local function delete_approval_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == "hermes://approval" then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
end

describe("hermes approval UI", function()
  before_each(function()
    approval.close()
    delete_approval_buffers()
  end)

  after_each(function()
    approval.close()
    delete_approval_buffers()
  end)

  it("shows a long multiline request in a scrollable Markdown window", function()
    local description = table.concat({
      "Hermes wants to run a command that needs careful review.",
      "",
      string.rep("Long context for the approval request. ", 20),
    }, "\n")
    local command = "printf 'first line\\n' && \\\n  printf 'second line\\n'"

    approval.open({
      description = description,
      command = command,
      choices = { "once", "session", "deny" },
    }, function() end)

    local bufnr = vim.api.nvim_get_current_buf()
    local winid = vim.api.nvim_get_current_win()
    local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

    assert.equals("hermes://approval", vim.api.nvim_buf_get_name(bufnr))
    assert.equals("markdown", vim.bo[bufnr].filetype)
    assert.is_false(vim.bo[bufnr].modifiable)
    assert.is_true(vim.wo[winid].wrap)
    assert.equals(1, vim.api.nvim_win_get_cursor(winid)[1])
    assert.matches(description, text, 1, true)
    assert.matches(command, text, 1, true)
    assert.matches("1. Allow once", text, 1, true)
    assert.matches("2. Allow for this session", text, 1, true)
    assert.matches("3. Deny", text, 1, true)
  end)

  it("selects a choice with its displayed number", function()
    local selected
    approval.open({ choices = { "once", "session", "deny" } }, function(choice)
      selected = choice
    end)
    local winid = vim.api.nvim_get_current_win()

    vim.api.nvim_feedkeys("2", "x", false)

    assert.equals("session", selected)
    assert.is_false(vim.api.nvim_win_is_valid(winid))
  end)

  it("selects the choice under the cursor with Enter", function()
    local selected
    approval.open({ choices = { "once", "session", "deny" } }, function(choice)
      selected = choice
    end)
    local bufnr = vim.api.nvim_get_current_buf()
    local choice_line
    for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line == "3. Deny" then
        choice_line = index
      end
    end
    vim.api.nvim_win_set_cursor(0, { choice_line, 0 })

    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)

    assert.equals("deny", selected)
  end)

  it("treats closing the approval window as a denial", function()
    local selected
    approval.open({ choices = { "once", "deny" } }, function(choice)
      selected = choice
    end)

    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)

    assert.equals("deny", selected)
  end)

  it("denies an existing request before showing its replacement", function()
    local first_choice
    local second_choice
    approval.open({ description = "First request" }, function(choice)
      first_choice = choice
    end)

    approval.open({ description = "Second request" }, function(choice)
      second_choice = choice
    end)

    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert.equals("deny", first_choice)
    assert.is_nil(second_choice)
    assert.matches("Second request", text, 1, true)
  end)

  it("denies without closing a window repurposed to another buffer", function()
    local selected
    approval.open({}, function(choice)
      selected = choice
    end)
    local winid = vim.api.nvim_get_current_win()
    local replacement = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(winid, replacement)

    assert.equals("deny", selected)
    assert.is_true(vim.api.nvim_win_is_valid(winid))
    assert.equals(replacement, vim.api.nvim_win_get_buf(winid))
  end)

  it("fits inside a small editor", function()
    local original_columns = vim.o.columns
    local original_lines = vim.o.lines
    vim.o.columns = 18
    vim.o.lines = 6

    local ok, err = pcall(approval.open, {}, function() end)
    local config
    if ok then
      config = vim.api.nvim_win_get_config(0)
    end

    approval.close()
    vim.o.columns = original_columns
    vim.o.lines = original_lines

    assert.is_true(ok, err)
    assert.is_true(config.width <= 16)
    assert.is_true(config.height <= 4)
  end)
end)

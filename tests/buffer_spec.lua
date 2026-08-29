local buffer = require("hermes.buffer")

describe("hermes chat buffer", function()
  after_each(function()
    buffer.reset()
  end)

  it("creates a temporary markdown buffer", function()
    local bufnr = buffer.ensure_buffer()

    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    assert.equals("markdown", vim.bo[bufnr].filetype)
    assert.equals("hide", vim.bo[bufnr].bufhidden)
    assert.is_false(vim.bo[bufnr].buflisted)
  end)

  it("appends streamed fragments without adding artificial newlines", function()
    local bufnr = buffer.ensure_buffer()

    buffer.append("Hello")
    buffer.append(" world\nNext")
    buffer.append(" line")

    assert.same({ "Hello world", "Next line" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("adds distinct user and assistant sections", function()
    local bufnr = buffer.ensure_buffer()

    buffer.append_user("First question")
    buffer.begin_assistant()
    buffer.append("First answer")
    buffer.finish_assistant()
    buffer.append_user("Second question")

    assert.same({
      "## You",
      "",
      "First question",
      "",
      "## Hermes",
      "",
      "First answer",
      "",
      "## You",
      "",
      "Second question",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("replaces the current assistant response", function()
    local bufnr = buffer.ensure_buffer()
    buffer.append_user("Question")
    buffer.begin_assistant()
    buffer.append("Draft")

    buffer.replace_assistant("Final")

    assert.same(
      { "## You", "", "Question", "", "## Hermes", "", "Final" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it("opens in a split when the current buffer cannot be abandoned", function()
    local current = vim.api.nvim_get_current_buf()
    vim.bo[current].modified = true
    local old_hidden = vim.o.hidden
    vim.o.hidden = false

    assert.has_no.errors(buffer.show)
    vim.o.hidden = old_hidden
    assert.equals(buffer.ensure_buffer(), vim.api.nvim_get_current_buf())
  end)
end)

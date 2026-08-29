local selection = require("hermes.selection")

describe("visual selection", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "first line",
      "second line",
      "third line",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("returns a linewise selection", function()
    local text = selection.get(bufnr, 1, 3, 2, 1, "V")

    assert.equals("first line\nsecond line", text)
  end)

  it("returns the selected columns for a characterwise selection", function()
    local text = selection.get(bufnr, 1, 3, 2, 6, "v")

    assert.equals("rst line\nsecond", text)
  end)

  it("normalizes a backwards characterwise selection", function()
    local text = selection.get(bufnr, 2, 6, 1, 3, "v")

    assert.equals("rst line\nsecond", text)
  end)
end)

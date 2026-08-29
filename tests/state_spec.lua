local state = require("hermes.state")

describe("durable session state", function()
  local path

  before_each(function()
    path = vim.fn.tempname()
  end)

  after_each(function()
    vim.fn.delete(path)
  end)

  it("persists and loads a stored session id", function()
    state.save(path, "stored-session")

    assert.equals("stored-session", state.load(path))
  end)

  it("returns nil for missing or malformed state", function()
    assert.is_nil(state.load(path))
    vim.fn.writefile({ "not json" }, path)
    assert.is_nil(state.load(path))
  end)

  it("clears persisted state", function()
    state.save(path, "stored-session")
    state.clear(path)

    assert.is_nil(state.load(path))
  end)
end)

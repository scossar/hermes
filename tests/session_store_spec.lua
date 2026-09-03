local session_store = require("hermes.session_store")

describe("durable session store", function()
  local path
  local original_delete
  local original_filereadable
  local original_isdirectory
  local original_mkdir

  before_each(function()
    path = vim.fn.tempname()
    original_delete = vim.fn.delete
    original_filereadable = vim.fn.filereadable
    original_isdirectory = vim.fn.isdirectory
    original_mkdir = vim.fn.mkdir
  end)

  after_each(function()
    vim.fn.delete = original_delete
    vim.fn.filereadable = original_filereadable
    vim.fn.isdirectory = original_isdirectory
    vim.fn.mkdir = original_mkdir
    vim.fn.delete(path)
  end)

  it("persists and loads a stored session id", function()
    session_store.save(path, "stored-session")

    assert.equals("stored-session", session_store.load(path))
  end)

  it("returns nil for missing or malformed data", function()
    assert.is_nil(session_store.load(path))
    vim.fn.writefile({ "not json" }, path)
    assert.is_nil(session_store.load(path))
  end)

  it("clears persisted data", function()
    session_store.save(path, "stored-session")
    session_store.clear(path)

    assert.is_nil(session_store.load(path))
  end)

  it("reports a session store directory creation failure", function()
    vim.fn.mkdir = function()
      return 0
    end
    vim.fn.isdirectory = function()
      return 0
    end

    local ok, err = session_store.save(path .. "/session.json", "stored-session")

    assert.is_false(ok)
    assert.equals("could not create session store directory", err)
  end)

  it("reports a session store file deletion failure", function()
    vim.fn.filereadable = function()
      return 1
    end
    vim.fn.delete = function()
      return 1
    end

    local ok, err = session_store.clear(path)

    assert.is_false(ok)
    assert.equals("could not delete session store file", err)
  end)
end)

local config = require("hermes.config")
local transcript = require("hermes.transcript")

local function read_lines(path)
  return vim.fn.readfile(path)
end

describe("transcript export", function()
  local directory
  local original_select
  local original_notify

  before_each(function()
    directory = vim.fn.tempname()
    assert.equals(1, vim.fn.mkdir(directory, "p"))
    original_select = vim.ui.select
    original_notify = vim.notify
    config.options = vim.tbl_deep_extend("force", {}, config.defaults)
  end)

  after_each(function()
    vim.ui.select = original_select
    vim.notify = original_notify
    vim.fn.delete(directory, "rf")
  end)

  it("writes markdown and appends the extension when the filename has none", function()
    local path = transcript.save({ "# Chat", "", "Hello" }, directory, "conversation", "overwrite")

    assert.equals(directory .. "/conversation.md", path)
    assert.same({ "# Chat", "", "Hello" }, read_lines(path))
  end)

  it("preserves an existing filename extension", function()
    local path = transcript.save({ "Chat" }, directory, "conversation.markdown", "overwrite")

    assert.equals(directory .. "/conversation.markdown", path)
    assert.same({ "Chat" }, read_lines(path))
  end)

  it("appends when append is explicit", function()
    local path = directory .. "/conversation.md"
    vim.fn.writefile({ "Existing" }, path)

    transcript.save({ "Added" }, directory, "conversation", "append")

    assert.same({ "Existing", "Added" }, read_lines(path))
  end)

  it("asks before replacing an existing file when no mode is supplied", function()
    local path = directory .. "/conversation.md"
    local choices
    local options
    vim.fn.writefile({ "Existing" }, path)
    vim.ui.select = function(items, opts, callback)
      choices = items
      options = opts
      callback("overwrite")
    end

    transcript.save({ "Replacement" }, directory, "conversation")

    assert.same({ "append", "overwrite", "cancel" }, choices)
    assert.matches("already exists", options.prompt)
    assert.same({ "Replacement" }, read_lines(path))
  end)

  it("leaves an existing file unchanged when the prompt is cancelled", function()
    local path = directory .. "/conversation.md"
    vim.fn.writefile({ "Existing" }, path)
    vim.ui.select = function(_, _, callback)
      callback("cancel")
    end

    transcript.save({ "Replacement" }, directory, "conversation")

    assert.same({ "Existing" }, read_lines(path))
  end)

  it("rejects unsupported save modes", function()
    local notifications = {}
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end

    local result = transcript.save({ "Chat" }, directory, "conversation", "replace")

    assert.is_false(result)
    assert.matches("append or overwrite", notifications[1].message)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
  end)

  it("completes configured transcript directories without restricting other paths", function()
    config.options.transcript_directories = { "~/obsidian_vault", "~/projects/python/notes" }

    assert.same(
      { "~/obsidian_vault" },
      transcript.complete("~/o", "HermesSaveTranscript ~/o", #"HermesSaveTranscript ~/o")
    )
    assert.same({}, transcript.complete("notes", "HermesSaveTranscript /tmp notes", #"HermesSaveTranscript /tmp notes"))
    assert.same(
      { "append", "overwrite" },
      transcript.complete("", "HermesSaveTranscript /tmp notes ", #"HermesSaveTranscript /tmp notes ")
    )
    assert.same(
      { "append", "overwrite" },
      transcript.complete(
        "",
        "HermesSaveTranscript ~/my\\ notes excerpt ",
        #"HermesSaveTranscript ~/my\\ notes excerpt "
      )
    )
  end)
end)

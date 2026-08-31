local composer = require("hermes.composer")

local function delete_composer_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == "hermes://compose" then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
end

describe("hermes composer", function()
  before_each(function()
    vim.cmd("only")
    delete_composer_buffers()
  end)

  after_each(function()
    vim.cmd("only")
    delete_composer_buffers()
  end)

  it("opens an unlisted Markdown draft below the transcript", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    local open_calls = 0
    chat.open = function()
      open_calls = open_calls + 1
    end

    composer.open()

    chat.open = original_open
    local bufnr = vim.api.nvim_get_current_buf()
    assert.equals(1, open_calls)
    assert.equals("hermes://compose", vim.api.nvim_buf_get_name(bufnr))
    assert.equals("markdown", vim.bo[bufnr].filetype)
    assert.is_false(vim.bo[bufnr].buflisted)
    assert.equals(2, #vim.api.nvim_list_wins())
    assert.equals(10, vim.api.nvim_win_get_height(0))
  end)

  it("returns to the existing draft without opening another split", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    chat.open = function() end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Keep this draft" })
    vim.cmd("wincmd p")

    composer.open()

    chat.open = original_open
    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
    assert.same({ "Keep this draft" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(2, #vim.api.nvim_list_wins())
  end)

  it("reopens a hidden draft without discarding it", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    chat.open = function() end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Hidden draft" })
    vim.cmd("close")
    composer.open()

    chat.open = original_open
    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
    assert.same({ "Hidden draft" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(2, #vim.api.nvim_list_wins())
  end)

  it("submits the complete multiline draft deliberately", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    local original_ask = chat.ask
    local submitted
    chat.open = function() end
    chat.ask = function(prompt, options)
      submitted = prompt
      options.on_accept(true)
      return true
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "First paragraph.", "", "```lua", "print('hi')", "```" })
    vim.cmd("HermesSubmit")

    chat.open = original_open
    chat.ask = original_ask
    assert.equals("First paragraph.\n\n```lua\nprint('hi')\n```", submitted)
    assert.is_false(vim.api.nvim_buf_is_valid(draft_bufnr))
  end)

  it("preserves edits made while submission is awaiting acceptance", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    local original_ask = chat.ask
    local on_accept
    chat.open = function() end
    chat.ask = function(_, options)
      on_accept = options.on_accept
      return true
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Submitted draft" })
    vim.cmd("HermesSubmit")
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "New unsent draft" })
    on_accept(true)

    chat.open = original_open
    chat.ask = original_ask
    assert.is_true(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.same({ "New unsent draft" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
  end)

  it("does not close a window repurposed before acceptance", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    local original_ask = chat.ask
    local on_accept
    chat.open = function() end
    chat.ask = function(_, options)
      on_accept = options.on_accept
      return true
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Submitted draft" })
    vim.cmd("HermesSubmit")
    local repurposed_winid = vim.api.nvim_get_current_win()
    local replacement_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(repurposed_winid, replacement_bufnr)
    on_accept(true)

    chat.open = original_open
    chat.ask = original_ask
    assert.is_true(vim.api.nvim_win_is_valid(repurposed_winid))
    assert.equals(replacement_bufnr, vim.api.nvim_win_get_buf(repurposed_winid))
    assert.is_false(vim.api.nvim_buf_is_valid(draft_bufnr))
  end)

  it("closes a composer reopened before acceptance", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    local original_ask = chat.ask
    local on_accept
    chat.open = function() end
    chat.ask = function(_, options)
      on_accept = options.on_accept
      return true
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Submitted draft" })
    vim.cmd("HermesSubmit")
    vim.cmd("close")
    composer.open()
    on_accept(true)

    chat.open = original_open
    chat.ask = original_ask
    assert.is_false(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.equals(1, #vim.api.nvim_list_wins())
  end)

  it("preserves the draft when Hermes cannot accept it", function()
    local chat = require("hermes.chat")
    local original_open = chat.open
    local original_ask = chat.ask
    chat.open = function() end
    chat.ask = function()
      return false
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Do not lose this" })
    vim.cmd("HermesSubmit")

    chat.open = original_open
    chat.ask = original_ask
    assert.is_true(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.same({ "Do not lose this" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
  end)

  it("preserves the draft when session acceptance fails", function()
    local chat = require("hermes.chat")
    local session = require("hermes.session")
    local original_ensure_session = session.ensure_session
    local ensure_calls = 0
    chat.reset()
    session.ensure_session = function(callback)
      ensure_calls = ensure_calls + 1
      if ensure_calls == 1 then
        callback("runtime-session", nil, { messages = {} })
      else
        callback(nil, { message = "backend unavailable" })
      end
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "  Keep exact whitespace  " })
    vim.cmd("HermesSubmit")
    composer.open()

    session.ensure_session = original_ensure_session
    assert.is_true(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
    assert.same({ "  Keep exact whitespace  " }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    chat.reset()
  end)

  it("closes the composer split after a real chat submission", function()
    local buffer = require("hermes.buffer")
    local chat = require("hermes.chat")
    local rpc = require("hermes.rpc")
    local session = require("hermes.session")
    local original_ensure_session = session.ensure_session
    local original_request = rpc.request
    local submitted
    chat.reset_conversation()
    session.ensure_session = function(callback)
      callback("runtime-session")
    end
    rpc.request = function(method, params, on_success)
      submitted = { method = method, params = params }
      on_success()
    end

    composer.open()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "A deliberate prompt" })
    vim.cmd("HermesSubmit")

    session.ensure_session = original_ensure_session
    rpc.request = original_request
    assert.equals(1, #vim.api.nvim_list_wins())
    assert.same({
      method = "prompt.submit",
      params = { session_id = "runtime-session", text = "A deliberate prompt" },
    }, submitted)
    assert.equals(buffer.ensure_buffer(), vim.api.nvim_get_current_buf())
    chat.reset()
    buffer.reset()
  end)
end)

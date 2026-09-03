local composer = require("hermes.composer")
local application = require("hermes.application")
local buffer = require("hermes.buffer")
local process = require("hermes.process")
local rpc = require("hermes.rpc")
local selection = require("hermes.selection")
local state = require("hermes.state")

local function delete_composer_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == "hermes://compose" then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
end

describe("hermes composer", function()
  local original

  before_each(function()
    original = {
      application_get = application.get,
      process_start = process.start,
      process_stop = process.stop,
      rpc_request = rpc.request,
      rpc_on_event = rpc.on_event,
      selection_current = selection.current,
      state_load = state.load,
      state_save = state.save,
      notify = vim.notify,
    }
    vim.cmd("only")
    delete_composer_buffers()
  end)

  after_each(function()
    application.get = original.application_get
    application.reset()
    process.start = original.process_start
    process.stop = original.process_stop
    rpc.request = original.rpc_request
    rpc.on_event = original.rpc_on_event
    selection.current = original.selection_current
    state.load = original.state_load
    state.save = original.state_save
    vim.notify = original.notify
    buffer.reset()
    vim.cmd("only")
    delete_composer_buffers()
  end)

  local function use_app(subject)
    application.get = function()
      return subject
    end
  end

  it("opens an unlisted Markdown draft below the transcript", function()
    local open_calls = 0
    use_app({
      open = function()
        open_calls = open_calls + 1
      end,
    })

    composer.open()

    local bufnr = vim.api.nvim_get_current_buf()
    assert.equals(1, open_calls)
    assert.equals("hermes://compose", vim.api.nvim_buf_get_name(bufnr))
    assert.equals("markdown", vim.bo[bufnr].filetype)
    assert.is_false(vim.bo[bufnr].buflisted)
    assert.equals(2, #vim.api.nvim_list_wins())
    assert.equals(10, vim.api.nvim_win_get_height(0))
  end)

  it("returns to the existing draft without opening another split", function()
    use_app({ open = function() end })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Keep this draft" })
    vim.cmd("wincmd p")

    composer.open()

    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
    assert.same({ "Keep this draft" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(2, #vim.api.nvim_list_wins())
  end)

  it("reopens a hidden draft without discarding it", function()
    use_app({ open = function() end })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Hidden draft" })
    vim.cmd("close")
    composer.open()

    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
    assert.same({ "Hidden draft" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(2, #vim.api.nvim_list_wins())
  end)

  it("refuses to send a selection from the composer", function()
    local hermes = require("hermes")
    local submit_calls = 0
    local selection_calls = 0
    local notifications = {}
    use_app({
      open = function() end,
      submit = function()
        submit_calls = submit_calls + 1
        return true
      end,
    })
    selection.current = function()
      selection_calls = selection_calls + 1
      return "Selected draft text"
    end
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    local draft_winid = vim.api.nvim_get_current_win()
    local window_count = #vim.api.nvim_list_wins()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Selected draft text", "Unselected draft text" })
    local accepted = hermes.ask_selection()

    assert.is_false(accepted)
    assert.equals(0, submit_calls)
    assert.equals(0, selection_calls)
    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
    assert.equals(draft_winid, vim.api.nvim_get_current_win())
    assert.equals(window_count, #vim.api.nvim_list_wins())
    assert.same(
      { "Selected draft text", "Unselected draft text" },
      vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false)
    )
    assert.equals(1, #notifications)
    assert.equals(
      "hermes: selections from the Compose buffer cannot be sent; use :HermesSubmit",
      notifications[1].message
    )
    assert.equals(vim.log.levels.WARN, notifications[1].level)
  end)

  it("submits the complete multiline draft deliberately", function()
    local submitted
    use_app({
      open = function() end,
      submit = function(_, prompt, options)
        submitted = prompt
        options.on_accept(true)
        return true
      end,
    })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "First paragraph.", "", "```lua", "print('hi')", "```" })
    vim.cmd("HermesSubmit")

    assert.equals("First paragraph.\n\n```lua\nprint('hi')\n```", submitted)
    assert.is_false(vim.api.nvim_buf_is_valid(draft_bufnr))
  end)

  it("preserves edits made while submission is awaiting acceptance", function()
    local on_accept
    use_app({
      open = function() end,
      submit = function(_, _, options)
        on_accept = options.on_accept
        return true
      end,
    })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Submitted draft" })
    vim.cmd("HermesSubmit")
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "New unsent draft" })
    on_accept(true)

    assert.is_true(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.same({ "New unsent draft" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
  end)

  it("does not close a window repurposed before acceptance", function()
    local on_accept
    use_app({
      open = function() end,
      submit = function(_, _, options)
        on_accept = options.on_accept
        return true
      end,
    })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Submitted draft" })
    vim.cmd("HermesSubmit")
    local repurposed_winid = vim.api.nvim_get_current_win()
    local replacement_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(repurposed_winid, replacement_bufnr)
    on_accept(true)

    assert.is_true(vim.api.nvim_win_is_valid(repurposed_winid))
    assert.equals(replacement_bufnr, vim.api.nvim_win_get_buf(repurposed_winid))
    assert.is_false(vim.api.nvim_buf_is_valid(draft_bufnr))
  end)

  it("closes a composer reopened before acceptance", function()
    local on_accept
    use_app({
      open = function() end,
      submit = function(_, _, options)
        on_accept = options.on_accept
        return true
      end,
    })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Submitted draft" })
    vim.cmd("HermesSubmit")
    vim.cmd("close")
    composer.open()
    on_accept(true)

    assert.is_false(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.equals(1, #vim.api.nvim_list_wins())
  end)

  it("preserves the draft when Hermes cannot accept it", function()
    use_app({
      open = function() end,
      submit = function()
        return false
      end,
    })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "Do not lose this" })
    vim.cmd("HermesSubmit")

    assert.is_true(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.same({ "Do not lose this" }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(draft_bufnr, vim.api.nvim_get_current_buf())
  end)

  it("preserves the draft when an accepted submission is later rejected", function()
    local on_accept
    use_app({
      open = function() end,
      submit = function(_, _, options)
        on_accept = options.on_accept
        return true
      end,
    })

    composer.open()
    local draft_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(draft_bufnr, 0, -1, false, { "  Keep exact whitespace  " })
    local was_modified = vim.bo[draft_bufnr].modified
    vim.cmd("HermesSubmit")
    on_accept(false)

    assert.is_true(vim.api.nvim_buf_is_valid(draft_bufnr))
    assert.same({ "  Keep exact whitespace  " }, vim.api.nvim_buf_get_lines(draft_bufnr, 0, -1, false))
    assert.equals(was_modified, vim.bo[draft_bufnr].modified)
  end)

  it("closes the composer split after a real application submission", function()
    local submitted
    application.reset()
    buffer.reset()
    process.start = function()
      return true
    end
    process.stop = function() end
    rpc.on_event = function() end
    state.load = function()
      return nil
    end
    state.save = function()
      return true
    end
    rpc.request = function(method, params, on_success)
      if method == "session.create" then
        on_success({ session_id = "runtime-session", stored_session_id = "durable-session", messages = {} })
      else
        submitted = { method = method, params = params }
        on_success({ accepted = true })
      end
    end

    composer.open()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "A deliberate prompt" })
    vim.cmd("HermesSubmit")

    assert.equals(1, #vim.api.nvim_list_wins())
    assert.same({
      method = "prompt.submit",
      params = { session_id = "runtime-session", text = "A deliberate prompt" },
    }, submitted)
    assert.equals(buffer.ensure_buffer(), vim.api.nvim_get_current_buf())
  end)
end)

local config = require("hermes.config")
local chat = require("hermes.chat")
local selection = require("hermes.selection")
local composer = require("hermes.composer")

local M = {}

local initialized = false

local function initialize()
  if initialized then
    return
  end
  initialized = true
  chat.setup()
end

local function ensure_setup()
  if not initialized then
    M.setup()
  end
end

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", {}, config.defaults, opts or {})
  initialize()
end

function M.ask(prompt)
  ensure_setup()
  chat.ask(prompt)
end

function M.ask_selection()
  ensure_setup()
  if composer.is_buffer(vim.api.nvim_get_current_buf()) then
    vim.notify("hermes: selections from the Compose buffer cannot be sent; use :HermesSubmit", vim.log.levels.WARN)
    return false
  end
  chat.ask_selection(selection.current())
end

function M.open()
  ensure_setup()
  chat.open()
end

function M.compose()
  ensure_setup()
  composer.open()
end

function M.stop()
  ensure_setup()
  chat.stop()
end

function M.interrupt()
  ensure_setup()
  chat.interrupt()
end

function M.new_session()
  ensure_setup()
  if
    not chat.new_session(function(_, err)
      if err then
        vim.notify("hermes: could not create a new session: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
        return
      end
    end)
  then
    vim.notify("hermes: wait for the current response or new session to finish", vim.log.levels.WARN)
  end
end

return M

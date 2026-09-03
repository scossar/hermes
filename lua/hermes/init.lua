local config = require("hermes.config")
local application = require("hermes.application")
local selection = require("hermes.selection")
local composer = require("hermes.composer")

local M = {}

local initialized = false

local function app()
  return application.get()
end

local function ensure_setup()
  if not initialized then
    M.setup()
  end
end

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", {}, config.defaults, opts or {})
  initialized = true
end

function M.ask(prompt)
  ensure_setup()
  app():submit(prompt)
end

function M.ask_selection()
  ensure_setup()
  if composer.is_buffer(vim.api.nvim_get_current_buf()) then
    vim.notify("hermes: selections from the Compose buffer cannot be sent; use :HermesSubmit", vim.log.levels.WARN)
    return false
  end
  app():submit(selection.current(), { selection = true, delimiter = true })
end

function M.open()
  ensure_setup()
  app():open()
end

function M.compose()
  ensure_setup()
  composer.open()
end

function M.stop()
  ensure_setup()
  app():stop()
end

function M.interrupt()
  ensure_setup()
  if not app():interrupt() then
    vim.notify("hermes: no active turn to interrupt", vim.log.levels.INFO)
  end
end

function M.new_session()
  ensure_setup()
  if
    not app():new_session(function(_, err)
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

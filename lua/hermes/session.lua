-- lua/hermes/session.lua
local process = require("hermes.process")
local rpc = require("hermes.rpc")
local config = require("hermes.config")

local M = {}

local session_id = nil
local stored_session_id = nil

function M.is_active()
  return session_id ~= nil
end

function M.current_session_id()
  return session_id
end

function M.ensure_session(cb)
  if session_id then
    cb()
    return
  end

  -- bridge_cmd will be something like { "node" vim.fn.stdpath("data") .. "hermes.nvim/bridge/build/bridge.js", "http://127.0.0.1:9119"}
  process.start(config.options.bridge_cmd, rpc.handle_message)

  rpc.request("session.create", {
    cols = 100,
    cwd = vim.fn.getcwd(),
    source = "hermes.nvim",
    title = "hermes.nvim session",
  }, function(result)
    session_id = result.session_id
    stored_session_id = result.stored_session_id
    cb()
  end, function(err)
    vim.notify("hermes: session.create failed: " .. err.message, vim.log.levels.ERROR)
  end)
end

function M.shutdown()
  if not session_id then
    return
  end
  rpc.request("session.close", { session_id = session_id }, function()
    process.stop()
    session_id = nil
    stored_session_id = nil
  end)
end

return M

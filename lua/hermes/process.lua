local M = {}

-- Module-level state via closures/upvalues, not a metatable "object" —
-- there's only ever one companion process, so a singleton module is the
-- right tool here, not a class.
local job = nil
local buffer = ""
local on_message_cb = nil
local on_exit_cb = nil

local function handle_stdout(err, data)
  if err then
    vim.schedule(function()
      vim.notify("hermes: stdout error: " .. err, vim.log.levels.ERROR)
    end)
    return
  end
  if not data then
    return -- stream closed
  end

  -- Chunks from the pipe are NOT guaranteed to align with JSON message
  -- boundaries -- one write() on the Node side can arrive as multiple
  -- chunks, or several messages can arrive in one chunk. Buffer and
  -- split on newlines rather than assuming data == one message.
  buffer = buffer .. data
  while true do
    local nl = buffer:find("\n", 1, true)
    if not nl then
      break
    end
    local line = buffer:sub(1, nl - 1)
    buffer = buffer:sub(nl + 1)

    if line ~= "" and on_message_cb then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == "table" then
        -- IMPORTANT: this callback fires in libuv's "fast event context",
        -- where most vim.api calls (buffer edits, etc.) are unsafe/disallowed.
        -- vim.schedule() defers the call to Neovim's main event loop.
        vim.schedule(function()
          on_message_cb(decoded)
        end)
      elseif ok then
        vim.schedule(function()
          vim.notify("hermes: invalid JSON frame from bridge", vim.log.levels.WARN)
        end)
      else
        vim.schedule(function()
          vim.notify("hermes: bad JSON from bridge: " .. line, vim.log.levels.WARN)
        end)
      end
    end
  end
end

--- @param cmd table e.g. { "node", "/path/to/bridge.js", "ws://100.x.x.x:8765" }
--- @param on_message fun(msg: table)
--- @param on_exit fun(code: integer)|nil
--- @return boolean
function M.start(cmd, on_message, on_exit)
  if job then
    vim.notify("hermes: process already running", vim.log.levels.WARN)
    return false
  end
  on_message_cb = on_message
  on_exit_cb = on_exit
  buffer = ""

  local ok, started_job = pcall(vim.system, cmd, {
    stdin = true,
    stdout = handle_stdout,
    -- Session lifecycle owns user-facing connection errors. Consuming stderr
    -- here avoids duplicate notifications for the same bridge failure.
    stderr = function() end,
  }, function(obj)
    vim.schedule(function()
      job = nil
      if on_exit_cb then
        on_exit_cb(obj.code)
      end
    end)
  end)
  if not ok then
    return false
  end
  job = started_job
  return true
end

function M.send(msg)
  if not job then
    vim.notify("hermes: process not running", vim.log.levels.ERROR)
    return
  end
  job:write(vim.json.encode(msg) .. "\n")
end

function M.stop()
  if job then
    job:write(nil) -- closes stdin -> triggers stdin "end" -> node closes ws and exits
  end
end

return M

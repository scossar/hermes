local buffer = require("hermes.buffer")
local rpc = require("hermes.rpc")
local session = require("hermes.session")

local M = {}

local reasoning = ""
local tool_ids_by_name = {}

local function relevant(params)
  return params.session_id == session.current_session_id()
end

local function reasoning_event(params)
  if not relevant(params) then
    return
  end
  local text = (params.payload or {}).text or ""
  reasoning = reasoning .. text
  buffer.set_event("reasoning", {
    "<details>",
    "<summary>Reasoning</summary>",
    "",
    unpack(vim.split(reasoning, "\n", { plain = true })),
    "",
    "</details>",
  })
end

local function tool_key(payload)
  local id = payload.tool_id
  if id and id ~= "" then
    if payload.name then
      tool_ids_by_name[payload.name] = id
    end
    return "tool:" .. id
  end
  if payload.name and tool_ids_by_name[payload.name] then
    return "tool:" .. tool_ids_by_name[payload.name]
  end
  return "tool:" .. (payload.name or "unknown")
end

local function tool_event(status)
  return function(params)
    if not relevant(params) then
      return
    end
    local payload = params.payload or {}
    local detail = payload.summary or payload.preview or payload.error or payload.context or ""
    local line = string.format("`%s` %s", payload.name or "tool", status)
    if detail ~= "" then
      line = line .. ": " .. detail
    end
    buffer.set_event(tool_key(payload), { line })
  end
end

function M.setup()
  rpc.on_event("reasoning.delta", reasoning_event)
  rpc.on_event("thinking.delta", reasoning_event)
  rpc.on_event("tool.start", tool_event("started"))
  rpc.on_event("tool.progress", tool_event("working"))
  rpc.on_event("tool.complete", tool_event("complete"))
end

function M.reset_turn()
  reasoning = ""
  tool_ids_by_name = {}
end

return M

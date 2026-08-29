local buffer = require("hermes.buffer")
local rpc = require("hermes.rpc")
local session = require("hermes.session")

local M = {}

local active = false
local reasoning = ""
local tools = {}

local function relevant(params)
  return active and params.session_id == session.current_session_id()
end

local function render()
  local lines = {}
  if reasoning ~= "" then
    vim.list_extend(lines, {
      "<details>",
      "<summary>Reasoning</summary>",
      "",
    })
    vim.list_extend(lines, vim.split(reasoning, "\n", { plain = true }))
    vim.list_extend(lines, { "", "</details>", "" })
  end
  for _, tool in ipairs(tools) do
    local line = string.format("- `%s` — %s", tool.name, tool.status)
    if tool.detail ~= "" then
      line = line .. ": " .. tool.detail:gsub("\n", " ")
    end
    table.insert(lines, line)
  end
  buffer.set_event("agent-events", lines)
end

local function reasoning_event(params)
  if not relevant(params) then
    return
  end
  reasoning = reasoning .. tostring((params.payload or {}).text or "")
  render()
end

local function find_tool(payload)
  if payload.tool_id then
    for _, tool in ipairs(tools) do
      if tool.id == payload.tool_id then
        return tool
      end
    end
  end
  local tool = {
    id = payload.tool_id,
    name = tostring(payload.name or "tool"),
    status = "started",
    detail = "",
  }
  table.insert(tools, tool)
  return tool
end

local function tool_event(status)
  return function(params)
    if not relevant(params) then
      return
    end
    local payload = params.payload or {}
    local tool = find_tool(payload)
    tool.name = tostring(payload.name or tool.name)
    tool.status = status
    tool.detail = tostring(payload.summary or payload.preview or payload.error or payload.context or tool.detail)
    render()
  end
end

function M.setup()
  rpc.on_event("reasoning.delta", reasoning_event)
  rpc.on_event("thinking.delta", reasoning_event)
  rpc.on_event("tool.start", tool_event("started"))
  rpc.on_event("tool.progress", tool_event("working"))
  rpc.on_event("tool.complete", tool_event("complete"))
end

function M.begin_turn()
  active = true
  reasoning = ""
  tools = {}
  buffer.begin_event_turn()
end

function M.end_turn()
  active = false
end

return M

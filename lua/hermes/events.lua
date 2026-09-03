local buffer = require("hermes.buffer")

local M = {}

local active = false
local reasoning = ""
local tools = {}

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

local function reasoning_event(payload)
  reasoning = reasoning .. tostring(payload.text or "")
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

local function tool_event(status, payload)
  local tool = find_tool(payload)
  tool.name = tostring(payload.name or tool.name)
  tool.status = status
  tool.detail = tostring(payload.summary or payload.preview or payload.error or payload.context or tool.detail)
  render()
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

function M.render(activity_type, payload)
  if not active then
    return
  end
  payload = payload or {}
  if activity_type == "reasoning.delta" or activity_type == "thinking.delta" then
    reasoning_event(payload)
  elseif activity_type == "tool.start" then
    tool_event("started", payload)
  elseif activity_type == "tool.progress" then
    tool_event("working", payload)
  elseif activity_type == "tool.complete" then
    tool_event("complete", payload)
  end
end

return M

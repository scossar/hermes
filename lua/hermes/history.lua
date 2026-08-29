local buffer = require("hermes.buffer")

local M = {}

local function text_lines(text)
  return vim.split(text or "", "\n", { plain = true })
end

function M.render(messages)
  buffer.clear()
  local blocks = {}

  for _, message in ipairs(messages or {}) do
    local role = message.role
    local text = message.text or ""
    if role == "user" and text ~= "" then
      table.insert(blocks, { "## You", "", unpack(text_lines(text)) })
    elseif role == "assistant" then
      local reasoning = message.reasoning or message.reasoning_content
      if reasoning and reasoning ~= "" then
        table.insert(
          blocks,
          { "<details>", "<summary>Reasoning</summary>", "", unpack(text_lines(reasoning)), "", "</details>" }
        )
      end
      if text ~= "" then
        local block = { "## Hermes", "" }
        vim.list_extend(block, text_lines(text))
        vim.list_extend(block, { "", "---" })
        table.insert(blocks, block)
      end
    elseif role == "tool" then
      local label = message.name or "tool"
      local context = message.context or ""
      table.insert(blocks, { string.format("`%s` %s", label, context) })
    end
  end

  local lines = {}
  for index, block in ipairs(blocks) do
    if index > 1 then
      table.insert(lines, "")
    end
    vim.list_extend(lines, block)
  end
  buffer.append_block(#lines > 0 and lines or { "" })
end

return M

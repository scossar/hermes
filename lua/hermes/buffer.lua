local M = {}

local bufnr = nil
local assistant_start = nil
local event_regions = {}
local event_namespace = 0

local function set_lines(lines)
  local buf = M.ensure_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

function M.ensure_buffer()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].bufhidden = "hide"
  vim.api.nvim_buf_set_name(bufnr, "hermes://chat")
  return bufnr
end

function M.show()
  local buf = M.ensure_buffer()
  local ok = pcall(vim.api.nvim_set_current_buf, buf)
  if not ok then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(buf)
  end
end

function M.append(text)
  if text == "" then
    return
  end

  local buf = M.ensure_buffer()
  local last_line = vim.api.nvim_buf_line_count(buf) - 1
  local last_line_text = vim.api.nvim_buf_get_lines(buf, last_line, last_line + 1, false)[1] or ""
  local last_col = #last_line_text
  local lines = vim.split(text, "\n", { plain = true })

  vim.api.nvim_buf_set_text(buf, last_line, last_col, last_line, last_col, lines)
end

function M.append_block(lines)
  local buf = M.ensure_buffer()
  local existing = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #existing == 1 and existing[1] == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  end
end

function M.clear()
  local buf = M.ensure_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  assistant_start = nil
  event_regions = {}
end

function M.set_event(key, lines)
  key = tostring(event_namespace) .. ":" .. key
  local normalized = {}
  for _, line in ipairs(lines) do
    vim.list_extend(normalized, vim.split(tostring(line or ""), "\n", { plain = true }))
  end
  lines = normalized
  local buf = M.ensure_buffer()
  local region = event_regions[key]
  if region then
    local old_finish = region.finish
    local old_count = old_finish - region.start
    vim.api.nvim_buf_set_lines(buf, region.start, old_finish, false, lines)
    local delta = #lines - old_count
    region.finish = region.start + #lines
    if assistant_start and region.start < assistant_start then
      assistant_start = assistant_start + delta
    end
    for other_key, other in pairs(event_regions) do
      if other_key ~= key and other.start >= old_finish then
        other.start = other.start + delta
        other.finish = other.finish + delta
      end
    end
    return
  end

  local existing = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local start
  if assistant_start then
    start = assistant_start
    vim.api.nvim_buf_set_lines(buf, start, start, false, lines)
    assistant_start = assistant_start + #lines
  elseif #existing == 1 and existing[1] == "" then
    start = 0
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    start = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  end
  event_regions[key] = { start = start, finish = start + #lines }
end

function M.begin_event_turn()
  event_namespace = event_namespace + 1
  event_regions = {}
end

function M.append_user(text)
  local buf = M.ensure_buffer()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local section = { "## You", "" }
  vim.list_extend(section, vim.split(text, "\n", { plain = true }))

  if #lines == 1 and lines[1] == "" then
    set_lines(section)
  else
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.list_extend({ "" }, section))
  end
end

function M.begin_assistant()
  local buf = M.ensure_buffer()
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "## Hermes", "", "" })
  assistant_start = vim.api.nvim_buf_line_count(buf) - 1
end

function M.replace_assistant(text)
  local buf = M.ensure_buffer()
  if assistant_start == nil then
    return
  end
  vim.api.nvim_buf_set_lines(buf, assistant_start, -1, false, vim.split(text, "\n", { plain = true }))
end

function M.finish_assistant(options)
  options = options or {}
  local buf = M.ensure_buffer()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  while #lines > 1 and lines[#lines] == "" and lines[#lines - 1] == "" do
    table.remove(lines)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if options.delimiter then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "---" })
  end
  assistant_start = nil
end

function M.reset()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  bufnr = nil
  assistant_start = nil
  event_regions = {}
  event_namespace = 0
end

return M

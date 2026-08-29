local M = {}

local bufnr = nil
local assistant_start = nil

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
end

return M

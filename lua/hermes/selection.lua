local M = {}

local function ordered(start_row, start_col, end_row, end_col)
  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    return end_row, end_col, start_row, start_col
  end
  return start_row, start_col, end_row, end_col
end

function M.get(bufnr, start_row, start_col, end_row, end_col, mode)
  start_row, start_col, end_row, end_col = ordered(start_row, start_col, end_row, end_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
  if #lines == 0 then
    return ""
  end

  if mode ~= "V" then
    lines[1] = string.sub(lines[1], start_col)
    if #lines == 1 then
      lines[1] = string.sub(lines[1], 1, end_col - start_col + 1)
    else
      lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end
  end

  return table.concat(lines, "\n")
end

function M.current()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local mode = vim.fn.visualmode()
  return M.get(bufnr, start_pos[2], start_pos[3], end_pos[2], end_pos[3], mode)
end

return M

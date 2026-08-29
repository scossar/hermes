local M = {}

function M.load(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or #lines == 0 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(decoded) ~= "table" or type(decoded.stored_session_id) ~= "string" then
    return nil
  end
  local id = vim.trim(decoded.stored_session_id)
  return id ~= "" and id or nil
end

function M.save(path, stored_session_id)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode({ stored_session_id = stored_session_id }) }, path)
end

function M.clear(path)
  vim.fn.delete(path)
end

return M

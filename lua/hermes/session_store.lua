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
  local dir = vim.fs.dirname(path)
  if vim.fn.mkdir(dir, "p") == 0 and vim.fn.isdirectory(dir) ~= 1 then
    return false, "could not create session store directory"
  end
  local temporary = path .. ".tmp"
  local ok_write, write_err =
    pcall(vim.fn.writefile, { vim.json.encode({ stored_session_id = stored_session_id }) }, temporary)
  if not ok_write then
    return false, tostring(write_err)
  end
  local ok_rename, renamed, rename_err = pcall(vim.uv.fs_rename, temporary, path)
  if not ok_rename or not renamed then
    vim.fn.delete(temporary)
    return false, tostring(rename_err or renamed or "atomic rename failed")
  end
  return true
end

function M.clear(path)
  if vim.fn.filereadable(path) ~= 1 then
    return true
  end
  local result = vim.fn.delete(path)
  if result ~= 0 then
    return false, "could not delete session store file"
  end
  return true
end

return M

local config = require("hermes.config")

local M = {}

local valid_modes = {
  append = true,
  overwrite = true,
}

local function notify_error(message)
  vim.notify("hermes: " .. message, vim.log.levels.ERROR)
end

local function with_markdown_extension(filename)
  local basename = vim.fs.basename(filename)
  if not basename:match("^.+%.[^%.]+$") then
    return filename .. ".md"
  end
  return filename
end

local function write(lines, target, mode)
  local ok, result = pcall(vim.fn.writefile, lines, target, mode == "append" and "a" or "")
  if not ok or result == -1 then
    notify_error("could not save " .. target .. (ok and "" or ": " .. tostring(result)))
    return false
  end
  return target
end

local function save_existing(lines, target, mode)
  if mode then
    return write(lines, target, mode)
  end

  vim.ui.select({ "append", "overwrite", "cancel" }, {
    prompt = target .. " already exists. How should it be saved?",
  }, function(choice)
    if choice == "append" or choice == "overwrite" then
      write(lines, target, choice)
    end
  end)
  return nil
end

function M.save(lines, directory, filename, mode)
  if mode ~= nil and not valid_modes[mode] then
    notify_error("save mode must be append or overwrite")
    return false
  end
  if directory == "" or filename == "" then
    notify_error("path and filename are required")
    return false
  end

  local expanded_directory = vim.fn.expand(directory)
  local directory_stat = vim.uv.fs_stat(expanded_directory)
  if not directory_stat or directory_stat.type ~= "directory" then
    notify_error("transcript directory does not exist: " .. expanded_directory)
    return false
  end

  local target = vim.fs.joinpath(expanded_directory, with_markdown_extension(filename))
  local target_stat = vim.uv.fs_stat(target)
  if target_stat and target_stat.type ~= "file" then
    notify_error("transcript target is not a file: " .. target)
    return false
  end
  if target_stat then
    return save_existing(lines, target, mode)
  end
  return write(lines, target, mode or "overwrite")
end

local function argument_index(command_line, cursor_position)
  local prefix = command_line:sub(1, cursor_position)
  local arguments = prefix:gsub("^%s*%S+", "", 1)
  local count = 0
  local in_token = false
  local escaped = false

  for index = 1, #arguments do
    local character = arguments:sub(index, index)
    if escaped then
      escaped = false
      in_token = true
    elseif character == "\\" then
      escaped = true
      in_token = true
    elseif character:match("%s") then
      in_token = false
    elseif not in_token then
      count = count + 1
      in_token = true
    end
  end

  return in_token and count or count + 1
end

local function add_matching(results, seen, candidates, arg_lead)
  for _, candidate in ipairs(candidates) do
    if vim.startswith(candidate, arg_lead) and not seen[candidate] then
      seen[candidate] = true
      table.insert(results, candidate)
    end
  end
end

function M.complete(arg_lead, command_line, cursor_position)
  local index = argument_index(command_line, cursor_position)
  if index == 3 then
    local results = {}
    add_matching(results, {}, { "append", "overwrite" }, arg_lead)
    return results
  end
  if index ~= 1 then
    return {}
  end

  local results = {}
  add_matching(results, {}, config.options.transcript_directories or {}, arg_lead)
  return results
end

return M

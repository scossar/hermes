local chat = require("hermes.chat")
local config = require("hermes.config")
local buffer = require("hermes.buffer")

local M = {}

local bufnr

local function ensure_buffer()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "hermes://compose")
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_create_user_command(bufnr, "HermesSubmit", function()
    M.submit()
  end, { desc = "Submit this draft to Hermes" })
  return bufnr
end

function M.submit()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local target = bufnr
  local composer_winid = vim.fn.bufwinid(target)
  local prompt = table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), "\n")
  local submitted_tick = vim.api.nvim_buf_get_changedtick(target)
  local was_modified = vim.bo[target].modified
  local function on_accept(accepted)
    if not accepted then
      if vim.api.nvim_buf_is_valid(target) then
        vim.bo[target].modified = was_modified
      end
      return
    end

    if vim.api.nvim_buf_is_valid(target) and vim.api.nvim_buf_get_changedtick(target) ~= submitted_tick then
      return
    end

    for _, winid in ipairs(vim.fn.win_findbuf(target)) do
      if
        vim.api.nvim_win_is_valid(winid)
        and vim.api.nvim_win_get_buf(winid) == target
        and #vim.api.nvim_list_wins() > 1
      then
        vim.api.nvim_win_close(winid, false)
      end
    end
    if vim.api.nvim_buf_is_valid(target) then
      vim.api.nvim_buf_delete(target, { force = true })
    end
    if bufnr == target then
      bufnr = nil
    end
  end

  local transcript_winid = vim.fn.bufwinid(buffer.ensure_buffer())
  if transcript_winid ~= -1 then
    vim.api.nvim_set_current_win(transcript_winid)
  else
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if winid ~= composer_winid then
        vim.api.nvim_set_current_win(winid)
        break
      end
    end
  end

  vim.bo[target].modified = false
  if chat.ask(prompt, { preserve_whitespace = true, on_accept = on_accept }) ~= true then
    if vim.api.nvim_buf_is_valid(target) then
      vim.bo[target].modified = was_modified
    end
    if
      composer_winid ~= -1
      and vim.api.nvim_win_is_valid(composer_winid)
      and vim.api.nvim_win_get_buf(composer_winid) == target
    then
      vim.api.nvim_set_current_win(composer_winid)
    end
    return false
  end

  return true
end

function M.open()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.api.nvim_set_current_win(winid)
      return
    end
  end

  chat.open()
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, ensure_buffer())
  vim.api.nvim_win_set_height(0, config.options.composer_height)
end

return M

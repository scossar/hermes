local M = {}

local active = nil

local choice_labels = {
  once = "Allow once",
  session = "Allow for this session",
  always = "Always allow",
  deny = "Deny",
}

local function append_text(lines, text)
  vim.list_extend(lines, vim.split(tostring(text or ""), "\n", { plain = true }))
end

local function render(payload, choices)
  local lines = { "# Hermes Approval Request", "" }
  append_text(lines, payload.description or "Hermes requests command approval")

  if payload.command and payload.command ~= "" then
    vim.list_extend(lines, { "", "## Command", "", "```sh" })
    append_text(lines, payload.command)
    vim.list_extend(lines, { "```" })
  end

  vim.list_extend(lines, { "", "## Choose", "" })
  local choice_start = #lines + 1
  for index, choice in ipairs(choices) do
    table.insert(lines, string.format("%d. %s", index, choice_labels[choice] or tostring(choice)))
  end
  table.insert(lines, "")
  table.insert(lines, "Press the choice number, or move to a choice and press <Enter>. Press q or <Esc> to deny.")
  return lines, choice_start
end

local function settle(choice)
  if not active then
    return
  end
  local callback = active.callback
  M.close()
  callback(choice)
end

function M.close()
  if not active then
    return
  end
  local winid = active.winid
  local bufnr = active.bufnr
  active = nil
  if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
    vim.api.nvim_win_close(winid, true)
  end
end

function M.open(payload, callback)
  if active then
    settle("deny")
  end
  payload = payload or {}
  local choices = type(payload.choices) == "table" and payload.choices or { "once", "session", "always", "deny" }
  local lines, choice_start = render(payload, choices)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "hermes://approval")
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  local border = vim.o.columns >= 4 and vim.o.lines >= 4 and "rounded" or "none"
  local border_size = border == "none" and 0 or 2
  local available_width = math.max(1, vim.o.columns - border_size)
  local available_height = math.max(1, vim.o.lines - border_size)
  local width = math.min(available_width, math.max(20, math.floor(vim.o.columns * 0.8)))
  local max_height = math.max(8, math.floor(vim.o.lines * 0.7))
  local height = math.min(available_height, max_height, math.max(8, #lines))
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = border,
    title = " Approval required ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
  })
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].cursorline = true
  active = {
    bufnr = bufnr,
    winid = winid,
    callback = callback,
    choices = choices,
    choice_start = choice_start,
  }

  local map_options = { buffer = bufnr, silent = true, nowait = true }
  for index, choice in ipairs(choices) do
    if index <= 9 then
      vim.keymap.set("n", tostring(index), function()
        settle(choice)
      end, map_options)
    end
  end
  vim.keymap.set("n", "<CR>", function()
    if not active or active.bufnr ~= bufnr then
      return
    end
    local index = vim.api.nvim_win_get_cursor(winid)[1] - active.choice_start + 1
    if choices[index] then
      settle(choices[index])
    end
  end, map_options)
  local deny = function()
    settle("deny")
  end
  vim.keymap.set("n", "q", deny, map_options)
  vim.keymap.set("n", "<Esc>", deny, map_options)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(winid),
    once = true,
    callback = function()
      if active and active.winid == winid then
        settle("deny")
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      if active and active.bufnr == bufnr then
        settle("deny")
      end
    end,
  })
  vim.api.nvim_win_set_cursor(winid, { 1, 0 })
end

return M

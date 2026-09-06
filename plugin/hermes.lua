if vim.g.loaded_hermes then
  return
end
vim.g.loaded_hermes = true

vim.api.nvim_create_user_command("Hermes", function(opts)
  if opts.args == "" then
    require("hermes").open()
    return
  end
  require("hermes").ask(opts.args)
end, {
  desc = "Open hermes.nvim or send a prompt",
  nargs = "*",
})

vim.api.nvim_create_user_command("HermesStop", function()
  require("hermes").stop()
end, { desc = "Close the current Hermes connection" })

vim.api.nvim_create_user_command("HermesCompose", function()
  require("hermes").compose()
end, { desc = "Draft a multiline prompt for Hermes" })

vim.api.nvim_create_user_command("HermesInterrupt", function()
  require("hermes").interrupt()
end, { desc = "Interrupt the active Hermes turn" })

vim.api.nvim_create_user_command("HermesNew", function()
  require("hermes").new_session()
end, { desc = "Start a new durable Hermes conversation" })

vim.api.nvim_create_user_command("HermesSendSelection", function()
  require("hermes").ask_selection()
end, {
  desc = "Send the visual selection to Hermes",
  range = true,
})

local function save_command(command, method, opts)
  if #opts.fargs < 2 or #opts.fargs > 3 then
    vim.notify("hermes: usage: :" .. command .. " path filename [append|overwrite]", vim.log.levels.ERROR)
    return
  end
  require("hermes")[method](opts.fargs[1], opts.fargs[2], opts.fargs[3])
end

local function complete_save(arg_lead, command_line, cursor_position)
  return require("hermes.transcript").complete(arg_lead, command_line, cursor_position)
end

vim.api.nvim_create_user_command("HermesSaveTranscript", function(opts)
  save_command("HermesSaveTranscript", "save_transcript", opts)
end, {
  desc = "Save the complete Hermes transcript as Markdown",
  nargs = "+",
  complete = complete_save,
})

vim.api.nvim_create_user_command("HermesSaveSelection", function(opts)
  save_command("HermesSaveSelection", "save_selection", opts)
end, {
  desc = "Save the visual selection as Markdown",
  nargs = "+",
  range = true,
  complete = complete_save,
})

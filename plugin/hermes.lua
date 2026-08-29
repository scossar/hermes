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

vim.api.nvim_create_user_command("HermesSendSelection", function()
  require("hermes").ask_selection()
end, {
  desc = "Send the visual selection to Hermes",
  range = true,
})

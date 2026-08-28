-- Guard against re-loading and against loading in non-Lua-compatible Neovim versions.
if vim.g.loaded_hermes then
  return
end
vim.g.loaded_hermes = true

vim.api.nvim_create_user_command("Hermes", function()
  require("hermes").hello()
end, { desc = "Run hermes.nvim's xample command" })

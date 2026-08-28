-- Bootstraps a minimal environment for running tests with plenary.nvim.
-- Expects plenary.nvim to be available as a sibling directory or installed
-- as a dependency by your CI/test runner.

local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")

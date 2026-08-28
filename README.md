# hermes.nvim

A Neovim plugin.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yourusername/hermes.nvim",
  opts = {},
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "yourusername/hermes.nvim",
  config = function()
    require("hermes").setup({})
  end,
})
```

## Usage

```lua
require("hermes").setup({
  enabled = true,
})
```

Run `:Hermes` to try the example command.

## Development

- Format: `stylua .`
- Test: see `.github/workflows/ci.yml` for the headless test invocation using
  [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s busted-style
  runner.

## License

MIT

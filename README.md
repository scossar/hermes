# hermes.nvim

A small Neovim chat client for a remote [Hermes Agent](https://github.com/NousResearch/hermes-agent) backend.

Version 1 keeps one live conversation in a temporary Markdown buffer. Hermes owns the canonical session and model context; the plugin owns only the local UI and connection process.

The v2 development branch adds durable resume, interactive approvals and
clarifications, tool/reasoning rendering, and turn interruption.

## Requirements

- Neovim 0.10 or later
- Node.js 22 or later
- A running `hermes serve` backend reachable at a local HTTP address

For the loopback-plus-SSH setup, start Hermes on the VPS:

```bash
hermes serve --host 127.0.0.1 --port 9119
```

Then open the tunnel locally:

```bash
ssh -N -L 9119:127.0.0.1:9119 user@vps
```

## Installation

Using lazy.nvim:

```lua
{
  "scossar/hermes",
  branch = "feat/v1-basic-chat", -- development branch
  build = "cd bridge && npm ci && npm run build",
  opts = {},
}
```

The compiled bridge is committed, but the build step ensures it matches the TypeScript source.

## Configuration

```lua
require("hermes").setup({
  bridge_cmd = {
    "node",
    vim.fn.stdpath("data") .. "/lazy/hermes/bridge/dist/bridge.js",
    "http://127.0.0.1:9119",
  },
})
```

The default bridge path is resolved from the plugin's own installation directory, so most installations can use `opts = {}`.

## Usage

Send a prompt:

```vim
:Hermes Explain WebSockets in one paragraph
```

Send visually selected text by selecting it and running:

```vim
:'<,'>HermesSendSelection
```

The command is designed for a visual-mode mapping. For example:

```lua
vim.keymap.set("v", "<leader>z", ":HermesSendSelection<CR>", {
  desc = "Send selection to Hermes",
  silent = true,
})
```

Only the selected text is sent. The plugin does not implicitly attach the
entire current buffer or codebase.

The prompt and streamed response appear in an unlisted temporary Markdown buffer named `hermes://chat`.

Open the existing chat buffer without sending a prompt:

```vim
:Hermes
```

Close the live session and bridge process:

```vim
:HermesStop
```

Interrupt the active turn without ending the conversation:

```vim
:HermesInterrupt
```

Start a new durable conversation and clear the scratch transcript:

```vim
:HermesNew
```

The current durable session ID is stored under Neovim's state directory by
default. Opening `:Hermes` after restarting Neovim resumes that Hermes session
and hydrates the scratch buffer from Hermes's canonical transcript.

When Hermes requests command approval or clarification, hermes.nvim uses
`vim.ui.select()` or `vim.ui.input()`. UI plugins such as dressing.nvim can
customize those prompts without changing hermes.nvim.

Reasoning is rendered in a Markdown `<details>` block. Tool calls are shown as
compact rows that update from started to working to complete.

The temporary buffer remains available until Neovim deletes it. Version 1 supports one live conversation per Neovim instance.

## Current scope

Implemented:

- loopback Hermes bootstrap token retrieval
- JSON-RPC over WebSocket through a Node bridge
- reliable request queueing while waiting for `gateway.ready`
- one live Hermes session tagged `hermes.nvim`
- prompt submission
- streamed `message.delta` rendering
- `message.complete` fallback and turn completion
- basic process-disconnect recovery
- durable session resume and transcript hydration
- new-conversation control
- approval and clarification prompts
- reasoning and tool event rendering
- active-turn interruption

Deferred:

- multiple simultaneous conversations
- richer prompt composition and buffer-context attachment

## Development

```bash
cd bridge
npm ci
npm test
npm run typecheck
npm run build
```

Lua tests use plenary.nvim; see `.github/workflows/ci.yml` for the complete command.

## License

MIT

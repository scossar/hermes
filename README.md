# hermes.nvim

A small Neovim chat client for a remote [Hermes Agent](https://github.com/NousResearch/hermes-agent) backend.

hermes.nvim keeps one live conversation in a temporary Markdown buffer. Hermes
owns the canonical session and model context; the plugin owns only the local UI
and connection process. Durable resume, interactive approvals and
clarifications, tool activity, and turn interruption are supported.

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
}
```

The compiled JavaScript bridge ships with the plugin, so installation does not
require a local build step. Public commands initialize hermes.nvim with its
defaults automatically; `opts = {}` or an explicit `setup()` call is not
required.

## Configuration

```lua
require("hermes").setup({
  session_store_file = vim.fn.stdpath("state") .. "/hermes.nvim/session.json",
  composer_height = 10,
})
```

The default `session_store_file` shown above stores the durable Hermes session
ID used to resume the conversation after Neovim restarts. Override it if you
want the session association stored elsewhere.

The default bridge command runs the bundled bridge with Node.js and connects to
`http://127.0.0.1:9119`. Its script path is resolved from the plugin's actual
installation directory, so it does not depend on a particular plugin manager
or installation path. Override `bridge_cmd` only when using a different local
endpoint, Node.js executable, or bridge wrapper.

## Usage

Send a prompt:

```vim
:Hermes Explain WebSockets in one paragraph
```

Draft a multiline prompt in a separate Markdown buffer:

```vim
:HermesCompose
```

This opens a ten-line horizontal composer beneath the transcript, leaving the
chat response visible and independently scrollable. Edit normally with Vim
motions, then deliberately submit the complete draft from the composer with:

```vim
:HermesSubmit
```

There is no default submit mapping. A successful submission closes the
composer and returns focus to the transcript. If the prompt is empty or a turn
is already active, submission is refused and the draft remains intact. `:close`
hides an unsubmitted composer without discarding it; `:HermesCompose` returns
to that draft. Configure the split height with `composer_height`.

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
entire current buffer or codebase. Selections cannot be sent from the Compose
buffer; use `:HermesSubmit` there so the complete draft is submitted
deliberately.

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

When Hermes requests command approval, hermes.nvim opens a dedicated scrollable
Markdown window. The full description and command remain available for review,
including long multiline requests. Press a displayed choice number, or move the
cursor to a choice and press `<Enter>`. Press `q` or `<Esc>`, or close the
window, to deny the request. Clarification questions continue to use
`vim.ui.select()` or `vim.ui.input()`, so UI plugins such as dressing.nvim can
customize them.

Tool calls are shown as compact rows that update from started to working to
complete.

The temporary buffer remains available until Neovim deletes it. hermes.nvim
currently supports one live conversation per Neovim instance.

## Current scope

Implemented:

- loopback Hermes bootstrap token retrieval
- JSON-RPC over WebSocket through a Node bridge
- reliable request queueing while waiting for `gateway.ready`
- one live Hermes session tagged `hermes.nvim`
- prompt submission
- multiline prompt composition in a separate Markdown buffer
- streamed `message.delta` rendering
- `message.complete` fallback and turn completion
- initial-connection and active-session disconnect recovery
- durable session resume and transcript hydration
- new-conversation control
- approval and clarification prompts
- tool event rendering
- active-turn interruption

Deferred:

- multiple simultaneous conversations
- buffer-context attachment

## Development

```bash
cd bridge
npm ci
npm test
npm run typecheck
npm run build
```

Lua tests use plenary.nvim; see `.github/workflows/ci.yml` for the complete command.

The controller/state-machine design, readiness terminology, recovery invariants,
and portable conformance scenarios are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## License

MIT

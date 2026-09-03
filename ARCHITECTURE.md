# Hermes client state-machine architecture

hermes.nvim separates a portable transition system from Neovim-specific I/O. The executable specification is `lua/hermes/machine.lua` plus the language-neutral scenarios in `tests/conformance/client_scenarios.json`.

## Components and ownership

- `machine.lua` owns all lifecycle decisions. `dispatch(event)` synchronously returns `{ accepted, effects }`; it performs no process, RPC, file, buffer, or UI I/O.
- `controller.lua` owns serialization. It drains an event queue and runs returned effects in order. Events dispatched synchronously by an effect are appended and handled only after the current effect list. If a transition or effect throws, `dispatching` is restored before the error propagates and already-queued events remain available to the next dispatch.
- `protocol.lua` validates and converts gateway payloads to domain events. Unsupported string event types become `protocol.unknown` rather than being guessed into known semantics.
- `runtime.lua` executes effects through injected adapters and converts every asynchronous completion into a correlated event.
- `application.lua` composes machine, controller, and runtime and owns public
  submission/new-session callbacks. Public commands in `init.lua` and the
  composer resolve this application directly.
- Process, RPC, state, history, and buffer modules are I/O and projection
  adapters, not lifecycle authorities. `events.lua` and `interaction.lua` are
  passive UI ports driven by runtime effects.

## Model regions

The model contains six independently inspectable regions:

| Region | Phases | Owned data |
| --- | --- | --- |
| `bridge` | `stopped`, `starting`, `running`, `stopping` | incarnation generation |
| `connection` | `disconnected`, `connecting`, `ready`, `disconnecting` | connection generation |
| `session` | `none`, `creating`, `resuming`, `clearing_stale`, `persisting_activation`, `active`, `replacing`, `persisting_replacement` | live ID, durable ID, operation/generation, sequence watermark |
| `projection` | `unhydrated`, `hydrating`, `ready` | hydration generation and session ID |
| `turn` | `idle`, `queued`, `submitting`, `running`, `interrupting` | submission, operation, turn generation, presentation flags |
| `interaction` | `none`, `approval`, `clarification`, `responding` | request, locked/collected answers, current question, operation/generation |

`connection.phase == "ready"` means that durable persistence and canonical projection hydration have completed for the active session. It does not represent the bridge's lower-level gateway-ready notification.

## Event contract

Events are immutable inputs. The principal event families are:

- Intent: `client.open_requested`, `client.stop_requested`, `client.new_session_requested`, `client.interrupt_requested`, `prompt.submitted`, approval/clarification answers.
- Bridge/storage: `bridge.started`, `bridge.start_failed`, `bridge.exited`, `session_store.loaded`, `session_store.saved`, `session_store.save_failed`, `session_store.cleared`, `session_store.clear_failed`.
- Session/projection: `session.activated`, `session.replacement_created`, `projection.hydrated`, `projection.hydration_failed`.
- RPC completion: `operation.succeeded`, `operation.failed`.
- Gateway stream: `message.delta`, `message.completed`, `agent_activity.received`, blocking interaction requests, and `protocol.unknown`.

An accepted event may legitimately have no effects. A rejected event must not mutate the model and returns an empty effect list. Repeated `client.open_requested` while active and ready is accepted, keeps all lifecycle phases unchanged, and emits only `projection.show`.

## Effect contract and ordering

Effects are commands, not notifications that work has already completed:

- `bridge.start`, `bridge.stop`, `bridge.close_session`
- `rpc.request`
- `session_store.load`, `session_store.save`, `session_store.clear`
- `projection.show`, `projection.hydrate`, append/begin/finish/clear effects
- activity and interaction rendering/invalidation
- `submission.settle`, `session_transition.settle`, `notify`
- `session.close_detached`

The effect array order is normative and is asserted by conformance scenarios. `bridge.close_session` closes a live gateway session and then stops the local bridge (with a timeout). `session.close_detached` sends `session.close` without stopping the bridge; it is used for abandoned sessions during replacement.

Canonical activation order is:

1. create/resume RPC returns `session.activated`;
2. machine enters `session.persisting_activation` and emits correlated `session_store.save`;
3. `session_store.saved` makes the session active, enters `projection.hydrating`, and emits correlated `projection.hydrate`;
4. runtime invokes the projection adapter and dispatches `projection.hydrated` only after it returns;
5. the correlated hydration completion sets connection/projection ready, restores a pending interaction, and only then starts queued work.

A save or hydration failure settles queued submission callbacks as false, renders/notifies the failure, closes the newly activated session, and stops the bridge. A queued selection with empty canonical history uses the same hydration handshake but preserves its already-rendered selection.

## Correlation contract

Every asynchronous operation carries the identity needed to reject stale completion:

- bridge and connection generations scope process callbacks;
- session generation plus operation ID scope create/resume/persist/replace callbacks;
- projection generation, session generation, and live session ID scope hydration callbacks;
- turn generation plus operation ID scope submit/interrupt callbacks;
- interaction generation plus operation ID and request ID scope blocking responses.

Completions with any mismatched field are rejected without effects. Generations are monotonic. `session.last_sequence` is reset on activation/reconnect, stop, and bridge exit. The controller—not the general RPC receiver—enforces sequence order. Legacy typed RPC handlers retain their compatibility suppression. An ordered `protocol.unknown` for the active session advances the watermark but has no semantic effect.

When a bridge exits, the runtime first dispatches the generation-scoped exit event so the model resets, then calls `rpc.fail_pending`. Stop paths likewise call `rpc.fail_pending`; callbacks released by that cleanup are stale and cannot change the reset model.

## Turn and interaction invariants

- A terminal `message.completed` is authoritative. String completion text replaces streamed text; malformed status/text/error fields are sanitized.
- Deltas and activity remain valid while interrupt acknowledgment is pending. Activity rendering ends only at terminal completion. Interrupt success leaves the turn busy until terminal completion. Interrupt failure returns to `running`, notifies, and permits retry.
- Replacement is rejected while a blocking interaction is open or responding. Otherwise it keeps the old identity until the new durable ID is saved. Creation/save failure restores the old identity; commit switches identity, clears projection, closes the old live session detached, and settles the application callback.
- Stop or bridge exit during replacement emits `session_transition.settle(false)` so the application cannot remain locked.
- Stop and fatal activation/hydration failures keep the bridge in `stopping` until the process exit event arrives. Open and prompt intents are rejected during that interval, preventing a second bridge start from racing the old process.
- Clarification batches are machine-owned. The model keeps the complete request, locked answers, collected answers, and current question. The UI collects one answer; each `clarify.respond` completion is correlated before the next unanswered question is shown. Cancellation sends one request-level empty response and ends the batch. Production UI does not own RPC progression.

## Runtime configuration

Production runtime options use provider functions for `bridge_cmd` and `state_file`. Values are read when each effect runs, so a later `setup()` change made before activation is honored. Injected fixed values remain supported for tests and custom adapters.

## Executable conformance specification

`tests/conformance/client_scenarios.json` is language-neutral JSON. Each scenario declares:

- an optional standardized prefix (`ready` or `running`);
- ordered steps containing an event, expected acceptance, and ordered effect-type list;
- optional per-step and final model subsets.

`tests/conformance_spec.lua` executes the same contract against the Lua machine. Scenarios cover queued startup/persistence/hydration, stale completions, prompt streaming and completion, disconnect/reconnect sequence reset, interrupt failure/retry, replacement persistence failure, and blocking interaction correlation.

## Scope

The client intentionally models one conversation, one turn, and one blocking interaction at a time. Approval and multi-question clarification progression are machine-owned; the controller only serializes their events and effects. Unsupported wire events remain observable sequence-aware no-ops; dedicated UI semantics for other future blocking event types are not claimed.

The conformance runner's `ready` prefix performs open, bridge start, empty store load, session activation, durable save, and projection hydration, leaving operation sequence `1`. The `running` prefix adds prompt submission and correlated acceptance, leaving turn generation `1` and operation sequence `2`. Scenario operation IDs are interpreted relative to those exact prefixes.

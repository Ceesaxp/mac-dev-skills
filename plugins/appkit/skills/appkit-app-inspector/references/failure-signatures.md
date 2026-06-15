<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# uitool failure signatures

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.

## Source: `Specs/models/domain.uitool.ipc.md`

---
id: domain.uitool.ipc
kind: domain
depends-on: [domain.uitool.node-id, domain.uitool.node, domain.uitool.injection]
---

# IPC Protocol

The wire contract between the `uitool` CLI and the injected headless server (`UIToolServer`, hosted by `UIToolBoot`). Derived from HANDOFF §7 + §8.1.

> **Scope note.** This protocol is the **deferred injection half** of `uitool` — the CLI and the injected `UIToolServer` are separately built and talk over this socket. The cheap-read MVP (`windows` / `tree` / `find` / `node`) is built on the pure `UIToolCore` first; this spec pins the contract the server must satisfy once the injection half lands. Specs are intact; only the impl is deferred. The pure core's projection, exit-code, and JSON-Lines behavior already obey the determinism rules below.

## Transport

- **Unix domain socket** at `/tmp/uitool-<pid>.sock`, `chmod 0600` to the dev user.
- The injected dylib creates the socket on load and unlinks it on unload.
- Rejected for v1: Mach ports (bootstrap friction), localhost TCP (any local process could connect).

## Message shape (JSON-Lines)

One request object in, one response (or a stream of node objects) out. Synchronous and stateless per request; the server holds the live object graph.

```jsonc
// request
{"v":1,"id":7,"op":"hierarchy","window":"auto","maxDepth":3,"include":["class","frame","layer"]}
// response (one line) — `data` is a raw snapshot (a Capture / WindowSnapshot subtree),
// NOT a pre-projected node: the CLI applies rounding, key order, and node-id
// stringification ([[domain.uitool.node]]). The server holds no policy.
{"v":1,"id":7,"ok":true,"data":{ /* a Capture: {epoch, windows:[…]} or a subtree */ }}
// error
{"v":1,"id":7,"ok":false,"error":{"code":"STALE_NODE","message":"…","recover":"…"}}
```

| Field | Type | Notes |
| --- | --- | --- |
| `v` | int | protocol version; mismatch is a hard error (exit 8) |
| `id` | int | echoed in the response |
| `op` | string | the operation |
| `ok` | bool | success flag |
| `data` / `error` | object | one or the other |
| `error.code` | string | machine code, drawn from the closed vocabulary below |
| `error.recover` | string | one-line recovery hint; never a stack trace |
| `schemaVersion` | string | semver, e.g. `"1.0.0"` — in every payload and in `ping` (HANDOFF §8.4) |
| `sessionId` | string | identifies the attach session; the wire form of node-id's `sessionEpoch`. Suppressed by `--no-meta` |
| `_meta` | object | list/stream metadata: `{returned, truncated, totalMatched}`. Suppressed by `--no-meta` |

**Envelope metadata.** Every response carries `schemaVersion` (string). Unless `--no-meta` is passed, a response also carries a top-level `sessionId` (string) — the wire form of [[domain.uitool.node-id]]'s `sessionEpoch`, so the agent can detect a re-attach — and list/stream responses carry `_meta: {returned, truncated, totalMatched}`. `truncated` is the single canonical "more exist past the limit/depth" flag (never a second `limitHit`). `--no-meta` strips `sessionId`/`_meta` so output is byte-identical across sessions. Error responses (`ok:false`) carry `v` / `id` / `schemaVersion` and the `error` object, but not `sessionId`/`_meta`; examples may elide `v`/`id`/`schemaVersion` for brevity. (The attach-time/local verbs `doctor` and `list-apps` answer before any IPC socket exists, so their result objects are not bound by this envelope.)

## Operations

One `op` per request. The vocabulary is closed; an unknown `op` is a hard error. The **cheap-read MVP** verbs map onto a small subset:

| `op` | CLI verb | Reads | Notes |
| --- | --- | --- | --- |
| `hierarchy` | `tree` | view tree, bounded by `maxDepth` | the spine read; emits a root [[domain.uitool.node]] with nested children |
| `hierarchy` (maxDepth 0) | `node` | one node, no descendants | the single-node read is `hierarchy` pinned to depth 0 — `node` binds to the tree op at `maxDepth: 0` rather than a separate op |
| `find` | `find` | descendant match against a [[domain.uitool.selector]] | streams matching nodes; sized by `--limit` / `--count-only` ([[domain.uitool.selector]]) |
| `windows` | `windows` | the app's top-level windows | a list response; each entry is a window-rooted [[domain.uitool.node]] |
| `inspect` | `inspect` | one object's ivar values + class reflection (`--invoke` adds getter values) | resolves a node id to a live object via [[domain.uitool.registry]]; the value-fetching op ([[command.uitool.inspect]], Phase 3.5) |

The `inspect` value-fetching op is specified in [[command.uitool.inspect]] (Phase 3.5): ivar reads are safe and default; **getter invocation** is gated behind `--invoke`, runs on the target main thread under the bounded timeout, and is safety-screened. Raw setter **mutation** stays out of scope — v1 is read-only.

## Default mode: structural, no-invoke

Reading ivar **memory** is safe (no target code runs) and is `inspect`'s default. Invoking property **getters** / `-description` runs the target's own code **inside someone else's process** — it can deadlock the main thread, mutate state, or crash the host. So getter invocation is gated behind `inspect --invoke`, runs on the target main thread under a hard per-query timeout, and is safety-screened ([[command.uitool.inspect]]). The cheap-read verbs (`windows` / `tree` / `find` / `node`) are all structural, no-invoke reads; `inspect` without `--invoke` is too.

## Threading (load-bearing)

- The socket accept/read loop runs on a dedicated **background** thread — never block the host main thread.
- **All AppKit reads run on the target's main thread**, marshaled per request with a bounded timeout (≈500 ms); on timeout return `TIMEOUT` rather than hang.
- Per-request main-thread work is tiny and bounded by `maxDepth`: snapshot on main, serialize to JSON off-main. Avoid the snapshot-image path entirely (it mutates the hierarchy).
- On dylib unload / app quit: close socket, unlink path, drop the registry.

## Error codes (the closed vocabulary)

`error.code` is drawn from a fixed set. These are the canonical wire codes — the CLI maps each to an exit code, the agent branches on the code without parsing `message`/`recover` prose.

| `error.code` | Exit | Source | Meaning |
| --- | --- | --- | --- |
| `BAD_SELECTOR` | 2 | [[domain.uitool.selector]] | the `--match` regex was uncompilable, or a usage/selector error |
| `UNKNOWN_FIELD` | 2 | projection | a `--fields` path that names no [[domain.uitool.node]] field |
| `BAD_PREDICATE` | 2 | projection | a malformed `--where` predicate |
| `NOT_ATTACHED` | 4 | [[domain.uitool.injection]] | no live session for the target (or injection failed) |
| `STALE_NODE` | 5 | [[domain.uitool.node-id]] | a held node id failed re-validation against the live graph |
| `NO_WINDOWS` | (see note) | windows | the attached app has no top-level windows to root a read at |
| `TIMEOUT` | 7 | this spec (threading) | a main-thread hop exceeded the ≈500 ms bound, or a socket timeout |

`UNKNOWN_FIELD` and `BAD_PREDICATE` are **distinct** codes (not a single `BAD_PROJECTION`): an unknown `--fields` path and a malformed `--where` predicate are different agent-fixable mistakes, so they get different codes — both exit 2. `BAD_SELECTOR` covers an uncompilable `--match` regex specifically (the [[domain.uitool.selector]] engine throws at `Regex` construction); the projection codes never collapse into it.

**`NO_WINDOWS` is not an error exit.** An attached app with zero top-level windows is a valid, empty result, not a failure: `windows` returns **exit 0** with `_meta.totalMatched: 0` and an empty list. `NO_WINDOWS` is the explanatory `error.code` carried on stderr's structured object only where a verb that *requires* a window to root at (e.g. a `tree`/`find` with `window: "auto"` and no candidate) cannot proceed — in that case it surfaces as the verb's empty result, never as a non-zero exit. The agent reads `_meta`, not the exit code, to tell empty from broken.

## Exit-code mapping (CLI)

The agent branches on exit code without parsing prose:

| Exit | Meaning |
| --- | --- |
| 0 | ok |
| 2 | usage / `BAD_SELECTOR` / `UNKNOWN_FIELD` / `BAD_PREDICATE` |
| 3 | app not running |
| 4 | `NOT_ATTACHED` / injection failed |
| 5 | `STALE_NODE` ([[domain.uitool.node-id]]) |
| 6 | SIP/AMFI/LV/arch precondition failed ([[domain.uitool.injection]]) |
| 7 | socket / `TIMEOUT` |
| 8 | schema-version mismatch |

A successful query that matches **nothing** is exit **0** (with `_meta.totalMatched: 0`), never a non-zero code — see Notes.

- **Exit 3 (app not running) and exit 6 (precondition) are attach-time only.** Exit 3 is emitted by `attach` while resolving/launching a named target; exit 6 by `doctor` and `attach` (the precondition gate). `list-apps` emits neither — it enumerates (0/2 only). Post-attach query verbs assume a live session; an unreachable session surfaces as **exit 4** (`NOT_ATTACHED`) or **exit 7** (`TIMEOUT`), never 3 or 6.
- This table governs the **CLI↔agent control channel only.** The commit/CI dual-use containment guard runs outside it and has its own non-zero convention (it fails the build/commit); it does not map to these codes.

## Invariants

- Every payload carries `schemaVersion` — a semver **string** (e.g. `"1.0.0"`), distinct from the int protocol version `v`; carried in `ping` too. Additive changes only within a major.
- `error.code` is always one of the closed vocabulary above. No ad-hoc codes; no placeholder strings.
- Never exit 0 on failure. Errors also print a one-line structured JSON object to stderr.
- The schema handshake on `ping` is what keeps the separately-built CLI and dylib from desyncing.

## Relationships

- [[domain.uitool.server]] — the in-target unit that speaks this protocol; it ships a raw `Capture` as a read's `data` and the CLI projects it. The threading invariants above are its law.
- [[domain.uitool.boot]] — the dylib that hosts the server and creates/unlinks the socket.
- [[domain.uitool.node]] — the projected shape the CLI derives from the raw `data` snapshot.
- [[domain.uitool.node-id]] / [[domain.uitool.injection]] — sources of `STALE_NODE` / precondition errors.
- [[domain.uitool.selector]] — source of `BAD_SELECTOR`; the matcher runs **CLI-side** over the `Capture` the server streams for `find`.

## Notes

- **Exit 6 is precondition-only.** A valid query that matches nothing is **not** an error — it returns **exit 0** with `_meta.totalMatched: 0` (and empty `data`/stream). The agent distinguishes empty-from-error by reading `_meta`, never by the exit code; a 0-match result means _broaden the selector_, not re-issue. (Resolves the HANDOFF §8.1 exit-6 double-assignment: 6 stays precondition-failed only.)
- The per-main-thread-hop timeout is **fixed at ≈500 ms** for v1 (not per-request configurable); a hop that exceeds it returns `TIMEOUT` → exit 7 (HANDOFF §7.4). The wire code is the canonical `TIMEOUT` (the HANDOFF's `MAIN_THREAD_TIMEOUT` working name is collapsed into it — a socket timeout and a main-thread-hop timeout share exit 7 and the one code).


## Source: `Features/uitool/0001-doctor/errors/uitool.doctor-precondition-failed.md`

---
id: error.uitool.doctor-precondition-failed
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.doctor]
---

# Precondition failed

## When this happens

The agent runs [[command.uitool.doctor]] (or any command that gates on the precondition stack) and the **cooperative** posture is not usable — i.e. `cooperative.usable` is false, because one of its required checks (`arch`, `injectable-arm64`) is unmet. The exit code tracks the cooperative posture only; an unusable **unrestricted** posture alone does not raise this error if the cooperative one is usable. This is the failure that, without `doctor`, would otherwise surface much later as a silent "dylib didn't load".

## What the user sees

Both posture reports on stdout, each naming its failed checks and, for each, a single concrete remedy. The command exits 6 ([[domain.uitool.ipc]]). A one-line structured error is also printed to stderr, carrying the wire code `PRECONDITION_FAILED`.

> "Precondition failed: cooperative — injectable-arm64 absent. Remedy: build the arm64 UIToolBoot injectable (the injection half is not yet built)."

## What this is NOT — the cooperative posture needs no machine defang

This error does **not** mean the machine must be SIP-disabled, AMFI-loosened, or library-validation-overridden to inspect the user's **own** apps. macOS gates injection per target: an app the user builds and signs for development carries `get-task-allow`, which is honored on a **stock, SIP-enabled Mac**. The cooperative posture's only machine requirements are an Apple Silicon host and the **arm64** `UIToolBoot` injectable.

So **today** this error is raised because the arm64 `UIToolBoot` injectable is not built yet — the **deferred injection half** — **not** because the machine is missing a defang. The full SIP/AMFI/LV/arm64e-ABI defang stack is required **only** for the **unrestricted** posture (inspecting apps the user did NOT sign — system / notarized), and an unusable unrestricted posture is reported in its own `ModeReport` without, by itself, setting exit 6.

## What the user can do

- **Read both `ModeReport`s** — `cooperative` tells you what's needed to inspect your own apps (today: just the deferred arm64 dylib); `unrestricted` tells you the additional defang needed only for apps you did not sign.
- **Apply the named remedy(ies)** — each failed check carries its own one-line fix. The cooperative posture's failures (today, the absent arm64 injectable) need no reboot; the unrestricted posture's boot-arg and SIP changes each require a reboot afterward.
- **Re-run `doctor`** — confirm `cooperative.usable` is now true (exit 0) before attempting cooperative attachment.
- **Branch on exit code 6** — the agent detects a cooperative-precondition failure without parsing prose ([[domain.uitool.ipc]]).

## Underlying cause (informational)

- **Cooperative posture (governs the exit code):** the host is not Apple Silicon, or the **arm64** `UIToolBoot` injectable is built as some other slice or absent. Today the latter holds — the arm64 injectable is part of the deferred injection half.
- **Unrestricted posture (reported, but only the cooperative posture sets exit 6):** SIP not lowered to Permissive Security; missing `amfi_get_out_of_my_way=0x1` or `-arm64e_preview_abi` in `boot-args`; `DisableLibraryValidation` unset; the **arm64e** `UIToolBoot` injectable absent or built as plain-arm64.
- Any single unmet link within a posture marks that posture not-usable; [[command.uitool.doctor]] reports all of them independently so a half-configured machine is fully diagnosed in one run.

## Related

- [[command.uitool.doctor]] — the command that emits this error and the two-posture report.
- [[domain.uitool.injection]] — the precondition stack and its remedies.
- [[domain.uitool.ipc]] — exit-code 6 mapping and the `PRECONDITION_FAILED` wire code.
- [[story.uitool.doctor-preconditions]] — the capability this protects.


## Source: `Features/uitool/0002-attach/errors/uitool.attach-injection-failed.md`

---
id: error.uitool.attach-injection-failed
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Injection did not take

## When this happens

The injected channel never opens within the bounded wait — the [[domain.uitool.boot]] dylib failed to load (a `launch` spawn that did not exec, or a constructor that never started the server), or (on the attach-to-running path) the remote `dlopen` was refused. This is the failure [[domain.uitool.injection]] warns is otherwise silent: "any one link failing silently produces 'dylib didn't load'."

## What the user sees

Exit code 4 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace. The agent is never told the attach succeeded.

> `{"ok":false,"error":{"code":"INJECTION_FAILED","message":"socket never appeared for pid 4821 within the bounded wait","recover":"run uitool doctor to identify the failing link; if attach-to-running was refused, try uitool launch for a clean-launch instance"}}`

The wire `error.code` for injection-not-taking is `INJECTION_FAILED` (exit 4) — canonical.

## What the user can do

- Run `uitool doctor` to localize which precondition or arch link is failing (it reports exactly which, per [[domain.uitool.injection]]).
- If attach-to-running was refused for a target, try `uitool launch` for a fresh instance; accept that some targets are out of scope and do not burn schedule defeating them.

## Underlying cause (informational)

- dyld silently rejected the dylib (e.g. a plain-arm64 dylib into an arm64e process), or the constructor never started the server, so the socket at `/tmp/uitool-<pid>.sock` ([[domain.uitool.ipc]]) never appeared.
- On the attach-to-running path, `task_for_pid` was refused (the target is not `get-task-allow`, or `uitool` is not debugger-entitled), or the remote `dlopen` into the target failed ([[domain.uitool.injection]]).

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[error.uitool.attach-precondition]] — distinct: the preconditions themselves failed (exit 6), detected before injection is attempted.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.injection-failed; [[story.uitool.launch]] — scenario.uitool.launch.injection-failed.


## Source: `Features/uitool/0002-attach/errors/uitool.attach-not-running.md`

---
id: error.uitool.attach-not-running
kind: error
depends-on: [domain.uitool.ipc, command.uitool.attach]
---

# Target app is not running

## When this happens

The agent attaches to a target whose process does not exist — a wrong pid, or a bundle id for an app that is not currently launched.

## What the user sees

Exit code 3 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"APP_NOT_RUNNING","message":"no process for com.example.SampleAppKit","recover":"launch the app, or pass a live pid (see uitool list-apps)"}}`

The wire `error.code` for the not-running case is `APP_NOT_RUNNING` (exit 3) — canonical.

## What the user can do

- Launch the target app, then re-attach.
- List attachable processes (`uitool list-apps`) to confirm the pid / bundle id.

## Underlying cause (informational)

- The requested pid does not exist, or the bundle id resolves to no running process.

## Related

- [[command.uitool.attach]] — the verb that surfaces this.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.not-running.


## Source: `Features/uitool/0002-attach/errors/uitool.attach-precondition.md`

---
id: error.uitool.attach-precondition
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Injection precondition failed

## When this happens

The agent attaches or launches, but a link in the injection precondition stack ([[domain.uitool.injection]]) is not satisfied. **Which links apply depends on the posture:** the **cooperative** path (your own `get-task-allow` app) needs only an Apple Silicon host and the matching arm64 [[domain.uitool.boot]] dylib (plus, for attach-to-running, `uitool` being debugger-entitled and the target being same-user) — **no SIP/AMFI/libval changes**; the **unrestricted** path (a target you did not sign) additionally needs the full machine defang — SIP off, AMFI boot-arg, library validation off, the arm64e ABI, and the arm64e dylib. Any one failing would otherwise produce a silent "dylib didn't load", so the command refuses up front rather than proceeding.

## What the user sees

Exit code 6 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr that names **exactly which** precondition failed plus a one-line remediation ([[domain.uitool.injection]] invariant) — never a stack trace.

> `{"ok":false,"error":{"code":"PRECONDITION_FAILED","message":"AMFI not disabled","recover":"add amfi_get_out_of_my_way=0x1 to nvram boot-args and reboot; then re-run uitool doctor"}}`

The wire `error.code` is a single canonical `PRECONDITION_FAILED` (exit 6); the failing check is named in `message`, satisfying [[domain.uitool.injection]]'s requirement to report "exactly which failed plus a one-line remedy" without a per-link code explosion.

## What the user can do

- Apply the named remediation (cooperative: build the arm64 [[domain.uitool.boot]] dylib; unrestricted: set the boot-arg, disable library validation, build the arm64e dylib), reboot if required, then re-attach or re-launch.
- Run `uitool doctor` for the full precondition verdict across all links at once.
- Run `uitool doctor --fix` to opt into auto-remediation ([[domain.uitool.injection]] invariant): it echoes each command before running it, never runs implicitly, and sets what it can — then prints exactly which manual steps (SIP via Recovery `csrutil`) and reboot remain.

## Underlying cause (informational)

- A cooperative check failed: not an Apple Silicon host, or the **arm64** [[domain.uitool.boot]] dylib absent (and, for attach-to-running, `uitool` not debugger-entitled or the target not same-user / not `get-task-allow`).
- Or an unrestricted check failed: SIP enabled, AMFI not disabled, library validation enabled, missing `-arm64e_preview_abi`, or the **arm64e** boot dylib absent.

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[error.uitool.attach-injection-failed]] — distinct: preconditions passed but injection still did not take (exit 4).
- `uitool doctor` / `uitool doctor --fix` — the dedicated precondition-verdict command and its explicit auto-remediation flag (a separate feature; [[domain.uitool.injection]] invariant).


## Source: `Features/uitool/0002-attach/errors/uitool.attach-schema-mismatch.md`

---
id: error.uitool.attach-schema-mismatch
kind: error
depends-on: [domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Schema version mismatch

## When this happens

The channel opened and the handshake completed, but the injected server reports a different protocol/schema version than the CLI expects — the separately-built CLI and dylib have desynced ([[domain.uitool.ipc]]: the `ping` handshake is what keeps them from desyncing).

## What the user sees

Exit code 8 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"SCHEMA_MISMATCH","message":"CLI expects schemaVersion \"1.0.0\", server reports \"2.0.0\"","recover":"rebuild UIToolBoot.dylib (and UIToolServer) from the same source as the CLI"}}`

The wire `error.code` for the version mismatch is `SCHEMA_MISMATCH` (exit 8) — canonical.

## What the user can do

- Rebuild [[domain.uitool.boot]] and [[domain.uitool.server]] from the same source as the CLI so both carry the same `schemaVersion`, then re-attach or re-launch.

## Underlying cause (informational)

- The `v` / `schemaVersion` carried in the `ping` response does not match the CLI's expected version ([[domain.uitool.ipc]]); only additive changes within a major are compatible.

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[domain.uitool.ipc]] — the schema handshake and version invariant.


## Source: `Features/uitool/0002-attach/errors/uitool.attach-timeout.md`

---
id: error.uitool.attach-timeout
kind: error
depends-on: [domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Socket or handshake timed out

## When this happens

The injected channel opened, but the schema handshake (`ping`) over the socket did not complete within its bounded timeout — typically because the target's main thread is busy (a blocking run loop or the spinning wait cursor) when the handshake marshals work to it.

## What the user sees

Exit code 7 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"TIMEOUT","message":"target main thread did not answer the handshake within the timeout","recover":"dismiss any modal in the target and re-attach"}}`

The wire `error.code` is the canonical `TIMEOUT` (exit 7). Both timeout shapes at attach or launch map to this one code: the main-thread hop exceeding its bounded window (the handshake reached the main thread but it did not answer), and the socket-level case where the handshake never returned at all. They are not split into separate codes — `TIMEOUT` covers the attach/launch-time bounded-wait family, the same way query-time main-thread hops report `TIMEOUT` ([[domain.uitool.ipc]]).

## What the user can do

- Dismiss any modal sheet or alert in the target that is blocking its main thread, then re-attach.
- Re-attach once the target is idle.

## Underlying cause (informational)

- The main-thread hop for the handshake exceeded its bounded timeout (≈500 ms) and returned `TIMEOUT` rather than hanging ([[domain.uitool.ipc]] threading).

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[domain.uitool.ipc]] — threading and the bounded main-thread timeout.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.handshake-timeout; [[story.uitool.launch]] — scenario.uitool.launch.handshake-timeout.


## Source: `Features/uitool/0002-attach/errors/uitool.launch-not-found.md`

---
id: error.uitool.launch-not-found
kind: error
depends-on: [domain.uitool.ipc, command.uitool.launch]
---

# App to launch was not found

## When this happens

The agent launches a target by bundle id or path, but no launchable `.app`
bundle resolves — a misspelled bundle id, a bundle id for an app that is not
installed, or a path that does not point at a valid app bundle. This is the
launch-time analog of [[error.uitool.attach-not-running]]: `attach` fails when a
named **running process** does not exist; `launch` fails when a named
**installable app** does not exist.

## What the user sees

Exit code 3 ([[domain.uitool.ipc]]) and a one-line structured JSON error on
stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"APP_NOT_FOUND","message":"no launchable app for com.example.SampleAppKit","recover":"check the bundle id, or pass a path to the .app bundle"}}`

The wire `error.code` for a launch target that cannot be resolved is
`APP_NOT_FOUND` (exit 3) — canonical. Like `APP_NOT_RUNNING`
([[error.uitool.attach-not-running]]), it is a **launch-time** code, not a
post-socket wire code: it is raised by `launch` while resolving the target,
before any injection or socket ([[domain.uitool.ipc]] — exit 3 is attach/launch
time only).

## Distinct from the already-running case

Refusing to launch because a same-user instance is **already running** (without
`--replace`) is a different condition: it is a usage error (exit 2), not
`APP_NOT_FOUND`, and its recovery hint points at [[command.uitool.attach]] or
`--replace` ([[command.uitool.launch]] Behavior step 2). `APP_NOT_FOUND` means
*there is no such app to launch*; the exit-2 case means *the app is right there,
already running — say how you want it handled*.


## Source: `Features/uitool/0003-windows/errors/uitool.windows-no-windows.md`

---
id: error.uitool.windows-no-windows
kind: error
depends-on: [domain.uitool.ipc, command.uitool.windows]
---

# No top-level windows open

## When this happens

The agent is attached to a running target that currently has no top-level windows open (e.g. a menu-bar-only app, or an app whose windows are all closed). This is a successful query with an empty result, **not** a failure — but it is a distinct, user-observable outcome the agent must not mistake for an error or retry blindly.

## What the user sees

An empty window list on stdout (no record lines) and exit code **0** per [[domain.uitool.ipc]]. The empty result is explicitly marked by the [[domain.uitool.ipc]] envelope's `_meta.totalMatched: 0` so it cannot be confused with a truncated read or a crash. With the envelope present (i.e. without `--no-meta`), the full top-level response carries the mandatory `schemaVersion` and the top-level `sessionId` alongside `_meta`:

> `{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":0,"truncated":false,"totalMatched":0}}`
>
> With `--no-meta`, `sessionId` and `_meta` are stripped and only `schemaVersion` remains; stdout carries no record lines either way.

## What the user can do

- **Accept the empty result** — re-issuing the identical query is the wrong recovery; the answer will not change until the app opens a window.
- **Bring up a window** — drive the app to open a window (open a document, trigger its main window), then re-run.

## Underlying cause (informational)

- The enumerated top-level window set (`NSApp.windows`, filtered per [[command.uitool.windows]]) is empty.

## Related

- [[command.uitool.windows]] — the verb that surfaces this.
- [[story.uitool.windows-enumerate]] — scenario `scenario.uitool.windows-enumerate.empty`.
- [[domain.uitool.ipc]] — empty-success is distinct from failure (never exit 0 on failure, and never non-zero on a valid empty result).


## Source: `Features/uitool/0003-windows/errors/uitool.windows-not-attached.md`

---
id: error.uitool.windows-not-attached
kind: error
depends-on: [domain.uitool.ipc, domain.uitool.injection, command.uitool.windows]
---

# Windows requested before attach

## When this happens

The agent runs the windows verb against an app it has not attached to (no injected server / no socket for that target), so there is no live object graph to enumerate.

## What the user sees

A one-line structured JSON error on stderr with a recovery hint, an empty stdout, and exit code **4** (not attached / injection failed) per [[domain.uitool.ipc]]. The error object carries the [[domain.uitool.ipc]] message-shape fields — the int protocol version `v`, the echoed request `id`, the semver `schemaVersion`, `ok: false`, and the `error` payload with the canonical `NOT_ATTACHED` code:

> `{"v":1,"id":1,"schemaVersion":"1.0.0","ok":false,"error":{"code":"NOT_ATTACHED","message":"no uitool session for <app>","recover":"run 'uitool attach <app>' first"}}`

## What the user can do

- **Attach first** — run `uitool attach <app>`, then re-run `uitool windows <app>`.
- **Check the target is running** — if the app is not running, attach itself fails with exit 3; resolve that first.

## Underlying cause (informational)

- See [[domain.uitool.ipc]] and [[domain.uitool.injection]] for the conditions that produce this state: no listening server for the resolved target, whether because no socket exists or because injection failed at attach time.

## Related

- [[command.uitool.windows]] — the verb that surfaces this.
- [[domain.uitool.ipc]] — exit-code mapping (exit 4).


## Source: `Features/uitool/0003-windows/errors/uitool.windows-timeout.md`

---
id: error.uitool.windows-timeout
kind: error
depends-on: [domain.uitool.ipc, command.uitool.windows]
---

# Window enumeration timed out

## When this happens

The injected server must read the window list on the target's main thread, but the main thread did not service the marshaled request within the bounded timeout (per [[domain.uitool.ipc]]) — typically because the target is busy, beachballing, or paused in a debugger.

## What the user sees

A one-line structured JSON error on stderr with a recovery hint, an empty stdout, and exit code **7** (socket / main-thread timeout) per [[domain.uitool.ipc]]. The error object carries the canonical `TIMEOUT` code:

> `{"ok":false,"error":{"code":"TIMEOUT","message":"target main thread did not respond","recover":"ensure <app> is not blocked or paused, then retry"}}`

## What the user can do

- **Retry** — the timeout is bounded and non-destructive; the server returns the error rather than hanging, so a later request can succeed once the main thread is free.
- **Unblock the target** — bring the app to a responsive state (resume it if paused under a debugger, wait out a long operation), then re-run.

## Underlying cause (informational)

- The main-thread hop that snapshots `NSApp.windows` exceeded the bounded timeout; the server returns `TIMEOUT` rather than block the accept loop.

## Related

- [[command.uitool.windows]] — the verb that surfaces this.
- [[domain.uitool.ipc]] — threading model and exit-code mapping (exit 7).


## Source: `Features/uitool/0004-tree/errors/uitool.tree-bad-projection.md`

---
id: error.uitool.tree-bad-projection
kind: error
depends-on: [command.uitool.tree, domain.uitool.node, domain.uitool.selector, domain.uitool.ipc]
---

# Tree projection or filter is invalid

This spec documents **two distinct error codes** with the same exit code (2):
`UNKNOWN_FIELD` for a malformed projection (`--fields`), and `BAD_PREDICATE` for
a malformed filter (`--where`). They are separate codes so an agent can tell a
typo'd field path apart from a syntactically broken predicate and recover the
right way without guessing.

## When this happens

The agent passes `--fields` a path that is not a field of [[domain.uitool.node]]
(`UNKNOWN_FIELD`), or passes `--where` an expression that does not parse under
[[domain.uitool.selector]] (`BAD_PREDICATE`). Either way the query is malformed
before any walking begins, and the two faults surface as two distinct codes.

## What the user sees

The walk does not run. A one-line structured JSON error on stderr, exit 2, with
a `recover` hint naming the offending token. No hierarchy on stdout. The stderr
line carries `schemaVersion` (the [[domain.uitool.ipc]] envelope invariant:
*every* payload carries it).

An unknown `--fields` path → code `UNKNOWN_FIELD`:

> `{"schemaVersion":"1.0.0","error":{"code":"UNKNOWN_FIELD","message":"unknown field 'frameTopLft' in --fields","recover":"use a field from `uitool schema`; did you mean frameTopLeft?"}}`

A malformed `--where` predicate → code `BAD_PREDICATE`:

> `{"schemaVersion":"1.0.0","error":{"code":"BAD_PREDICATE","message":"--where: unexpected token near 'frame-w >>'","recover":"see the --where grammar in `uitool schema`/selector docs"}}`

The two codes are distinct on the wire so the agent's recovery branch is
unambiguous: `UNKNOWN_FIELD` means fix the projection, `BAD_PREDICATE` means fix
the predicate.

## What the user can do

- On `UNKNOWN_FIELD`: run `uitool schema` to get the exact set of projectable
  field paths, then correct `--fields`.
- On `BAD_PREDICATE`: fix the `--where` expression to the bounded grammar in
  [[domain.uitool.selector]]. A `--where` pattern is matched with Swift-native
  `Regex` (case-insensitive, unanchored substring); a pattern that fails to
  *parse* the predicate grammar is this `BAD_PREDICATE` fault, distinct from a
  pattern that parses but matches nothing (which is a valid, exit-0 empty walk).
- Re-issuing the identical command is the wrong recovery in either case: the
  query string itself is malformed and will fail the same way.

## Underlying cause (informational)

- `UNKNOWN_FIELD`: `--fields` referenced a path absent from the
  [[domain.uitool.node]] schema.
- `BAD_PREDICATE`: `--where` failed to parse under the total expression language
  in [[domain.uitool.selector]] (including an invalid Swift `Regex` pattern,
  which throws at construction and is mapped here).
- Both map to [[domain.uitool.ipc]]'s usage class → exit 2, as two distinct
  `error.code` strings: `UNKNOWN_FIELD` and `BAD_PREDICATE`.

## Related

- [[command.uitool.tree]] — the verb that surfaces both codes.
- [[story.uitool.tree-project]] — scenario `scenario.uitool.tree-project.unknown-field`.


## Source: `Features/uitool/0004-tree/errors/uitool.tree-stale-root.md`

---
id: error.uitool.tree-stale-root
kind: error
depends-on: [command.uitool.tree, domain.uitool.node-id, domain.uitool.ipc]
---

# Tree root handle is stale

## When this happens

The agent passes `--at` a node handle that no longer matches the live tree — the
object was recycled, the path shifted under live mutation, or the registry was
invalidated (a re-attach, a key-window change). Per [[domain.uitool.node-id]], a stale
handle is never dereferenced.

## What the user sees

The walk does not run. A one-line structured JSON error on stderr, exit 5, with
a `recover` hint. No partial hierarchy on stdout. The stderr line carries
`schemaVersion` (the [[domain.uitool.ipc]] envelope invariant: *every* payload carries
it).

> `{"schemaVersion":"1.0.0","error":{"code":"STALE_NODE","message":"node 7:w0/cv/sv2/sub0 no longer matches the live tree","recover":"re-resolve the path with windows/tree, or re-attach if the session epoch changed"}}`

## What the user can do

- Re-walk from a known-good ancestor — `windows` for a fresh root, then `tree`
  back down to the node — to mint a current handle.
- Compare the epoch prefix in the node id (e.g. the `7` in `7:w0/cv/...`)
  against the `sessionId` field in the current response; a bumped epoch means
  re-attach invalidated every prior handle. (`sessionId` is the wire form of
  node-id's internal `sessionEpoch` integer — [[domain.uitool.ipc]].)
- Re-issuing the identical `--at` is the wrong recovery: it will fail the same
  way, since the handle is what is stale.

## Underlying cause (informational)

- One of [[domain.uitool.node-id]]'s pre-deref validation invariants failed: the
  structural-path re-walk no longer matches, the pointer no longer resolves to a
  live object, or the live class no longer equals the recorded class. (The
  specific checks are defined in [[domain.uitool.node-id]]; this error surfaces their
  failure at the model level.)
- Maps to [[domain.uitool.ipc]]'s `STALE_NODE` → exit 5.

## Related

- [[command.uitool.tree]] — the verb that surfaces this.
- [[story.uitool.tree-walk]] — scenario `scenario.uitool.tree-walk.stale`.


## Source: `Features/uitool/0005-find/errors/uitool.find-bad-selector.md`

---
id: error.uitool.find-bad-selector
kind: error
depends-on: [domain.uitool.selector, domain.uitool.ipc, command.uitool.find, story.uitool.find-locate]
status: draft
---

# Malformed selector or predicate

## When this happens

The agent passes a `--class` selector or a `--where` predicate that does not parse — an unknown combinator, an unbalanced bracket, an unsupported operator, an attribute the grammar does not address, or an **invalid `Regex` pattern** in a `matches`/`~` operand (the Swift-native `Regex` engine throws at construction). It also covers running `find <app>` with **neither** `--class` nor `--where`, which the surface refuses as a usage error rather than enumerating the whole tree. This is a **usage error**, not a zero-match result: the query never ran against the tree.

## What the user sees

A one-line structured JSON error object on stderr (never a stack trace), and exit code **2** per [[domain.uitool.ipc]].

> `{"error":{"code":"BAD_SELECTOR","message":"unexpected token near '[frame-w>>200]'","recover":"fix the selector/predicate syntax; see the selector grammar"}}`

The wire `error.code` is the canonical string **`BAD_SELECTOR`**, per [[domain.uitool.ipc]]'s error-code vocabulary.

## What the user can do

- Correct the selector / predicate syntax against [[domain.uitool.selector]] and re-run — distinct from a zero-match, where re-issuing the same query is the wrong move.
- If the failure is an invalid regular expression in a `matches`/`~` operand, fix the pattern: the engine is Swift-native `Regex` (case-insensitive, unanchored substring), so a literal substring or a valid `Regex` works; an unbalanced group or a malformed character class throws.
- Drop to a simpler `--class` glob and add `--where` constraints incrementally.
- If you passed neither `--class` nor `--where`, add at least one constraint (to enumerate broadly on purpose, pass an explicit broad selector like `--class '*'` and size it with `--count-only` first).

## Underlying cause (informational)

- The selector parser rejected the structural selector before evaluation.
- The predicate parser rejected the `--where` expression before evaluation.
- A `Regex` pattern in a `matches`/`~` operand failed to construct (the Swift `Regex` initializer threw).
- An attribute referenced in the query is outside the addressable vocabulary (see the attribute-vocabulary section of [[domain.uitool.selector]]).
- No constraint was supplied (`find` requires at least one of `--class` / `--where`).

## Related

- [[command.uitool.find]] — issues exit 2 for this.
- [[domain.uitool.selector]] — the grammar this validates against, including the `Regex` engine for `matches`/`~`.
- [[story.uitool.find-locate]] — scenario `scenario.uitool.find-locate.bad-selector`.


## Source: `Features/uitool/0005-find/errors/uitool.find-not-attached.md`

---
id: error.uitool.find-not-attached
kind: error
depends-on: [domain.uitool.ipc, command.uitool.find, domain.uitool.injection]
status: draft
---

# Target not attached

## When this happens

The agent runs `find` against an app that uitool has not injected into (or whose injection has gone away). There is no server-side tree to evaluate the selector against. This is distinct from the app not being running at all (exit 3).

## What the user sees

A one-line structured JSON error object on stderr, and exit code **4** per [[domain.uitool.ipc]].

> `{"error":{"code":"NOT_ATTACHED","message":"no uitool session for com.apple.mail","recover":"run: uitool attach com.apple.mail"}}`

The wire `error.code` is the canonical string **`NOT_ATTACHED`**, per [[domain.uitool.ipc]]'s error-code vocabulary.

## What the user can do

- Attach first (`uitool attach <app>`) and re-run the same `find`.
- If attach itself fails, run `uitool doctor` to check the SIP/AMFI/LV/arch preconditions ([[domain.uitool.injection]]) — a precondition failure surfaces separately as exit 6. `doctor` detects and instructs by default; to opt into auto-remediation of the fixable preconditions, run `uitool doctor --fix` (it echoes each command before running it and prints the manual steps + reboot it cannot perform — per [[domain.uitool.injection]]).

## Underlying cause (informational)

- No socket exists at `/tmp/uitool-<pid>.sock` for the resolved target.
- The dylib was injected but has since unloaded (app quit, detached, or registry dropped).

## Related

- [[command.uitool.find]] — issues exit 4 for this.
- [[domain.uitool.ipc]] — transport and the exit-code mapping.


## Source: `Features/uitool/0005-find/errors/uitool.find-timeout.md`

---
id: error.uitool.find-timeout
kind: error
depends-on: [domain.uitool.ipc, domain.uitool.selector, command.uitool.find]
---

# Search timed out on the target's main thread

## When this happens

The selector / predicate parses and runs, but the server-side evaluation cannot complete within the bounded main-thread window (≈500 ms per [[domain.uitool.ipc]]) — typically because the target's main thread is busy or the tree is very large. uitool returns rather than hang the host: evaluation is bounded by design, so this surfaces as a timeout, never a frozen target.

## What the user sees

A one-line structured JSON error object on stderr, and exit code **7** per [[domain.uitool.ipc]].

> `{"error":{"code":"TIMEOUT","message":"target main thread did not respond within the budget","recover":"narrow the selector or retry once the target is idle"}}`

The wire `error.code` is the canonical string **`TIMEOUT`**, per [[domain.uitool.ipc]]'s error-code vocabulary (covering both the bounded main-thread hop and the socket round-trip).

## What the user can do

- Narrow the query (a tighter `--class` selector or more `--where` constraints) so server-side evaluation visits fewer nodes, then re-run.
- Retry once the target app is idle (e.g. not mid-animation or mid-load).
- Use `--count-only` first to size a narrower selector before pulling records.

## Underlying cause (informational)

- The per-request main-thread hop exceeded its bounded budget; the server returned `TIMEOUT` instead of blocking.
- The socket round-trip exceeded its timeout.

## Related

- [[command.uitool.find]] — issues exit 7 for this.
- [[domain.uitool.ipc]] — the threading model and ≈500 ms main-thread budget.
- [[domain.uitool.selector]] — evaluation is total and bounded, which is why this is a timeout, not a hang.


## Source: `Features/uitool/0006-node/errors/uitool.node-stale.md`

---
id: error.uitool.node-stale
kind: error
depends-on: [domain.uitool.node-id, domain.uitool.ipc, command.uitool.node, story.uitool.node-stale-detection]
---

# The node id no longer points at the located object

## When this happens

The agent reads a node with `--at NODE`, but the held id no longer resolves to the object it was minted for — because the session was re-attached (the `sessionEpoch` moved), or the tree changed so the structural path now resolves to a different object, or the recorded pointer is no longer a valid object of the recorded class. Per [[domain.uitool.node-id]], the server validates before every deref and refuses to dereference a recycled pointer.

## What the user sees

A `STALE_NODE` failure: a non-zero exit (exit 5 from [[domain.uitool.ipc]]) and a one-line structured JSON error on stderr with a `recover` hint. No node record is emitted on stdout. `STALE_NODE` is the canonical wire code (exit 5), confirmed in [[domain.uitool.ipc]]'s closed error vocabulary.

> `{"code":"STALE_NODE","message":"node 7:w0/cv/sv2/sub0 no longer resolves to the recorded NSVisualEffectView","recover":"re-locate the node with windows/tree/find and read the freshly-minted id"}`

## What the user can do

- **Re-locate the node** — re-run `windows`/`tree`/`find` to mint a fresh node id, then read that id. The breadcrumb form of the id (a sibling `sub0`→`sub1` shift) is often guessable without a full re-search.
- **Do not re-issue the same read** — the same stale id yields the same `STALE_NODE`; re-issuing is the wrong recovery.

## Underlying cause (informational)

- `sessionEpoch` mismatch after `attach`/re-attach.
- Structural path re-walk lands on an object whose `object_getClass` differs from the recorded class.
- `FLEXPointerIsValidObjcObject(ptr)` fails for the recorded pointer.
- The registry was invalidated by `reset`, `detach`, or a key-window change.

## Related

- [[domain.uitool.node-id]] — the validation rules and the `STALE_NODE` contract.
- [[command.uitool.node]] — the verb that surfaces this.
- [[story.uitool.node-stale-detection]] — the observable behavior.


## Source: `Features/uitool/0006-node/errors/uitool.node-value-timeout.md`

---
id: error.uitool.node-value-timeout
kind: error
depends-on: [domain.uitool.ipc, command.uitool.node]
---

# A value-fetching read timed out on the target's main thread

## When this happens

The agent reads a node with a value-fetching facet (`--include ivars`/`props`, or any facet that invokes live getters). Those run on the target's main thread under a bounded timeout per [[domain.uitool.ipc]]; if the main-thread hop does not complete in time the op returns `TIMEOUT` rather than hang or risk the host. This is the failure mode the default structural projection avoids by never invoking getters.

> **Scope.** The value-fetching facets that trigger this are part of the deferred injection / expensive-verb half — they are not served in the cheap-read build of [[command.uitool.node]] (which accepts only the structural `class`/`frame`/`constraints`/`layer` facets and never invokes getters). This error pins the contract that half must satisfy once it lands; until then `node` cannot reach it, because the cheap-read structural facets never time out this way.

## What the user sees

A non-zero exit (exit 7 from [[domain.uitool.ipc]]) and a one-line structured JSON error on stderr with a `recover` hint. No node record is emitted on stdout. The target app is left alive. The wire code is the canonical `TIMEOUT` (exit 7) from [[domain.uitool.ipc]]'s closed vocabulary — a main-thread-hop timeout and a socket timeout share the one code and exit 7.

> `{"code":"TIMEOUT","message":"value-fetching read of 7:w0/cv/sv2/sub0 did not complete within the main-thread timeout","recover":"retry the read without --include ivars/props, or narrow the value fetch"}`

## What the user can do

- **Retry without the value-fetching facet** — read the same node with only the structural facets (`class`,`frame`,`constraints`,`layer`); the default projection and the structural facets never invoke getters and will not time out this way.
- **Retry later** — a transiently busy main thread may complete the next attempt; the read is idempotent.
- **Narrow the value fetch** — fetch fewer ivars via the value-fetching facet's `--match REGEX` narrowing. This narrowing arrives with the deferred injection half alongside `--include ivars`/`props` (specified with that pass); the standalone `ivars` verb exposes the same filter.

## Underlying cause (informational)

- The target's main thread was busy past the bounded main-thread timeout.
- A live getter / `-description` invoked by the value fetch was slow or blocked.

## Related

- [[domain.uitool.ipc]] — the main-thread marshaling rule and the timeout / exit-code mapping (`TIMEOUT` → exit 7).
- [[command.uitool.node]] — the verb that surfaces this; the cost-tier note on the value-fetching facets and their deferral to the injection half.


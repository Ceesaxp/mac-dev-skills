<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# uitool CLI contract

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.

## Source: `Specs/models/agent-cli.md`

---
id: domain.agent-cli
kind: domain
---

# Domain: the AgentCLI contract

The machine contract every tool in this repo obeys, realized as the `AgentCLI` library so honoring it is a dependency, not a memory. This is the through-line that lets one agent drive a symbol-graph query engine and a live process inspector the same way. See `ARCHITECTURE.md` → "The unifying contract".

`AgentCLI` is **pure** (Foundation only — no ArgumentParser, no I/O beyond the explicit stdout/stderr edges). Its projection functions return strings and are unit-tested on any Mac; the printing/exiting functions are the effectful edge.

## Output projection

- **Scalar result → `Output.json(_:)`** — a pretty-printed JSON string with **sorted keys** and **forward slashes unescaped** (`[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`).
- **Stream → `Output.line(_:)`** — one **compact, single-line** JSON object (sorted keys, slashes unescaped) per record; the stream is newline-delimited (JSON-Lines).
- **`Output.emit(_:)` / `Output.emitLines(_:)`** print the above to **stdout** — the machine payload, and nothing else, lands on stdout.

### Determinism invariants

1. **Sorted keys.** Object members are emitted in sorted key order, always.
2. **No slash escaping.** `/` is never written as `\/`.
3. **Byte-identical for equal input.** The same `Encodable` value encodes to the same bytes across runs and processes.
4. **Stable floats.** Floating-point fields are rounded to a fixed number of decimal places (`stableRounded(_:places:)`, default 3) before encoding, so accumulated FP error never changes the bytes.
5. **No volatile fields in the default projection.** No addresses, timestamps, or PIDs unless a verb explicitly asks for them.
6. **JSON-Lines records carry no embedded newline.** Each record is exactly one line.

A consequence: `diff` over two runs is trustworthy, and an agent may cache results by input.

## Exit-code taxonomy

Exit codes are the control channel; a tool never exits `0` on failure, and a zero-result query (no matches) is **success**, distinct from a failure.

- `ExitStatus.success` = **0**
- `ExitStatus.usage` = **2** (a usage/validation error; matches ArgumentParser's validation exit)

Tools extend the space **above 2** with their own meanings via the `AgentError` protocol (e.g. uitool's `stale-node` = 5, `precondition` = 6, `timeout` = 7). `AgentError` carries:

- `exitCode: Int32` — the code to exit with.
- `message: String` — a human-readable diagnostic, written to **stderr**.

## stdout / stderr discipline

- **stdout** carries the JSON payload alone. No prompts, spinners, progress, color, or pagers — ever.
- **stderr** carries diagnostics: `Diagnostics.warn(_:)` for a non-fatal note, `Diagnostics.fail(_:)` to write an `AgentError`'s message and exit with its code.
- **Color** is off by default and never emitted; `NO_COLOR` is therefore satisfied by construction.

## Acceptance

- `[scenario.agent-cli.sorted-keys]` Object keys encode in sorted order.
- `[scenario.agent-cli.no-escape]` Forward slashes are not escaped.
- `[scenario.agent-cli.deterministic]` Equal input encodes byte-identically.
- `[scenario.agent-cli.jsonlines]` A stream record is one compact object per line, with no embedded newline.
- `[scenario.agent-cli.stable-float]` Float rounding is stable to the requested places.
- `[scenario.agent-cli.exit-taxonomy]` `success` is 0 and `usage` is 2.


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


## Source: `Features/uitool/0001-doctor/commands/uitool.doctor.md`

---
id: command.uitool.doctor
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.doctor-preconditions]
---

# `uitool doctor` — report what you can inject into from here

## Synopsis

```
uitool doctor [--fix]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| (none) | — | — | `doctor` takes no target; it inspects only the local machine. |
| `--fix` | flag | no | Opt into sudo auto-remediation of the remediable **unrestricted-mode** checks ([[domain.uitool.injection]]). Off by default — `doctor` detects and instructs unless `--fix` is passed. Echoes each command before running it, never runs anything implicitly, and stops at steps that need Recovery (SIP via `csrutil`) or a reboot, printing exactly which manual steps remain. The cooperative posture has **nothing for `--fix` to remediate** — it requires no machine state change (see below). |

There is no `--json` flag: JSON is the only output. The consumer is a coding agent, not a human at a TTY, so output is always deterministic JSON on stdout ([[architecture]]) — there is no human-readable mode to toggle.

## The two injection postures

macOS gates injection **per target**, and which gate applies depends on **who controls the target's code signing**. `doctor` reports **both** postures so an agent knows what it can attach to from here — not one machine-wide pass/fail verdict that treats every target as hostile.

### Cooperative — inspect apps you build and sign (the default dev loop)

The target is an app **the user builds and signs for development**. A debug build is signed with `get-task-allow` (Xcode does this by default) — the entitlement by which the app **opts in** to being debugged and injected. Its hardened runtime is off, or it carries `com.apple.security.cs.allow-dyld-environment-variables` + `com.apple.security.cs.disable-library-validation`. The user controls all of this because it is their build.

This works on a **stock, SIP-enabled Mac**. SIP's debugging restriction protects only Apple-signed system/restricted processes; a `get-task-allow` target is honored for task-port access and dyld insertion **regardless of SIP** — exactly how `lldb` / Xcode / Reveal / InjectionIII attach to your own apps on a stock machine. Library validation and the hardened runtime are **per-process** flags the user sets in their own build, not machine-wide gates.

The v1 mechanism is **launch**: spawn the target with `DYLD_INSERT_LIBRARIES=<…>/UIToolBoot.dylib` so the boot dylib loads at launch and `dlopen`s the server. (A running `get-task-allow` target can also be attached via its task port, `lldb`-style, with the dylib remote-loaded — heavier, a later slice.) A normal Xcode app is **arm64**, so the injectable must be the **arm64** `UIToolBoot` — the `-arm64e_preview_abi` boot-arg is **not** involved here; it exists only for third-party arm64e code.

**Machine requirements: none beyond the OS.** No `csrutil`, no `nvram` boot-args, no library-validation override, no reboot. The two requirements `doctor` checks here are an Apple Silicon host and the **arm64** `UIToolBoot` injectable being present. The per-**target** preconditions (the target is `get-task-allow`, and for the launch path permits dyld env vars) are checked at attach/launch time against a named target — **not** by this machine doctor.

### Unrestricted — inspect apps you did NOT sign (system / notarized)

The target is **any** app, including ones the user did not sign — Mail, Finder, a notarized third-party app. These ship with the hardened runtime + library validation and **no `get-task-allow`**, so there is **no per-app lever to flip**. The only path is to lower the protections **machine-wide**: SIP disabled, `amfi_get_out_of_my_way=0x1`, library validation disabled, `-arm64e_preview_abi`, and the injectable built **arm64e** to match the system frameworks (the shared cache is arm64e on Apple Silicon).

**Machine requirements: the full defang stack** — the existing per-check interpreters. This is a dedicated dev box that holds no real data, reversible from Recovery.

> **The reframe.** The defanged machine is required **only** for non-cooperative targets. For the user's own apps, `uitool` runs on a stock, SIP-enabled Mac. `doctor` was previously documented as if every target were hostile — that is the **worst case, not the floor**.

## Behavior

`doctor` is **pure local detection** — it runs before any injection and does **not** open the IPC socket or contact a target ([[domain.uitool.ipc]] describes the post-injection wire protocol, which this command does not use). It evaluates the **machine-wide** subset of the precondition stack defined in [[domain.uitool.injection]], judging **each check independently** so a half-configured machine yields an itemized verdict rather than a single mystery failure, then **groups** those checks into the two postures:

1. Evaluate each machine-wide precondition independently — every check in the stack except `target running`, which requires a named target `doctor` does not take, and the per-target `get-task-allow` / dyld-env preconditions, which are checked at attach time.
2. Group the checks into two `ModeReport`s — **cooperative** and **unrestricted** — each carrying its own `requires` set and a `usable` flag that is true only when **every** check it requires passes.
3. For each failing check, record the one-line remedy.
4. Emit both reports and set the exit code from `cooperative.usable`.

`doctor` is **detect-and-instruct by default**: it reports failures and their remedies but does not change machine state. Auto-remediation is opt-in via `--fix` ([[domain.uitool.injection]]): with `--fix`, `doctor` runs the remediable boot-arg / library-validation commands (the **unrestricted** posture's checks) under sudo, echoing each command before it runs, never running anything implicitly, and stopping at steps that require Recovery (SIP via `csrutil`) or a reboot — it sets what it can, then prints exactly which manual steps + reboot remain. The cooperative posture needs no machine state change, so `--fix` has nothing to apply there. Without `--fix`, machine state is never mutated.

The **target running**, **`get-task-allow`**, and **dyld-env** checks are part of the per-attach gate in [[domain.uitool.injection]] but are **not** evaluated by `doctor`, which takes no target argument; the output below lists exactly the machine-wide checks each posture needs. Those per-target checks are evaluated only by `attach` once a target is named.

## Output

A single JSON object on stdout: the two posture reports plus the OS build. Each `ModeReport` carries its own `usable` flag, its ordered `requires` array (one entry per check), and a one-line `note` saying what the posture is for. `pass` is true/false per check; `remedy` is present only on a failing check (one line, never a stack trace).

```jsonc
{
  "cooperative": {
    "usable": false,
    "requires": [
      { "check": "arch",             "pass": true,  "detail": "arm64e" },
      { "check": "injectable-arm64", "pass": false, "detail": "absent",
        "remedy": "build the arm64 UIToolBoot injectable (the injection half is not yet built)" }
    ],
    "note": "Inspect apps you build and sign for development (get-task-allow). No SIP / AMFI / library-validation changes — your machine is already capable."
  },
  "unrestricted": {
    "usable": false,
    "requires": [
      { "check": "sip",               "pass": true,  "detail": "disabled" },
      { "check": "amfi",              "pass": false, "detail": "enforcing",
        "remedy": "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot" },
      { "check": "libval",            "pass": true,  "detail": "disabled" },
      { "check": "arm64e-abi",        "pass": true,  "detail": "present" },
      { "check": "arch",              "pass": true,  "detail": "arm64e" },
      { "check": "injectable-arm64e", "pass": false, "detail": "absent",
        "remedy": "build the arm64e UIToolBoot injectable (the injection half is not yet built)" }
    ],
    "note": "Additionally required only to inspect apps you did NOT sign (system / notarized). Dedicated dev box; reversible from Recovery."
  },
  "osBuild": "26.3 (26D...)"
}
```

Output is deterministic: each `requires` array is emitted in a fixed order (as listed above), with stable key order and no addresses or timestamps. A posture's `usable` is true only when **every** check in its `requires` passes.

### The check sets per posture (pinned)

- **`cooperative.requires`** = `[ arch, injectable-arm64 ]`.
  - `arch` — the host is Apple Silicon (arm64e-capable).
  - `injectable-arm64` — the **arm64** `UIToolBoot` injectable is present (matches a normal Xcode arm64 app).
  - No `sip`, no `amfi`, no `libval`, no `arm64e-abi` — a stock SIP-enabled Mac is already capable for this posture.
- **`unrestricted.requires`** = `[ sip, amfi, libval, arm64e-abi, arch, injectable-arm64e ]`.
  - `sip` / `amfi` / `libval` / `arm64e-abi` — the machine-wide defang stack.
  - `arch` — the host is Apple Silicon (the **same** check the cooperative posture uses).
  - `injectable-arm64e` — the **arm64e** `UIToolBoot` injectable is present (matches the arm64e system frameworks / shared cache).

### Frozen check ids, detail tokens, and remedies

The per-check `check` ids and `detail` values are a **frozen, byte-stable contract** so the output can be asserted by **snapshot tests**. The per-check interpreters for `sip` / `amfi` / `libval` / `arm64e-abi` / `arch` and their tokens and remedies are **unchanged**; what changes is how they are **grouped** into the two postures and that the single `uitool-built` check is **split** into the posture-specific `injectable-arm64` (cooperative) and `injectable-arm64e` (unrestricted). `detail` is a fixed token per check, never free prose:

| check | posture(s) | `detail` when `pass` | `detail` when fail | remedy on fail |
| --- | --- | --- | --- | --- |
| `sip` | unrestricted | `disabled` | `enabled` | `boot to Recovery and run: csrutil enable --without kext --without dtrace; csrutil authenticated-root disable` |
| `amfi` | unrestricted | `disabled` | `enforcing` | `sudo nvram boot-args="amfi_get_out_of_my_way=0x1 -arm64e_preview_abi" && reboot` |
| `libval` | unrestricted | `disabled` | `enabled` | `sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true` |
| `arm64e-abi` | unrestricted | `present` | `absent` | `sudo nvram boot-args="amfi_get_out_of_my_way=0x1 -arm64e_preview_abi" && reboot` |
| `arch` | both | `arm64e` | `arm64` \| `x86_64` (the reported arch) | `run uitool on an Apple Silicon (arm64e-capable) host` |
| `injectable-arm64` | cooperative | `present` | `absent` | `build the arm64 UIToolBoot injectable (the injection half is not yet built)` |
| `injectable-arm64e` | unrestricted | `present` | `absent` | `build the arm64e UIToolBoot injectable (the injection half is not yet built)` |

The `arch` check is **shared**: it appears in both `requires` arrays and reports the same verdict in each (an Apple Silicon host satisfies both postures; `x86_64` fails both). `detail` is the concrete reported arch, per the spec's "the built arch" failure token.

The top-level `osBuild` records the OS build (e.g. `26.3 (26D...)`) because precondition validity is OS-build-specific (arm64e injection regresses across Tahoe 26.x); it is **not a check**, never affects either posture's `usability`, and is normalized out of snapshot assertions (like a session id), not part of the byte-stable contract. `null` when it could not be read.

### Not ready today — and why

Today **neither posture is usable**, but for **different reasons**, and the report makes the distinction explicit:

- The **cooperative** posture fails today **only** on `injectable-arm64` — the arm64 `UIToolBoot` is not built yet. This is the **deferred injection half**, **not** a machine-defang gap. The machine itself needs **no** SIP / AMFI / library-validation change for the user's own apps; the report shows `arch` passing on any Apple Silicon Mac and only the (deferred) dylib missing.
- The **unrestricted** posture additionally fails on whichever of `sip` / `amfi` / `libval` / `arm64e-abi` are unmet on this machine, plus `injectable-arm64e`.

So the verdict is "not ready today," but `doctor` makes clear the cooperative path's only blocker is the deferred dylib, not anything the user must defang.

## States & exit codes

The exit code is driven by **`cooperative.usable`** — the cooperative posture is the common case, so it governs the control channel. Exit codes otherwise map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| `cooperative.usable` is true | 0 | both posture reports on stdout |
| `cooperative.usable` is false | 6 | both posture reports (with per-check remedies) on stdout; a one-line structured error on stderr ([[error.uitool.doctor-precondition-failed]]) |
| `--fix` remediated every remediable **unrestricted** check; only Recovery/reboot steps remain | 6 | both reports plus the remaining manual steps; the echoed commands and a one-line structured error on stderr — a reboot is still required, and `cooperative.usable` is unaffected by it |
| `--fix` ran and `cooperative.usable` is true | 0 | both reports on stdout (re-run after any reboot to confirm the unrestricted posture) |

**Today, `doctor` exits 6** — because `cooperative.usable` is false (the arm64 `UIToolBoot` is not built). The report explains that this gap is the **deferred injection half**, **not** a missing machine defang. Exit 6 is `PRECONDITION_FAILED` ([[domain.uitool.ipc]]); it stays precondition-only.

## Invariants

- Read-only and side-effect-free **by default**: inspects machine state, never mutates it unless `--fix` is passed ([[domain.uitool.injection]]).
- With `--fix`, mutation is explicit and visible: every command is echoed before it runs, nothing runs implicitly, Recovery/reboot steps are reported as remaining rather than performed, and only the **unrestricted** posture's remediable checks are touched.
- Reports **both** postures every run, so an agent always knows whether it needs the defang at all or just a cooperative target.
- The cooperative posture's `requires` never includes a machine-wide defang check — for the user's own apps the machine needs no SIP / AMFI / library-validation change.
- Does not open the IPC socket or contact any target process — it is the pre-injection gate, not a query.
- Each precondition is judged independently; no check is skipped because another failed ([[domain.uitool.injection]] invariant).
- Exit is 0 iff `cooperative.usable`; otherwise 6 (`PRECONDITION_FAILED`) — never exit 0 when the cooperative posture is not usable.
- Output is deterministic across runs on an unchanged machine.

## Notes

Cost tier: **cheap/bounded** — a fixed set of local reads (`csrutil status`, `nvram boot-args`, the LV plist, a `uname -m` arch read, two injectable-presence stats), no target process, no socket, no unbounded work.

The unrestricted posture's `arm64e-abi` and the `amfi`/`arm64e-abi` shared remedy command remain single points of failure tracked by [[domain.uitool.injection]] — `-arm64e_preview_abi` is removable by Apple in any point release, and arm64e injection is actively regressing on Tahoe 26.x. None of that touches the cooperative posture, which depends on neither boot-arg.


## Source: `Features/uitool/0001-doctor/commands/uitool.list-apps.md`

---
id: command.uitool.list-apps
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.doctor-list-apps]
---

# `uitool list-apps` — list attachable processes

## Synopsis

```
uitool list-apps [--match <substring>]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `--match` | string | no | Keep only processes whose **name or bundle id** contains the value (case-insensitive substring). Default: all attachable processes. |

## Behavior

`list-apps` is **pure local detection** — like [[command.uitool.doctor]] it runs before any injection and does **not** open the IPC socket or contact a target ([[domain.uitool.ipc]] is the post-injection protocol, unused here). It enumerates the running processes that are candidates for attachment and annotates each:

1. Enumerate **every running process with an attachable task port** — not just GUI apps; background and system processes are included. `list-apps` filters nothing by kind; the agent narrows with `--match`.
2. If `--match` is given, keep only the processes whose name or bundle id matches (case-insensitive substring).
3. For each remaining process, read its pid, name, bundle id, hardened flag, and architecture.
4. Emit the listing.

The **hardened** flag and **arch** are reported so the agent can read its attach expectations off [[domain.uitool.injection]]'s attach-path table; `list-apps` itself decides nothing about which path applies and attaches to nothing. It surfaces the inputs (hardened, arch); the attach-path determination belongs to `attach`, against that table.

## Output

A JSON object on stdout carrying the apps array; each entry is one attachable process.

```jsonc
{
  "apps": [
    { "pid": 5123, "name": "Mail",         "bundleId": "com.apple.mail",          "hardened": true,  "arch": "arm64e" },
    { "pid": 6710, "name": "SampleAppKit", "bundleId": "dev.uitool.SampleAppKit", "hardened": false, "arch": "arm64" }
  ]
}
```

Output is deterministic for a given set of processes: the `apps` array is **sorted by `bundleId` ascending** (processes without a bundle id sort last, ordered by `name`), with `name` then `pid` as tiebreakers — `pid` is never the primary key (it is non-deterministic across runs). Stable key order, no addresses or timestamps. `arch` is one of `arm64e` / `arm64` / `x86_64` (a running process is a single concrete slice, never `universal`). `name` is the display name (or the executable/process name for non-app processes), distinct from `bundleId`, which may be absent for non-app processes.

An empty match yields `{"apps": []}` and exit 0 — an empty result is distinct from an error, per [[domain.uitool.ipc]]: a query matching nothing is exit 0, never a non-zero precondition code. `list-apps` represents zero matches as exit 0.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| listing produced (including zero matches) | 0 | the apps object on stdout |
| usage / bad `--match` argument | 2 | a one-line structured error on stderr |

## Invariants

- Read-only and side-effect-free: enumerates and inspects processes, never attaches or mutates.
- Does not open the IPC socket or contact any target process.
- An empty result (zero attachable apps, or zero matches) is exit 0 with an empty `apps` array — never an error.
- Output is deterministic: stable sort, stable key order, no addresses/timestamps.

## Notes

Cost tier: **cheap/bounded** — a single process-list enumeration plus a fixed per-app metadata read (bundle id, code-signing hardened flag, arch), no target process, no socket.


## Source: `Features/uitool/0002-attach/commands/uitool.launch.md`

---
id: command.uitool.launch
kind: command
depends-on: [domain.uitool.injection, domain.uitool.boot, domain.uitool.server, domain.uitool.ipc, domain.uitool.node-id, story.uitool.launch]
---

# `uitool launch` — start an app under inspection

## Synopsis

```
uitool launch <bundle-id|path> [--replace] [--pretty] [--no-meta] [-- <app-args>…]
```

`launch` brings a target up **fresh** with the inspector already loaded — the
cooperative **launch path** ([[domain.uitool.injection]]): `posix_spawn` under
`DYLD_INSERT_LIBRARIES=…/UIToolBoot.dylib` so the [[domain.uitool.boot]] dylib
loads before `main` and starts the [[domain.uitool.server]]. Use it when a clean
launch state is wanted. To inspect an app **as it sits right now**, preserving its
on-screen state, use [[command.uitool.attach]] instead.

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<bundle-id\|path>` | string | yes | the app to launch, by bundle id or path to a `.app` |
| `--replace` | flag | no | if a same-user instance of the target is already running, terminate it first, then launch fresh. Default off — without it, an already-running target is a usage error directing you to `attach` (see Behavior) |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `launch` (single-object result). Default off |
| `-- <app-args>…` | strings | no | arguments passed through to the launched app after `--`. Default none |

## Behavior

1. Resolve `<bundle-id|path>` to a launchable `.app` bundle. If none resolves, fail (exit 3, [[error.uitool.launch-not-found]]).
2. If a same-user instance of the target is already running: without `--replace`, fail (exit 2) with a message directing the agent to [[command.uitool.attach]] (to inspect it preserving state) or to re-run with `--replace`. With `--replace`, terminate the running instance(s) first.
3. Verify the cooperative launch preconditions ([[domain.uitool.injection]]): Apple Silicon host, the **arm64** [[domain.uitool.boot]] dylib present, and the target permits dyld environment variables (a debug build, or one carrying `com.apple.security.cs.allow-dyld-environment-variables`). On any failed precondition, fail (exit 6, [[error.uitool.attach-precondition]]) — never silently proceed.
4. `posix_spawn` the bundle's executable with `DYLD_INSERT_LIBRARIES` pointing at the arm64 boot dylib and any `-- <app-args>` appended, then poll (bounded) for the per-pid socket to appear ([[domain.uitool.ipc]] transport at `/tmp/uitool-<pid>.sock`).
5. On the socket opening, bump the session epoch ([[domain.uitool.node-id]]) and perform the schema handshake (`ping`); a schema-version mismatch fails (exit 8, [[error.uitool.attach-schema-mismatch]]).
6. If the handshake does not return within its bounded window — the socket opened but the target never answered — fail (exit 7, [[error.uitool.attach-timeout]]); the epoch **stays incremented** (it is never rolled back, [[command.uitool.attach]] epoch invariant).
7. If the socket never opens within the bounded wait — the spawn failed to exec, or the dylib failed to load — fail (exit 4, [[error.uitool.attach-injection-failed]]); never report success.
8. Emit the result.

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses or timestamps in the default projection.

```jsonc
{
  "ok": true,
  "target": { "pid": 4930, "bundleId": "com.example.SampleAppKit" },
  "path": "launch",            // always "launch" for this command
  "channel": "open",
  "schemaVersion": "1.0.0",    // string semver from the ping handshake — see [[domain.uitool.ipc]]
  "replaced": false,           // true when --replace terminated a prior running instance first — a command-result flag, never stripped by --no-meta
  "sessionId": "8"             // the session marker (wire form of node-id's sessionEpoch); stripped by --no-meta
}
```

> The key set (`ok`, `target`, `path`, `channel`, `schemaVersion`, `replaced`,
> `sessionId`) is the contract the read verbs branch on, parallel to
> [[command.uitool.attach]]'s. `path` is always `"launch"` here; `attach` reports
> `"running"`.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| launched & attached | 0 | the result object on stdout |
| usage / already running without `--replace` | 2 | structured error on stderr |
| app not found / not launchable | 3 | structured error on stderr (see [[error.uitool.launch-not-found]]) |
| injection failed (socket never opened) | 4 | structured error on stderr (see [[error.uitool.attach-injection-failed]]) |
| precondition failed (arch / arm64 injectable / dyld-env) | 6 | structured error on stderr with one-line remediation (see [[error.uitool.attach-precondition]]) |
| socket / handshake timeout | 7 | structured error on stderr (see [[error.uitool.attach-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (see [[error.uitool.attach-schema-mismatch]]) |

## Invariants

- **`launch` always starts a new process**, so it always opens a **new session
  with a fresh epoch** ([[domain.uitool.node-id]]); it is never idempotent the way
  a re-`attach` is, and never reports `reused`. Two `launch`es are two sessions.
- **`launch` loses the target's prior on-screen state by design** — it is a clean
  launch. Preserving live state is [[command.uitool.attach]]'s job
  ([[domain.uitool.injection]] trade-off).
- **Never terminates a running instance without `--replace`.** A silent kill could
  lose the user's data; `launch` refuses (exit 2) and names the explicit path
  forward (repo "no silent fallback" rule).
- Never exits 0 on failure; a spawn whose socket never opens is exit 4, never
  silent success ([[domain.uitool.injection]] invariant).
- The cooperative launch precondition stack gates the spawn; a failed precondition
  is exit 6 ([[domain.uitool.injection]]).
- Read-only with respect to the target's behavior once attached: v1 ships no
  write/mutation op ([[domain.uitool.ipc]]).

## Notes

- **Cost tier: expensive (and mutating).** Like `attach`, `launch` spawns a
  process and waits on a bounded poll; reserve it for session boundaries.
- **`launch` vs `attach`.** `launch` = fresh instance, clean state, robust across
  OS/app updates; `attach` = the already-running instance, live state preserved.
  `--replace` is the old `attach --relaunch` semantics relocated to where the
  spawn actually lives — relaunch *is* a launch.
- **Process ownership after detach.** `launch` owns the process it spawned only
  until `detach`; `detach` removes the inspection bridge and **never** terminates
  the target ([[command.uitool.detach]]), so a launched process keeps running and
  its lifecycle thereafter is the researcher's concern
  ([[story.uitool.attach-release]] scenario.uitool.attach-release.app-survives-relaunched).
- The bounded poll/wait for the socket is a fixed internal bound (not a flag) in
  this build, as in [[command.uitool.attach]]; surfacing it as configurable is
  deferred until there is a second caller asking for it.


## Source: `Features/uitool/0002-attach/commands/uitool.attach.md`

---
id: command.uitool.attach
kind: command
depends-on: [domain.uitool.injection, domain.uitool.boot, domain.uitool.server, domain.uitool.ipc, domain.uitool.node-id, story.uitool.attach-inject]
---

# `uitool attach` — inspect a running app, preserving its state

## Synopsis

```
uitool attach <pid|bundle-id> [--pretty] [--no-meta]
```

`attach` reaches into an **already-running** target and slips the inspector in
**without restarting it** — the cooperative **attach-to-running** path
([[domain.uitool.injection]]): acquire the target's task port (`task_for_pid`,
permitted for your own same-user `get-task-allow` process) and remote-`dlopen` the
[[domain.uitool.boot]] dylib, which starts the [[domain.uitool.server]]. The app
keeps its exact current on-screen state — the research default. To start a target
**fresh** from a clean state (or to inspect a cold, not-yet-running app), use
[[command.uitool.launch]] instead.

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<pid\|bundle-id>` | string | yes | the target **running** process, by pid or bundle id |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `attach` (single-object result). Default off |

## Behavior

1. Resolve `<pid|bundle-id>` to a **running** target process. If no such process exists, fail (exit 3, [[error.uitool.attach-not-running]]) — `attach` does not start a cold app; use [[command.uitool.launch]] for that.
2. Verify the cooperative attach-to-running preconditions ([[domain.uitool.injection]]): an Apple Silicon host, the arm64 [[domain.uitool.boot]] dylib present, `uitool` signed with the debugger entitlement, and the target being same-user and `get-task-allow`. On any failed precondition, fail (exit 6) — never silently proceed.
3. If the target already has a healthy server from the current session, reuse it and report success without bumping the session epoch ([[domain.uitool.injection]] lifecycle; idempotent).
4. Otherwise acquire the target's task port (`task_for_pid`) and remote-`dlopen` the [[domain.uitool.boot]] dylib into it — which starts the [[domain.uitool.server]] — then poll (bounded) for the per-pid socket to appear ([[domain.uitool.ipc]] transport at `/tmp/uitool-<pid>.sock`).
5. On the socket opening, bump the session epoch ([[domain.uitool.node-id]]) and perform the schema handshake (`ping`); a schema-version mismatch fails (exit 8).
6. If the handshake (`ping`) does not return within its bounded window — the socket opened but the target never answered — fail (exit 7); never report success ([[error.uitool.attach-timeout]]). When the handshake times out (exit 7) or the schema mismatches (exit 8) after the epoch was bumped in step 5, the epoch **stays incremented** — it is not rolled back — so the next attempt always gets a fresh epoch and any handle minted against the half-open session reads as stale rather than silently valid (see the epoch invariant below).
7. If the socket never opens within the bounded wait, fail (exit 4) — never report success.
8. Emit the result.

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses or timestamps in the default projection.

```jsonc
{
  "ok": true,
  "target": { "pid": 4821, "bundleId": "com.example.SampleAppKit" },
  "path": "running",           // always "running" for attach; uitool launch reports "launch"
  "channel": "open",
  "schemaVersion": "1.0.0",    // string semver from the ping handshake — see [[domain.uitool.ipc]]
  "reused": false,             // true when an existing server was reused (idempotent re-attach) — a command-result flag, not list/stream `_meta`; never stripped by --no-meta
  "sessionId": "7"             // the session marker (wire form of node-id's sessionEpoch); stripped by --no-meta — see [[domain.uitool.ipc]]
}
```

> The exact key set above is the cheap-read MVP's documented shape. Pinning it
> against the live socket — and any fields the injected server adds once the
> injection half is built — is part of that deferred half; this build commits to
> the keys shown (`ok`, `target`, `path`, `channel`, `schemaVersion`, `reused`,
> `sessionId`) as the contract the read verbs branch on.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| attached (newly or reused) | 0 | the result object on stdout |
| usage / bad selector | 2 | structured error on stderr |
| target not running | 3 | structured error on stderr (see [[error.uitool.attach-not-running]]) |
| injection failed (socket never opened) | 4 | structured error on stderr (see [[error.uitool.attach-injection-failed]]) |
| precondition failed (SIP/AMFI/LV/arch) | 6 | structured error on stderr with one-line remediation (see [[error.uitool.attach-precondition]]) |
| socket / handshake timeout | 7 | structured error on stderr (see [[error.uitool.attach-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (see [[error.uitool.attach-schema-mismatch]]) |

## Invariants

- Idempotent: a second `attach` on an already-attached target reuses the existing server and does not bump the session epoch ([[domain.uitool.injection]]).
- The session epoch is bumped exactly once per new attach attempt that opens the socket, before the success result is emitted ([[domain.uitool.node-id]]). A failed attach (handshake timeout, exit 7; schema mismatch, exit 8) bumps the epoch in step 5 before the failure is known, and **leaves it incremented** — the epoch is never rolled back. This pins the idempotency check in step 3: a re-attach that finds a socket left over from a previous failed `ping` is treated as a **fresh attach** (re-handshake, fresh epoch), not "already attached" — a leftover socket from a half-open session is not a healthy server to reuse. "Already attached" (reuse, no bump) means a server that completed its handshake in this session.
- Never exits 0 on failure; injection that does not take is exit 4, never silent success ([[domain.uitool.injection]] invariant).
- The precondition stack gates every injection path; a failed precondition is exit 6 ([[domain.uitool.injection]]).
- `attach` is **attach-to-running only** — it preserves the target's live state and never starts or restarts the app. Starting a fresh instance is [[command.uitool.launch]]'s job ([[domain.uitool.injection]]).

## Notes

- **Cost tier: expensive (and mutating).** `attach` is one of the only non-read-only, non-idempotent-in-effect verbs (alongside `detach`); it acquires the target's task port and remote-loads the inspector, then waits on a bounded poll. The read verbs are cheap; reserve `attach`/`launch`/`detach` for session boundaries.
- **Attach-to-running preserves the target's current UI state** — the research default ("inspect it as it sits right now"). For your **own** `get-task-allow` apps this is the everyday lldb/Reveal technique on a stock Mac, not a brittle one. The brittle, version-fragile route is the *unrestricted* attach into a target you did **not** sign — the MIP-style `launchservicesd` hook — which stays deferred (HANDOFF M5, [[domain.uitool.injection]]). For a clean launch state, use [[command.uitool.launch]].
- The bounded poll/wait duration for the socket appearing is a fixed internal bound (not a flag) in this build; whether to surface it as a configurable flag waits for a second caller asking for it.
- Resolving a bundle-id to a target that is not currently running is **exit 3 (not running)**: `attach` requires an already-running process and does not auto-launch a cold app. To start a cold app under inspection, use [[command.uitool.launch]] (which owns process spawning and ownership).


## Source: `Features/uitool/0002-attach/commands/uitool.detach.md`

---
id: command.uitool.detach
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, domain.uitool.node-id, story.uitool.attach-release]
---

# `uitool detach` — end an inspection session

## Synopsis

```
uitool detach <app> [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the target, by pid or bundle id, as passed to `attach` |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `detach` (single-object result). Default off |

## Behavior

1. Resolve `<app>` to a target.
2. If the target is attached in the current session, instruct the injected server to close and unlink the socket and drop the registry ([[domain.uitool.ipc]] threading: on unload, close socket, unlink path, drop the registry; [[domain.uitool.injection]] lifecycle: detach → close socket, drop registry).
3. If the target is not attached (or already detached), treat the detach as already satisfied — idempotent.
4. Emit the result.

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses or timestamps in the default projection.

```jsonc
{
  "ok": true,
  "target": { "pid": 4821, "bundleId": "com.example.SampleAppKit" },
  "channel": "closed",
  "wasAttached": true,               // false when nothing was attached (idempotent no-op) — a command-result flag, not list/stream `_meta`; never stripped by --no-meta
  "sessionId": "7"                   // the session being torn down; stripped by --no-meta — see [[domain.uitool.ipc]]
}
```

> The exact key set above is the cheap-read MVP's documented shape. This build
> commits to the keys shown (`ok`, `target`, `channel`, `wasAttached`,
> `sessionId`) as the contract; any fields the injected server adds on teardown
> are part of the deferred injection half.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| detached (or already detached) | 0 | the result object on stdout |
| usage / bad selector | 2 | structured error on stderr |

## Invariants

- Idempotent: detaching a target that is not attached succeeds (exit 0) and reports the channel closed ([[domain.uitool.injection]] lifecycle).
- Detach closes the socket, unlinks its path, and drops the registry ([[domain.uitool.ipc]], [[domain.uitool.node-id]] — the registry is invalidated on detach).
- After a successful detach, a read query to the same target is not-attached (exit 4) until the next `attach`.
- Read-only with respect to the target's behavior: detach removes the inspection bridge but does not mutate the app's state.

## Notes

- **Cost tier: bounded (and mutating).** `detach` is one of the only mutating verbs (alongside `attach`). It is cheap relative to `attach` — no precondition stack, no injection, no bounded socket poll — but it changes session state, so it is not idempotent-in-effect the way the read verbs are.
- Detaching does not terminate the target. For a process started by [[command.uitool.launch]], detach removes only the inspection bridge and never kills the target, so the launched process keeps running and its lifecycle thereafter is the researcher's concern — `launch` does not adopt ownership past detach. See [[story.uitool.attach-release]] scenario.uitool.attach-release.app-survives-relaunched.


## Source: `Features/uitool/0003-windows/commands/uitool.windows.md`

---
id: command.uitool.windows
kind: command
depends-on: [domain.uitool.node, domain.uitool.ipc, domain.uitool.node-id, story.uitool.windows-enumerate]
---

# `uitool windows` — list top-level windows

## Synopsis

```
uitool windows <app> [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target — pid or bundle id, same resolution as every other verb |
| `--pretty` | flag | no | pretty-print JSON; defaults off (machine-first) |
| `--no-meta` | flag | no | suppress the top-level `sessionId` and `_meta` so output is fully byte-stable; defaults off |

## Behavior

1. Resolve `<app>` to the attached session's socket per [[domain.uitool.ipc]]; if no session is attached, fail per [[domain.uitool.ipc]].
2. Issue the [[domain.uitool.ipc]] `hierarchy` op with `maxDepth: 0` and `window: "all"` to the injected server. `maxDepth: 0` projects window roots only — no descendant walk — which is exactly what this verb returns; there is no dedicated `windows` op. The server enumerates the target's top-level windows on the main thread and mints a [[domain.uitool.node-id]] for each window root. The window-enumeration op is the shared `hierarchy` op constrained to `maxDepth: 0` and `window: "all"`; `windows` is a thin CLI verb over it, not a distinct server op — the same op the single-node and tree verbs bind to at their own depths.
3. For each window root, project the window-relevant fields (see Output) and serialize off the main thread.
4. Emit one record per window on stdout.

The set of windows enumerated is the public top-level set: the entries of `NSApp.windows` that are user-facing — ordinary windows and panels (`NSPanel`), including off-screen ones (a window the user has moved off a display, or one positioned but not yet ordered front, is still part of the app's window surface and is reported). Internal and system-owned windows are filtered out: an entry is excluded when it is not a user-facing window — concretely, when `canBecomeKeyWindow` and `canBecomeMainWindow` are both false **and** the window has no title and a zero or off-screen frame (AppKit's hidden helper/utility windows). The NARRATIVE's "off-screen, internal, or system-owned beyond what the contract pins" is pinned here: off-screen user windows are in; internal/system-owned helpers are out.

## Output

JSON-Lines: one window record per line, in `NSApp.windows` array order. That array order is the canonical window sort key — it is the basis for the `wN` window index in [[domain.uitool.node-id]]'s structural path (`w0` is `NSApp.windows[0]`, `w1` is `[1]`, …), so the record order, the node ids, and the structural breadcrumbs all agree. Z-order is **not** the sort key (it is non-deterministic across turns as the user raises and lowers windows); window number is not used either.

Each record is a window-root [[domain.uitool.node]] (so `parent` is `null` at a window root) projected to exactly four base node fields — `node`, `parent`, `class`, `frame` — plus three **window-only** fields not present on a view node: `title`, `key`, and `main`. These three are window-level facts ([[domain.uitool.node]] is a *view* node, which a window root does not have); they are additive fields that appear only on this verb's records and do **not** extend [[domain.uitool.node]]'s field table. The view-relative node fields (`frameTopLeft`, `isFlipped`, `hidden`, `alpha`, `childCount`, etc.) are **not** emitted here: a window root is not enclosed by a view, so they do not apply.

The window `frame` is in **screen coordinates** — `NSWindow.frame` with AppKit's bottom-left screen origin — at 1 dp. Because a window root has no enclosing view, `frameTopLeft` and `isFlipped` do not apply and are omitted (the consumer reads `frame` as screen-space directly; there is no view to flip against).

JSON-Lines, one window record per line on stdout:

```jsonc
{"node":"7:w0","parent":null,"class":"NSWindow","title":"Inbox — Mail","frame":{"x":0,"y":0,"w":1200,"h":800},"key":true,"main":true}
{"node":"7:w1","parent":null,"class":"NSPanel","title":"Find","frame":{"x":1240,"y":120,"w":360,"h":220},"key":false,"main":false}
```

When `--no-meta` is not set, the response also carries the [[domain.uitool.ipc]] envelope on its own trailing line: the mandatory `schemaVersion` (a semver **string**, e.g. `"1.0.0"`, on every payload per [[domain.uitool.ipc]]), a top-level `sessionId` (string), and, for this list verb, `_meta: {returned, truncated, totalMatched}`:

```jsonc
{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":2,"truncated":false,"totalMatched":2}}
```

`--no-meta` strips `sessionId` and `_meta` so output is byte-stable across sessions; `schemaVersion` is **not** suppressible — it is on every payload per [[domain.uitool.ipc]]. An empty window set still exits **0** with `_meta.totalMatched: 0` — it is a valid empty result, never a failure.

## States & exit codes

Exit codes are the [[domain.uitool.ipc]] mapping; the relevant rows:

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (≥ 1 window) | 0 | one record per window on stdout |
| success, no windows open | 0 | empty list + `_meta.totalMatched: 0` on stdout (see [[error.uitool.windows-no-windows]]) |
| usage / bad selector | 2 | structured error on stderr |
| not attached / injection failed | 4 | structured error on stderr (see [[error.uitool.windows-not-attached]]) |
| socket / main-thread timeout | 7 | structured error on stderr (see [[error.uitool.windows-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr |

`windows` is a post-attach query verb: it assumes a live session, so the attach-time codes do not surface here. App-not-running (exit 3) and SIP/AMFI/LV preconditions (exit 6) are attach-time only per [[domain.uitool.ipc]] — an unreachable session surfaces here as **exit 4** (not attached) or **exit 7** (timeout), never 3 or 6. Window enumeration does not deref a caller-supplied node id, so `STALE_NODE` (exit 5) is not reachable from this verb either. Exit 1 is unused here, as in [[domain.uitool.ipc]] — it is reserved by the shell for generic failure.

## Invariants

- Read-only and side-effect-free; idempotent — re-running on an unchanged target yields byte-identical output modulo `sessionId`.
- Deterministic: stable key order, fixed window order, frames at 1 dp, no addresses or timestamps in the default projection.
- An empty window list (exit 0) is distinct from an error (never exit 0 on failure).
- **At most one** record is flagged `key` and **at most one** `main`. When the app is frontmost with a focused window, exactly one record is `key` and exactly one is `main`. But AppKit allows `keyWindow`/`mainWindow` to be `nil` — when the app is backgrounded, or has only non-key-capable panels open, or has no windows — and in that case the verb reports **zero** `key` and/or **zero** `main` rows. The verb never synthesizes a key/main flag to force exactly one; it reports the live AppKit truth. (`key` and `main` are independent: a window can be `main` without being `key`, e.g. while a panel holds key.)
- `parent` is `null` for every record (window roots have no parent), per [[domain.uitool.node]].

## Notes

Cost tier: **cheap / bounded**. This is the cheapest query in the surface — a fixed, tiny payload independent of view-tree size, with no descendant walk. It is the intended first call of a session: list windows, then `tree`/`find` into the chosen one.


## Source: `Features/uitool/0004-tree/commands/uitool.tree.md`

---
id: command.uitool.tree
kind: command
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.selector, domain.uitool.ipc]
---

# `uitool tree` — depth-bounded hierarchy walk

The structural-exploration verb. Walks the view hierarchy from a chosen root
down a finite depth, projects a chosen set of fields per node, and emits an
explicit truncated marker at every branch cut off by the depth limit. It never
walks the whole tree — `--depth` is always finite and small by default. The
coding agent is the consumer; output is machine-first.

## Synopsis

```
uitool tree <app> [--at NODE] [--depth N] [--fields a,b,c] [--where EXPR] [--limit N] [--count-only] [--jsonl]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | target selector — pid or bundle id of an attached app |
| `--at` | string | no | node id ([[domain.uitool.node-id]]) to root the walk at. Default: when `--at` is omitted, the walk roots at the target's **key window** — the same root the IPC `hierarchy` op selects for `window:"auto"`. A target with no key window (no front window, fully backgrounded) yields an empty walk (exit 0, `_meta.totalMatched: 0`), not an error. To walk a specific non-key window, pass its window-root node id (from a prior `windows` call) as `--at`. |
| `--depth` | int | no | levels to descend below the root, inclusive of the root level. Default: **2**. This is the Skill-steered structural-skim depth (`tree --depth 2`); deeper walks are an explicit, costed choice. `--depth` is always finite — there is no "walk everything" value. |
| `--fields` | string | no | comma-separated projection paths (e.g. `node,class,frame`), as defined by [[domain.uitool.node]]'s dotted field projection. Default: the default projection from [[domain.uitool.node]] |
| `--where` | string | no | server-side filter expression ([[domain.uitool.selector]]) applied to nodes within the depth window. The predicate selects which nodes are **emitted**; it does not prune the walk. A node that fails `--where` is omitted from the result, but the walk still descends into its in-window descendants and emits any of them that match — a deep match is never hidden behind a shallow non-match. Parent linkage in emitted records refers to the nearest *emitted* ancestor; when an intermediate ancestor was filtered out, its `parent` is the nearest surviving ancestor within the depth window (and is absent for the walk root). A `--where` expression that does not parse is a `BAD_PREDICATE` error (exit 2) before any walking begins — see [[error.uitool.tree-bad-projection]]. |
| `--limit` | int | no | maximum number of node records to emit; the walk stops once reached. Default: **50**. The default exists so an unexpectedly wide level can never flood the agent's context; raise it deliberately with `--limit N` when a known-wide level must be read whole. A walk stopped by `--limit` sets `_meta.truncated: true`. To size a query before paying for it, use `--count-only`. |
| `--count-only` | flag | no | size the query without transferring node bodies: run the walk + `--where` filter server-side and return only the envelope (`schemaVersion`, `sessionId`, `_meta`) with `_meta.totalMatched` set to the number of nodes the walk matched within the depth window. No node records cross the wire. Use it to decide whether to widen `--limit`, tighten `--where`, or descend a different branch before paying for the bodies. |
| `--jsonl` | flag | no | explicit opt-in to the JSON-Lines stream output shape. **JSON-Lines is already the default for `tree`** (it is a list/stream verb), so `--jsonl` is a no-op kept for symmetry with the other stream verbs and for callers that want to state the shape explicitly. `tree` never emits a single nested object; the wire shape is always one node record per line followed by the trailing envelope line. |

## Behavior

1. Resolve `<app>` to the attached target's socket; if there is no live session
   (never attached, or the session has gone away), this is exit 4 — not a
   precondition failure (preconditions are attach-time only, see States & exit
   codes).
2. Resolve `--at` to a live object: re-walk the structural path and validate per
   [[domain.uitool.node-id]]'s deref rules. On any mismatch, return `STALE_NODE` —
   never dereference a recycled pointer. When `--at` is omitted, the root is the
   target's key window (`window:"auto"`), resolved the same way.
3. Issue the [[domain.uitool.ipc]] `hierarchy` op with `maxDepth` from `--depth`, the
   resolved root, and `include` derived from `--fields`. Filtering and projection
   happen **server-side, in the injected agent** — only the projected, in-window,
   matching nodes cross the wire.
4. The server walks each node down to `maxDepth`. At a node that has children but
   sits at the depth limit, it emits `truncated: true` and `childCount` and omits
   `children` — the depth-cut marker contract defined by [[domain.uitool.node]] (its
   `children` field is present only within `--depth`; past it, omitted with
   `truncated: true` + `childCount`).
5. Apply `--where` to select which walked nodes are emitted; a non-matching node
   is dropped from the result but its in-window descendants are still walked and
   emitted on their own merits.
6. Project each emitted node to the requested `--fields`; `node` is always
   present so the agent can drill in later.
7. Emit the result, stopping at `--limit`. A capped result sets
   `_meta.truncated: true` ([[domain.uitool.ipc]]'s single canonical "more exist" flag).
   Under `--count-only`, steps 6–7 are skipped: no node bodies are emitted, only
   the envelope with `_meta.totalMatched`.

## Output

Each node follows [[domain.uitool.node]] — same field semantics, same precision, same
truncated-marker shape. The agent uses each node's `node` handle to issue
follow-up `node` calls on survivors.

`tree` emits a **JSON-Lines stream**: one node record per line, in walk order,
followed by a single trailing envelope line. The agent consumes incrementally,
and an interrupted read still yields N whole, valid node records up to the cut.
This is the contracted wire shape (`--jsonl` is the explicit, no-op opt-in to
it); `tree` never emits a single nested object.

```jsonc
{"node":"7:w0/cv/sv2","parent":"7:w0/cv","class":"NSScrollView","frame":{"x":0,"y":0,"w":280,"h":600},"childCount":1}
{"node":"7:w0/cv/sv2/sub0","parent":"7:w0/cv/sv2","class":"NSClipView","childCount":1,"truncated":true}
{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":2,"truncated":true,"totalMatched":2}}
```

The trailing envelope line conforms to [[domain.uitool.ipc]]'s envelope — a top-level
`schemaVersion` (semver string, in *every* payload and never stripped), a
top-level `sessionId` (string), and, on this list/stream verb, `_meta:
{returned, truncated, totalMatched}`; `--no-meta` strips `sessionId` and `_meta`
but not `schemaVersion`:

- A node cut off by `--depth` carries `truncated: true` + `childCount` and omits
  `children`. A node whose whole subtree is within `--depth` is never marked
  truncated.
- `_meta.returned` is the node count emitted; `_meta.totalMatched` is the count
  of nodes the walk matched within the depth window (0 for an empty walk). Under
  `--count-only`, `_meta.returned` is 0 and `_meta.totalMatched` carries the full
  matched count.
- `_meta.truncated` — the single canonical "more exist past the limit/depth"
  flag — is true if any branch was depth-cut or if `--limit` stopped the walk.
- Output is deterministic per [[domain.uitool.node]]'s determinism invariant: stable key
  order, children in subview / z-order, frames to 1 dp, no addresses/timestamps in
  the default projection (modulo the suppressible top-level `sessionId`).

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table. `tree` is a **post-attach query
verb**, so it carries neither exit 3 (app not running) nor exit 6 (precondition)
— both are attach-time only, emitted while `doctor` / `list-apps` / `attach`
resolve and inject. An unreachable session surfaces here as exit 4 (not
attached) or exit 7 (timeout), never 3 or 6.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (including a fully-contained tree, a depth-truncated tree, a `--count-only` sizing, and a walk that contains zero nodes) | 0 | the payload on stdout |
| usage / unknown `--fields` path (`UNKNOWN_FIELD`) / malformed `--where` predicate (`BAD_PREDICATE`) | 2 | structured error on stderr — see [[error.uitool.tree-bad-projection]] |
| not attached / injection failed (or a session that has gone away post-attach) | 4 | structured error on stderr |
| `--at` handle is stale | 5 | structured error on stderr — see [[error.uitool.tree-stale-root]] |
| main-thread snapshot timed out | 7 | structured error on stderr |
| schema-version mismatch | 8 | structured error on stderr |

A valid walk that matches/contains zero nodes (an empty subtree, a target with
no key window, or a `--where` that excludes everything) is **exit 0**, not an
error — the response carries an empty stream and `_meta.totalMatched: 0`. The
agent distinguishes empty from error by reading `_meta`, never by the exit code;
a 0-match result means *broaden the selector*, not re-issue. See
[[domain.uitool.ipc]].

## Invariants

- Read-only and side-effect-free; idempotent. Same target state → byte-identical
  output (modulo the suppressible `sessionId`).
- `--depth` is always finite; the command never walks the whole tree regardless
  of input.
- Every emitted node carries its `node` handle even under the narrowest `--fields`.
- A depth-cut node is always distinguishable from a leaf: `truncated: true` +
  `childCount > 0` vs `childCount: 0` (a leaf is never marked truncated).
- Never exits 0 on failure; a stale `--at` is exit 5, never a silent empty tree.
- A truncated read (process killed mid-stream) still yields whole, valid node
  records up to the cut — a property of the JSON-Lines wire shape.
- `--count-only` transfers no node bodies; it returns only the envelope and is a
  strict subset of a full walk's work (same matched count, no projection cost).

## Notes

- **Cost tier: cheap / bounded.** This is one of the read verbs the Skill steers
  toward (`tree --depth 2`); the per-node deep reads (the `node` verb's expensive
  facets — ivars, props) are the costed follow-ups on a single chosen survivor.
  The whole point is tree *search*, not tree *download*.
- Cost scales with `--depth` and subtree fan-out; pair with `--fields` to keep a
  structural skim tiny, `--limit` to cap an unexpectedly wide level, and
  `--count-only` to size a query before paying for the bodies.
- **No stdin batching.** `tree` walks a single root per spawn; batching multiple
  roots through stdin is reserved for the per-node `node` verb (its `--stdin`
  mode). A multi-branch exploration issues one `tree` per branch, each rooted by
  `--at` on a handle from the prior walk — which is exactly the bounded,
  one-branch-at-a-time access pattern this feature exists to make cheap.


## Source: `Features/uitool/0005-find/commands/uitool.find.md`

---
id: command.uitool.find
kind: command
depends-on: [domain.uitool.selector, domain.uitool.node-id, domain.uitool.node, domain.uitool.ipc]
status: draft
---

# `uitool find` — locate few

<!--
  The cheap "locate few" entry point of the canonical loop. Resolves a class
  selector and/or a --where predicate server-side, optionally counts, caps, and
  projects, then emits only the matched nodes. Pure-core decision logic the CLI
  wraps; testable without injection by feeding it captured match data.
-->

## Synopsis

```
uitool find <app> [--class GLOB] [--where EXPR] [--fields PATHS] [--limit N] [--count-only]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target — pid or bundle id (e.g. `com.apple.mail`) |
| `--class` | string (glob) | no | a bare **class glob** per [[domain.uitool.selector]]; class matching honors the runtime class hierarchy. `--class` accepts a class glob only — the richer structural combinators (descendant, child, attribute) live in `--where`, not here. The two flags compose: `--class` narrows by class, `--where` adds predicate constraints over the survivors. |
| `--where` | string (predicate) | no | a predicate expression per [[domain.uitool.selector]] (total, bounded; `and`/`or`/`not`, `matches`, `intersects`, `~`). A `matches`/`~` operand is a **Swift-native `Regex`** — case-insensitive, unanchored substring (`firstMatch`); an invalid pattern throws at construction and surfaces as a usage error (exit 2, see [[error.uitool.find-bad-selector]]), never a hang or a silent zero-match. |
| `--fields` | string | no | projection path list per [[domain.uitool.selector]] (`node,class,frame,font`); ignored when `--count-only`. When omitted, `find` emits the **full default node projection** from [[domain.uitool.node]] (the default field set: `node`, `class`, `frame`/`frameTopLeft`/`isFlipped`, and the other default fields that model defines) — not a `find`-specific minimal default. The HANDOFF examples pass `--fields` explicitly because narrow projection is the cheaper habit, but the default is the full node projection, so an agent that omits the flag still gets a complete, well-defined record. |
| `--limit` | int | no | cap on returned node records; does not affect the reported total matched count. **Default: 50.** Override with `--limit N` to widen or tighten the cap. Pair with `--count-only` first to size a query before paying for the records. |
| `--count-only` | flag | no | report only the total matched count; return no node records. The cheapest sizing call — "size it before you pay." |

At least one of `--class` / `--where` is required. `find <app>` with neither is a **usage error** (exit 2, see [[error.uitool.find-bad-selector]]): an unconstrained full enumeration is exactly the expensive tree-download the cost-tiering exists to discourage, so the surface refuses it rather than silently matching every node. To enumerate broadly on purpose, pass an explicit broad selector (e.g. `--class '*'`) and size it with `--count-only` first.

## Behavior

1. Resolve `<app>` to the attached session; if no session is attached, fail (exit 4 per [[domain.uitool.ipc]]).
2. Require at least one of `--class` / `--where`; neither present is a usage error (exit 2, see [[error.uitool.find-bad-selector]]).
3. Parse `--class` and/or `--where` into the selector / predicate per [[domain.uitool.selector]]; a parse failure — an unknown combinator, an unbalanced bracket, or an **invalid `Regex` pattern in a `matches`/`~` operand** — is a usage error (exit 2, see [[error.uitool.find-bad-selector]]).
4. Issue the matching op (`find`) to the injected server, which evaluates the selector / predicate **server-side** against the live tree on the target's main thread (per [[domain.uitool.ipc]]); only matching nodes cross the wire.
5. If `--count-only`: emit the total matched count in `_meta.totalMatched`; return no records.
6. Otherwise: project each matched node to `--fields` per [[domain.uitool.node]] (or the full default projection when `--fields` is omitted), cap to `--limit` (default 50), emit the records, then emit the result-summary `_meta` marker (per [[domain.uitool.ipc]]'s envelope).

## Output

Responses conform to [[domain.uitool.ipc]]'s envelope. Every payload — every JSON-Lines object, including each node-record line — carries `schemaVersion` (a semver **string**, e.g. `"1.0.0"`, per [[domain.uitool.ipc]]). Unless `--no-meta` is passed, the response also carries a top-level `sessionId` (string) and, on the streamed result, a `_meta: {returned, truncated, totalMatched}` summary; `--no-meta` strips both `sessionId` and `_meta` (never `schemaVersion`).

`sessionId` appears **once per response, on the summary line** — the single `--count-only` object, or the trailing `_meta` line of the multi-record stream — not repeated on every node-record line. A node-record line carries its `schemaVersion` and projected fields only; the session is identified once for the whole stream.

`--count-only` — a single JSON object carrying the match count in `_meta.totalMatched`, with no node records:

```jsonc
{"schemaVersion":"1.0.0","sessionId":"a1b2c3","_meta":{"returned":0,"truncated":false,"totalMatched":3}}
```

Otherwise — JSON-Lines: one matched node per line (projected to `--fields`, fields from [[domain.uitool.node]]), then a final `_meta` line carrying the per-stream `sessionId`:

```jsonc
{"schemaVersion":"1.0.0","node":"7:w0/cv/sv0/tv0/tr0/c0#b2c4","class":"NSTextField","frame":{"x":34,"y":8,"w":160,"h":16},"font":{"family":"SF Pro Text","size":13,"weightName":"regular"}}
{"schemaVersion":"1.0.0","sessionId":"a1b2c3","_meta":{"returned":1,"truncated":false,"totalMatched":1}}
```

- One node per line so the agent consumes incrementally and a truncated read still yields N valid records (per [[domain.uitool.ipc]] / HANDOFF §8.1).
- `_meta.returned` = records emitted; `_meta.truncated` = true when `totalMatched > returned` because of `--limit` (the single canonical "more exist" flag per [[domain.uitool.ipc]] — never a second `limitHit`); `_meta.totalMatched` = the full server-side match count regardless of `--limit`.
- Deterministic: stable key order, children/records in z-order (never address order), frames to 1 dp, no addresses/timestamps in the default projection. `pointer` is a pull-on-demand field, never a sort key (see [[domain.uitool.node-id]]).
- `--no-meta` strips the summary line's `sessionId` and the `_meta` summary for byte-identical diffs across sessions, but never `schemaVersion` (which is in every payload per [[domain.uitool.ipc]]).

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (≥1 match, or any `--count-only`) | 0 | payload on stdout |
| valid query, 0 matches | 0 | empty result on stdout, `_meta.totalMatched: 0` (a 0-match query is **not** an error per [[domain.uitool.ipc]]) |
| malformed selector / predicate, or neither `--class` nor `--where` given | 2 | structured error on stderr (see [[error.uitool.find-bad-selector]]) |
| not attached | 4 | structured error on stderr (see [[error.uitool.find-not-attached]]) |
| socket / main-thread timeout | 7 | structured error on stderr (see [[error.uitool.find-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (defined by [[domain.uitool.ipc]]'s exit-code table; not a find-specific error) |

## Invariants

- Read-only and side-effect-free; idempotent — re-running with the same target state yields byte-identical output (modulo the suppressible `sessionId`).
- Filtering and projection happen **server-side**; the CLI never pulls the tree to filter or project locally (per [[domain.uitool.selector]]).
- Never exits 0 on failure. A valid 0-match result is distinct from a usage error (exit 2) — re-issuing the same query is the wrong recovery for a 0-match.
- `--count-only` reports `totalMatched` unaffected by `--limit`; with records, `_meta.totalMatched` likewise reflects all matches, not just the returned slice.
- Class predicates resolve through the runtime class hierarchy, not string equality (per [[domain.uitool.selector]]).
- Predicate `matches`/`~` operands evaluate as Swift-native `Regex` (case-insensitive, unanchored substring); an invalid pattern is rejected at parse time (exit 2), never deferred to a partial result.
- Evaluation is total and bounded — no selector or predicate can hang the target (per [[domain.uitool.selector]]); exceeding the main-thread budget yields exit 7, not a hang.

## Notes

- **Cost tier: cheap / bounded.** `find --count-only` is the cheapest sizing call; `find --where … --limit N --fields …` is bounded by `--limit` (default 50) and the projection. This is the first verb the Skill steers toward — locate few → project narrow → read deep on the survivors. The expensive deep-read verbs (`node`, `font`, `layer`, `constraints`) then operate on the 1–3 survivors `find` returns.
- Batching: large inputs are stdin JSON-Lines elsewhere in the surface (per HANDOFF §8.5). `find` itself is single-query per spawn — one `--class`/`--where` per process — in this build; stdin batching of selectors/predicates is reserved for the node-resolution verbs, where a batch of stable handles is the natural unit.


## Source: `Features/uitool/0006-node/commands/uitool.node.md`

---
id: command.uitool.node
kind: command
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.ipc]
---

# `uitool node` — deep-read one located node

The drill step of the canonical loop (locate few → project narrow → **read deep on the survivors**). Reads a single node the agent has already located and pulls the on-demand facets the default tree/find projection omits. It does not walk a subtree and does not search.

## Synopsis

```
uitool node <app> --at NODE [--include class,frame,constraints,layer]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | target selector (pid or bundle id) — the attached session to query |
| `--at` | node id | yes | the [[domain.uitool.node-id]] of the single node to read |
| `--include` | comma list | no | facets to pull beyond the default projection; subset of `class,frame,constraints,layer` in the cheap-read MVP (`ivars`/`props` are deferred — see below). Default: none (default projection only) |

The `--include` tokens map to fields of [[domain.uitool.node]]:

| Token | Adds to the record |
| --- | --- |
| `class` | `superclasses` (the runtime hierarchy; the real `class` is already in the default projection) |
| `frame` | **No-op kept for symmetry.** `frame`, `frameTopLeft`, and `isFlipped` are already default-projection fields of [[domain.uitool.node]] (it never omits frames), so `--include frame` requests nothing new — it is accepted (not rejected as a bad token) and changes nothing in the record. The token exists only so an agent can name `frame` uniformly across verbs without special-casing `node`. |
| `constraints` | **Inlines the full constraint list.** The default projection carries only `constraintsCount`; `--include constraints` inlines the walker's `ConstraintNode` (every touching `NSLayoutConstraint` plus the intrinsic-sizing facts — the same shape the dedicated `constraints` verb returns) into the node record, alongside the still-present `constraintsCount`. |
| `layer` | `layer` (the recursive `LayerSnapshot` where `wantsLayer`; `null` otherwise) |

### Deferred facets (`ivars`, `props`) — not available in this build

`--include ivars` and `--include props` are **value-fetching** facets: they invoke live getters / read instance state **inside the target process**, so they belong to the deferred injection / expensive-verb half (see [[domain.uitool.ipc]] → "Default mode: structural, no-invoke" and HANDOFF §8.2 / §11). They are **not part of the cheap-read MVP** and are **not available in this build**:

- The cheap-read `node` build accepts only the structural tokens (`class`, `frame`, `constraints`, `layer`). Passing `ivars` or `props` is reported as a **not-yet-available facet** — an explicit, structured usage error (exit 2) naming the facet and that it requires the injection half — never a silently-dropped token. The agent learns the facet exists but is not yet served, rather than getting a quietly thinner record than it asked for.
- When the injection half lands, `ivars`/`props` join the `--include` vocabulary as value-fetching facets. They run on the target's main thread under [[domain.uitool.ipc]]'s bounded timeout; on timeout the op returns `TIMEOUT` (see [[error.uitool.node-value-timeout]]). Their inlined shape (a map of name → boxed value) and any `--match REGEX` narrowing are specified with that pass, not here.

The `material`, `blendingMode`, and `font` pull-on-demand handling of [[domain.uitool.node]] is unchanged: `material` and `font` are already default-projection fields; `blendingMode` and the visual-effect specifics are reached through their dedicated verbs, not inlined here, and have no `--include` token on `node`.

## Behavior

1. Resolve `<app>` to the attached session's socket (per [[domain.uitool.ipc]] transport).
2. Validate `--at` is a well-formed node id; reject malformed ids as a usage error (exit 2) before issuing any op.
3. Validate the `--include` tokens. An unknown token, or a deferred value-fetching token (`ivars`/`props`) in this build, is a usage error (exit 2) — the deferred ones name the facet and that it requires the injection half.
4. Issue one [[domain.uitool.ipc]] op to read the single node rooted at `--at`, carrying the requested structural `include` facets. The single-node read is the **`hierarchy` op pinned to `maxDepth: 0`** — `node` binds to the tree/hierarchy op at depth 0 rather than a distinct op (per [[domain.uitool.ipc]]'s operations table), so it reads exactly one node and never its descendants.
5. The injected server resolves and validates the node id before any deref (re-walk path, pointer validity, recorded-class match per [[domain.uitool.node-id]]); on mismatch it returns `STALE_NODE`.
6. (Injection half, deferred) Value-fetching facets (`ivars`/`props`, and any facet that invokes live getters) run on the target's main thread under the bounded timeout from [[domain.uitool.ipc]]; on timeout the op returns `TIMEOUT`. The cheap-read structural facets never invoke getters and never hit this path.
7. Project the one node to [[domain.uitool.node]]'s default fields plus exactly the requested facets, and emit it.

## Output

A single JSON object (scalar query, not JSON-Lines) describing one node, per [[domain.uitool.node]]. Default-projection fields always present; only the requested `--include` facets are added. Deterministic per [[domain.uitool.ipc]]: stable key order, fixed precision, no addresses/timestamps in the default projection.

```jsonc
// uitool node com.apple.mail --at 7:w0/cv/sv2/sub0 --include constraints,layer
{
    "schemaVersion": "1.0.0",
    "sessionId": "7",
    "node": "7:w0/cv/sv2/sub0",
    "parent": "7:w0/cv/sv2",
    "class": "NSVisualEffectView",
    "frame": { "x": 0, "y": 40, "w": 280, "h": 600 },
    "frameTopLeft": { "x": 0, "y": 0, "w": 280, "h": 600 },
    "isFlipped": false,
    "hidden": false,
    "alpha": 1.0,
    "identifier": "MailMessageListSidebar",
    "text": null,
    "axRole": "AXGroup",
    "font": null,
    "material": "sidebar",
    "constraintsCount": 4,
    "swiftUIBoundary": false,
    "childCount": 7,
    "constraints": [
        { "firstItem": "7:w0/cv/sv2/sub0", "firstAttribute": "width", "relation": "==", "constant": 280, "priority": 1000 }
    ],
    "layer": { "present": true, "cornerRadius": 6, "masksToBounds": true, "backgroundColor": "#00000000" }
}
```

Requested facets that do not apply to the node are emitted as `null` (e.g. `layer: null` on an unbacked view, or `font: null` on a node with no font carrier), never omitted — so the agent distinguishes "asked, absent" from "not asked". (`--include frame` is the one exception: a no-op that adds nothing, since the frame fields are already default.)

Per [[domain.uitool.ipc]]'s envelope, the record carries a top-level `sessionId` (string) — the wire form of [[domain.uitool.node-id]]'s `sessionEpoch`, so the agent can detect a re-attach. `node` is a scalar query, not a list/stream verb, so it does **not** carry `_meta` (that envelope key is for list/stream verbs only). `--no-meta` strips `sessionId`, making the output byte-identical across sessions.

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | the node object on stdout |
| malformed `--at` / unknown or deferred `--include` token | 2 | structured error on stderr |
| not attached / injection failed (`NOT_ATTACHED`) | 4 | structured error on stderr |
| node id no longer resolves (`STALE_NODE`) | 5 | structured error on stderr (see [[error.uitool.node-stale]]) |
| main-thread / socket timeout on a value-fetching read (`TIMEOUT`) | 7 | structured error on stderr (see [[error.uitool.node-value-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr |

`node` is a post-attach query verb: per [[domain.uitool.ipc]], exit 3 (app not running) and exit 6 (precondition failed) are attach-time only and never surface here. An unreachable session is exit 4 (`NOT_ATTACHED`) or exit 7 (`TIMEOUT`).

## Invariants

- Read-only and side-effect-free for the default projection and the structural facets; idempotent — same target state and same flags yield byte-identical output (modulo the top-level `sessionId` from [[domain.uitool.ipc]]'s envelope, which `--no-meta` strips for byte-identical output across sessions).
- Reads exactly one node — the `hierarchy` op at `maxDepth: 0`. Never emits child node records and never walks a subtree.
- Never exits 0 on failure. A `STALE_NODE` is exit 5, distinct from any success.
- Requested-but-inapplicable facets are `null`, not omitted; unrequested facets are absent, not `null`. `--include frame` is a no-op (the frame fields are already default).
- Value-fetching facets (`ivars`/`props`) are not served in this build and are rejected as a usage error (exit 2), never silently dropped. When served (injection half), they never block the host indefinitely — they are bounded by [[domain.uitool.ipc]]'s main-thread timeout.

## Notes

Cost tier: **cheap/bounded** for the default projection (which already carries `constraintsCount`, `material`, and `font`) and the structural `--include` facets (`class`/superclasses, `frame` no-op, `constraints`, `layer`) — one node, bounded, no-invoke work. **Expensive** for `--include ivars`/`props` (and any facet that invokes live getters): they run code inside the target, are timeout-bounded, and are off by default and deferred to the injection half per HANDOFF §8.2 / §11.

Batching: large id lists go over stdin as JSON-Lines (`uitool node --stdin < ids.jsonl`) so the agent resolves many nodes in one process spawn. With `--stdin` the output is **one JSON object per line (JSON-Lines), one per input id, in input order**, each line carrying that node's record (or a per-line error object for a stale/failed id). A `STALE_NODE` (or other per-id failure) on one id emits a per-line structured error and **continues** the batch rather than aborting it; the process exits **0** when every line was emitted (success or per-line error) and reserves a non-zero exit for a batch-level failure (not attached, schema mismatch, malformed stream). The per-line error object carries the same `code`/`message`/`recover` shape as the single-node stderr error, keyed to its input id, so the agent reconciles results to ids without losing the rest of the batch.


## Source: `Features/uitool/0007-inspect/commands/uitool.inspect.md`

---
id: command.uitool.inspect
kind: command
depends-on: [domain.uitool.registry, domain.runtime.reflection, domain.uitool.ipc, domain.uitool.node-id, story.uitool.inspect-read]
---

# `uitool inspect` — read a live object's ivars, properties, and reflection

## Synopsis

```
uitool inspect <app> --at <node-id> [--invoke] [--match <regex>] [--fields <fields>] [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target, by pid or bundle id |
| `--at <node-id>` | string | yes | the node to inspect ([[domain.uitool.node-id]]) |
| `--invoke` | flag | no | also invoke property **getters** to read property values. **Off by default** — getters run the target's own code; gated, timed, and safety-screened. See Safety. Default off |
| `--match <regex>` | string | no | narrow `ivars` and `properties` to names matching the Swift-Regex pattern ([[domain.uitool.selector]] grammar), so a large object isn't dumped wholesale. Default: all |
| `--fields <fields>` | string | no | projection path list over the result ([[domain.uitool.node]] `--fields`). Default: the full result |
| `--pretty` / `--no-meta` | flag | no | pretty-print / strip `sessionId` for byte-stable output. Default off |

## Behavior

1. Resolve `<app>` to its live session over the socket ([[domain.uitool.ipc]]); no session is `NOT_ATTACHED` (exit 4).
2. Send the `inspect` op with the node id, the `--invoke` flag, and the `--match` pattern.
3. The server resolves the node id to its live object through the [[domain.uitool.registry]] — re-walking the structural path and passing the four-gate validation (epoch, path, pointer validity, class echo); any failure is `STALE_NODE` (exit 5, [[error.uitool.node-stale]]), never a recycled-pointer read.
4. On the target main thread, under the bounded hop ([[domain.uitool.ipc]]), the server reflects the object via [[domain.runtime.reflection]]: the **ivar values** (safe memory reads), the **class reflection** (declared properties, instance methods, adopted protocols), and — only with `--invoke` — the **property values** from the getters.
5. A value read / getter that exceeds the bound returns `TIMEOUT` (exit 7, [[error.uitool.node-value-timeout]]); the target is left alive.
6. Project the result (deterministic: sorted keys, normalized values — see Output) and emit.

## Output

A single JSON object on stdout. Deterministic: stable key order, **no raw pointers or addresses**, no `-description` invocation in the default (no-`--invoke`) read.

```jsonc
{
  "node": "7:w0/cv/vev0",
  "class": "NSVisualEffectView",
  "ivars": [
    { "name": "_state", "type": "q", "value": 1 },                  // scalar, read from memory
    { "name": "_appearance", "type": "@", "value": { "class": "NSAppearance" } },  // object ivar → class (+ node if a registered view)
    { "name": "_material", "type": "q", "value": 7 }
  ],
  "properties": [
    { "name": "material", "type": "q", "readonly": false },         // metadata; value present only with --invoke
    { "name": "state",    "type": "q", "readonly": false, "value": 1 }   // value shown here because --invoke was passed
  ],
  "protocols": ["NSAccessibilityElement", "NSAppearanceCustomization"],
  "methods": ["material", "setMaterial:", "blendingMode"]
}
```

### Value representation (deterministic, no addresses)

- **Scalar ivars/values** (int / float / bool, by `@encode` type) are carried as the value.
- **Object-typed ivars/values** are carried as `{ "class": "<runtime class>" }`, plus `"node": "<id>"` when the object is a view registered in the [[domain.uitool.registry]] — **never** a raw pointer, and **never** the result of an invoked `-description` (that would run code). A short, bounded string is carried verbatim for `NSString`/`NSNumber`.
- **A raw pointer** is available only via `--fields pointer` (opt-in), never default — pointers are non-deterministic ([[domain.uitool.node-id]]).

## Safety

- **Ivar reads are safe and default.** They read memory at the ivar's offset; no target code runs. Ivars on a class `RuntimeSafety.classIsSafe` rejects, or that `RuntimeSafety.ivarIsSafe` flags, are **skipped** (omitted), never read.
- **Getter invocation is gated behind `--invoke`** and runs the target's own accessor code — it can block, mutate, or crash the host. Each invocation runs on the target main thread under the hard ~500 ms bound ([[domain.uitool.ipc]]); a slow/blocked getter is `TIMEOUT` (exit 7), never a hang. Getters on a `RuntimeSafety`-unsafe class are skipped. v1 invokes **getters only** — never a setter, never an arbitrary method.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| inspected | 0 | the result object on stdout |
| usage / bad `--match` / missing `--at` | 2 | structured error on stderr |
| not attached | 4 | structured error ([[domain.uitool.ipc]]) |
| stale node id | 5 | structured error ([[error.uitool.node-stale]]) |
| value-fetch / getter timeout | 7 | structured error ([[error.uitool.node-value-timeout]]) |
| schema mismatch | 8 | structured error |

## Invariants

- **Read-only.** `inspect` never sets an ivar or calls a setter; v1 mutates nothing ([[domain.uitool.ipc]] v1 read-only invariant).
- **Validate before deref.** Every resolution passes the four [[domain.uitool.registry]] gates; a stale handle is exit 5, never a recycled-pointer read.
- **No getter without `--invoke`.** The default read runs no target code; getter invocation is explicit, timed, and safety-screened.
- **Deterministic.** Sorted keys, normalized values, no addresses/pointers in the default projection — same object + same flags → byte-identical modulo `sessionId`.

## Notes

- **Cost tier: expensive (value-fetching).** Reserve `inspect` for the few nodes
  the structural verbs flagged as interesting; it resolves a live object and hops to
  main per read. `--invoke` is the most expensive and the only path that runs target
  code — use it deliberately.
- `--match` narrowing is what keeps a sprawling controller readable; the
  [[error.uitool.node-value-timeout]] recovery hint points at it.
- Methods and protocols are class reflection (cheap metadata from
  [[domain.runtime.reflection]]); they describe the class, not the instance, so they
  carry no per-instance value and are unaffected by `--invoke`.


## Source: `Features/uitool/0008-schema/commands/uitool.schema.md`

---
id: command.uitool.schema
kind: command
depends-on: [domain.uitool.node, domain.uitool.ipc, command.uitool.inspect, story.uitool.schema-print]
---

# `uitool schema` — print the output contract

## Synopsis

```
uitool schema [--pretty]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |

No target, no `--snapshot`, no injection — `schema` is a pure static read of the
contract the other verbs emit.

## Behavior

1. Emit the static output contract as one JSON object (see Output) and exit 0.

No app is resolved, no socket opened, no precondition checked — `schema` describes
the tool's output and never touches a target.

## Output

A single JSON object on stdout. Deterministic (stable key order, fixed content for
a given build): the record types the verbs emit, each with its fields, plus the
exit-code map.

```jsonc
{
  "schemaVersion": "1.0.0",                 // the IPC schema version ([[domain.uitool.ipc]])
  "exitCodes": {                            // the closed exit-code map the agent branches on
    "0": "ok (a zero-match query is still 0)",
    "2": "usage / BAD_SELECTOR / UNKNOWN_FIELD / BAD_PREDICATE",
    "3": "app not running / not found",
    "4": "NOT_ATTACHED / injection failed",
    "5": "STALE_NODE",
    "6": "precondition failed",
    "7": "TIMEOUT",
    "8": "schema-version mismatch"
  },
  "records": {                              // one entry per output record type
    "node": {
      "description": "a view-tree node (windows/tree/find/node)",
      "fields": [
        { "name": "node",  "type": "string", "default": true,  "description": "stable node id" },
        { "name": "class", "type": "string", "default": true,  "description": "real runtime class" },
        { "name": "layer", "type": "object|null", "default": false, "include": "layer", "description": "CALayer snapshot" }
        // … the full default + --include field set ([[domain.uitool.node]])
      ]
    },
    "window": { "description": "…", "fields": [ /* … */ ] },
    "inspect": { "description": "ivars + reflection ([[command.uitool.inspect]])", "fields": [ /* … */ ] }
  }
}
```

Each field carries `name`, `type`, a `default` flag (true when the verbs emit it
without `--include`), an optional `include` token (the `--include` facet that turns
it on), and a one-line `description`. The catalog mirrors [[domain.uitool.node]]'s
field table — it is the machine-readable form of that contract.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | the contract object on stdout |

`schema` has no failure mode: it takes no external input and does no I/O beyond
printing. (A malformed flag is ArgumentParser's usage exit, as for any command.)

## Invariants

- **Static and offline.** No app, no node, no socket, no injection — `schema` never
  touches a target and is runnable on any Mac.
- **Deterministic.** Stable key order, fixed content for a given build; same build →
  byte-identical output.
- **Mirrors the node contract.** The `node` record's fields are exactly
  [[domain.uitool.node]]'s default + `--include` set; a field added there is added
  here (a drift guard, not a free-form doc).

## Notes

- **Cost tier: free.** No I/O, no target. The cheapest verb.
- The contract is **authored data**, the machine-readable twin of
  [[domain.uitool.node]] / [[command.uitool.inspect]]; keep it in step with those
  specs and the `Node` / `InspectResult` types (a test asserts the `node` record's
  field names match the projected node's keys).


## Source: `Features/uitool/0009-signing/commands/uitool.signing.md`

---
id: command.uitool.signing
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.signing-read]
---

# `uitool signing` — read a target's code signature

## Synopsis

```
uitool signing <pid|bundle-id|path> [--pretty]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<pid\|bundle-id\|path>` | string | yes | a running pid, a bundle id, or a path to a `.app` / executable |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |

No injection, no attach — `signing` reads the signature off the target's binary.

## Behavior

1. Resolve `<target>` to a binary path: a pid → its executable; a bundle id → the app's executable; a path → the executable inside a `.app`, or the file itself. If none resolves, fail (exit 3, app not found).
2. Read the code signature via the Security framework (signing info + entitlements + CS flags).
3. Derive the **cooperative-injectability** verdict from the facts ([[domain.uitool.injection]] — see Verdict).
4. Emit the report (exit 0).

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses.

```jsonc
{
  "target": "com.example.SampleAppKit",
  "signed": true,
  "identifier": "com.example.SampleAppKit",   // the code-signing identifier, or null
  "teamId": null,                              // TeamIdentifier, or null (ad-hoc / unsigned)
  "authority": "ad-hoc",                       // "ad-hoc", the leaf authority CN, or "unsigned"
  "hardenedRuntime": false,                    // the CS_RUNTIME flag
  "sandboxed": false,                          // com.apple.security.app-sandbox
  "getTaskAllow": true,                        // com.apple.security.get-task-allow — the cooperative lever
  "entitlements": {                            // the injection-relevant entitlements only
    "com.apple.security.get-task-allow": true
  },
  "cooperativeInjectable": true                // the derived verdict (see below)
}
```

The `entitlements` object carries only the injection-relevant keys
([[domain.uitool.injection]]): `get-task-allow`, `com.apple.security.cs.debugger`,
`com.apple.security.cs.disable-library-validation`,
`com.apple.security.cs.allow-dyld-environment-variables`,
`com.apple.security.app-sandbox` — not the full plist.

### Verdict

`cooperativeInjectable` is **true** when the target accepts cooperative injection on
a stock Mac ([[domain.uitool.injection]] Posture 1): it carries `get-task-allow`,
**and** either the hardened runtime is off **or** it grants both the dyld-environment
and disable-library-validation overrides (so `DYLD_INSERT` and an unsigned-by-Apple
dylib are honored). A target without `get-task-allow` is `false` — it needs the
unrestricted posture (the defanged box).

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| read | 0 | the report on stdout |
| usage | 2 | structured error on stderr |
| target not found | 3 | structured error on stderr |

No `4`/`5`/`6`/`7` — `signing` opens no socket and injects nothing.

## Invariants

- **Static and read-only.** No injection, no attach, no mutation; reads the
  signature off disk / the running binary.
- **Deterministic.** Stable key order; the injection-relevant entitlement subset is
  fixed.
- **The verdict follows [[domain.uitool.injection]].** `cooperativeInjectable`
  encodes Posture 1's per-target preconditions, so it stays in step with the
  injection model.

## Notes

- **Cost tier: cheap.** One Security-framework read; no target code runs.
- Complements `doctor`: `doctor` reports the *machine* posture, `signing` the
  *target* posture. Together they answer "can I inspect this app from here?"
- For a running pid, the signature is read from the process's executable path; a
  freshly re-signed binary (e.g. `mise run uitool-sign`) reflects immediately.


## Source: `Features/uitool/0010-classes/commands/uitool.classes.md`

---
id: command.uitool.classes
kind: command
depends-on: [domain.runtime.reflection, domain.uitool.ipc, domain.uitool.selector, story.uitool.classes-browse]
---

# `uitool classes` — browse the target's loaded classes

## Synopsis

```
uitool classes <app> (--match <regex> | --class <name>) [--limit <n>] [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target, by pid or bundle id |
| `--match <regex>` | string | one of | **list mode** — class names matching the Swift-Regex pattern ([[domain.uitool.selector]]) |
| `--class <name>` | string | one of | **reflect mode** — the one class to reflect fully |
| `--limit <n>` | int | no | cap the list mode's returned names. Default 200 |
| `--pretty` / `--no-meta` | flag | no | pretty-print / strip session metadata |

Exactly one of `--match` / `--class` is required — a bare `classes` would dump every
loaded class, the unbounded read the surface forbids.

## Behavior

1. Resolve `<app>` to its live session ([[domain.uitool.ipc]]); no session is `NOT_ATTACHED` (exit 4).
2. **List mode** (`--match`): the server enumerates the target's loaded classes (`objc_copyClassList`), keeps the names matching the regex, sorts them, and returns up to `--limit` with a `truncated` flag.
3. **Reflect mode** (`--class`): the server resolves the name to a loaded class and reflects it via [[domain.runtime.reflection]] — superclass chain, ivars (name + type), properties, instance + class methods, protocols. A name that is not a loaded class returns `loaded: false` (exit 0 — a valid empty result, not an error).
4. Emit the result.

## Output

A single JSON object on stdout. Deterministic: sorted keys and names, no addresses,
no instance values.

**List mode:**

```jsonc
{ "match": "NSVisual", "count": 3, "truncated": false,
  "names": ["NSVisualEffectView", "NSVisualEffectViewBackdrop", "_NSVisualEffectViewBackdropLayer"] }
```

**Reflect mode:**

```jsonc
{
  "class": "NSVisualEffectView",
  "loaded": true,
  "superclasses": ["NSView", "NSResponder", "NSObject"],
  "ivars": [ { "name": "_material", "type": "q" } ],
  "properties": ["material", "state", "blendingMode"],
  "methods": ["material", "setMaterial:"],
  "classMethods": ["defaultAnimationForKey:"],
  "protocols": ["NSAccessibilityElement"]
}
```

Reflection is **declared** members only — what the class itself declares, not
inherited ([[domain.runtime.reflection]]); the inheritance is the `superclasses`
chain. No ivar/property *values* — those need an instance (`inspect`).

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| listed / reflected (incl. 0 matches or `loaded: false`) | 0 | the result on stdout |
| usage / neither flag / bad `--match` regex | 2 | structured error on stderr |
| not attached | 4 | structured error ([[domain.uitool.ipc]]) |
| timeout | 7 | structured error |
| schema mismatch | 8 | structured error |

A 0-match list and an unloaded `--class` are **exit 0** (valid empty results), never
errors — the agent reads `count` / `loaded`, not the exit code.

## Invariants

- **One mode required.** Exactly one of `--match` / `--class`; the list is never
  unbounded (capped by `--limit`, `truncated` when cut).
- **Reflection is metadata, no values, no target code.** Class reflection runs no
  getter and touches no instance ([[domain.runtime.reflection]]).
- **Deterministic.** Sorted names + keys; same target → byte-identical modulo session.

## Notes

- **Cost tier: bounded.** Enumeration is one `objc_copyClassList` walk on the target
  main thread; reflection is one class's metadata.
- Pairs with `inspect`: `classes --class` shows what a type *declares*; `inspect`
  shows what an *instance* currently holds.


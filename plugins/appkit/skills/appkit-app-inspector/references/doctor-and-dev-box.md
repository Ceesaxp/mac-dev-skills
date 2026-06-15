<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# uitool doctor and development postures

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.

## Source: `Specs/models/domain.uitool.injection.md`

---
id: domain.uitool.injection
kind: domain
depends-on: [domain.uitool.node-id, domain.uitool.ipc]
---

# Injection & Postures

The model for getting the `uitool` server into a target process, and what each path requires of the **machine** versus the **target**. Derived from HANDOFF §6 — the load-bearing risk of the whole project.

> **Scope note.** This is the **deferred injection half** of `uitool`. The `doctor` (precondition gate) and `attach` / `detach` (injection lifecycle) commands are absorbed as specs here, but their implementation lands after the cheap-read MVP (`windows` / `tree` / `find` / `node` on the pure `UIToolCore`). The spec is intact and the contract below is binding; only the injector and lifecycle implementation are deferred — including the `UIToolBoot` dylib both postures need, which is why both report as not-yet-usable today (see *Today's state*).

## The reframe (read this first)

macOS gates injection **per target**, and which gate applies depends on **who controls the target's code signing**. There is no single "is this machine ready to inject?" question — there are two, and the cheaper one is the common one.

- For an app **you build and sign** for development, the target itself opts in (a debug build carries `get-task-allow`). Injection into your own app works on a **stock, SIP-enabled Mac** — the same way lldb / Xcode / Reveal / InjectionIII attach to your own builds every day. No machine defanging.
- For an app **you did not sign** — Mail, Finder, a notarized third-party app — there is no per-app opt-in to flip, so the only path is to lower the system protections **machine-wide**. That is the defanged dev box.

The tool was previously documented as if **every** target were hostile and the full system defang were always required. That is the worst case, not the floor. The two postures below name the floor and the ceiling, and `doctor` reports **both** so an agent knows what it can attach to from here.

## Posture 1 — Cooperative (the default dev loop)

**Inspect apps you build and sign for development. SIP / AMFI / library-validation stay ON.**

- **Target.** An app the **user** builds and signs for development. A debug build is signed with `get-task-allow` (Xcode does this by default) — the entitlement by which the app **opts in** to being debugged / injected. Its hardened runtime is off, or it carries `com.apple.security.cs.allow-dyld-environment-variables` + `com.apple.security.cs.disable-library-validation`. The user controls all of this because it is their build.
- **Why it works with SIP enabled.** SIP's debugging restriction only protects **Apple-signed system / restricted** processes. A `get-task-allow` target is honored for task-port access and `dyld` insertion **regardless of SIP** — exactly how lldb / Xcode / Reveal / InjectionIII attach to your own apps on a stock Mac. Library validation and the hardened runtime are **per-process** flags the user sets in their own build, not machine-wide switches.
- **Mechanism (v1 = both cooperative paths).** Two ways in, both shipping in v1 for `get-task-allow` targets:
  - **launch** ([[command.uitool.launch]]) — spawn the target with `DYLD_INSERT_LIBRARIES=<…>/UIToolBoot.dylib` (`posix_spawn`) so the [[domain.uitool.boot]] dylib loads before `main` and starts the [[domain.uitool.server]] ([[domain.uitool.ipc]]). Robust across OS/app updates; **loses the target's current on-screen state** (it is a fresh launch).
  - **attach-to-running** ([[command.uitool.attach]]) — resolve a **running** `get-task-allow` target's task port (lldb-style `task_for_pid`, permitted for your own debuggable same-user process on a stock Mac) and remote-`dlopen` the boot dylib into it. **Preserves the target's live UI state** — the research default. Heavier than launch but a well-trodden technique for your own apps (lldb / Reveal / InjectionIII do it daily); the only genuinely hard, deferred route is the *unrestricted* running-attach into a target you did not sign (see *Attach mechanism*).
- **Machine requirements: NONE beyond the OS.** No `csrutil`, no `nvram boot-args`, no library-validation override, no reboot. You **do** need the **arm64** `UIToolBoot` dylib built: a normal Xcode app is arm64, so the injectable must match arm64. The `-arm64e_preview_abi` boot-arg is **not** involved here — it exists only for third-party arm64e code.
- **Per-target preconditions** (checked at attach / launch, **not** by the machine doctor): the target is debuggable (`get-task-allow`) and, for the launch path, permits dyld env vars; for the **attach-to-running** path the target must also be the **same user** (so `task_for_pid` is permitted without root) and `uitool` itself must be signed with the debugger entitlement (`com.apple.security.cs.debugger`) — the per-process lever that lets it acquire a `get-task-allow` target's task port, the same entitlement lldb carries. `doctor` cannot check the *target* preconditions — it has no target — so they live on `attach` / `launch`, not in the machine report; whether `doctor` surfaces the `uitool`-is-debugger-signed fact (a machine-stable property of the installed binary) is its own call, but it does not change the frozen `cooperative.requires` set below.

## Posture 2 — Unrestricted (arbitrary / system / notarized targets)

**Inspect any app, including system apps. Needs the full machine defang.**

- **Target.** Any app, **including ones the user did not sign** — Mail, Finder, a notarized third-party app. These ship with the hardened runtime + library validation and **no `get-task-allow`**, so there is **no per-app lever to flip**.
- **Why it needs the system-wide defang.** With no per-app opt-in, the only path is to lower the protections machine-wide: SIP disabled, `amfi_get_out_of_my_way=0x1`, library validation disabled, `-arm64e_preview_abi`, and the injectable built **arm64e** to match the system frameworks (the dyld shared cache is arm64e on Apple Silicon).
- **Machine requirements: the full defang stack** (the per-check interpreters below). A **dedicated dev box** that holds no real data; reversible from Recovery.

**The key reframe restated:** the defanged machine is required **only** for non-cooperative targets. For the user's own apps, `uitool` runs on a stock, SIP-enabled Mac.

## The doctor report shape

`doctor` is **pure local detection** — it runs before any injection, opens no IPC socket, contacts no target ([[domain.uitool.ipc]] describes the post-injection wire). It judges each machine-wide check **independently** (a half-configured machine yields an itemized verdict, never a single mystery failure) and groups the verdicts into the two postures, so the report answers "what can I attach to from here?" rather than one undifferentiated boolean.

```
DoctorReport
  cooperative : ModeReport   // inspect your own get-task-allow apps; SIP may stay on
  unrestricted: ModeReport   // inspect any app incl. system; needs the defang
  osBuild     : string?      // not a check; never affects usability

ModeReport
  usable  : bool             // every `requires` check is .ok
  requires: [PreconditionCheck]
  note    : string           // one line: what this posture is for
```

A `ModeReport.usable` is true only when **every** check in its `requires` array passed. `osBuild` is recorded but is **not a check** — precondition validity is OS-build-specific (arm64e injection regresses across Tahoe 26.x), so the build is reported for context but never affects either posture's usability, and it is machine-specific so it is normalized out of snapshot assertions like a session id.

### `cooperative.requires`

| Check | Source | Pass condition | `detail` |
| --- | --- | --- | --- |
| `arch` | `uname -m` | Apple Silicon host (`arm64` / `arm64e`) | the reported arch |
| `injectable-arm64` | filesystem | the **arm64** `UIToolBoot` dylib is present | `present` / `absent` |

> **note** ≈ *"Inspect apps you build and sign for development (get-task-allow). No SIP / AMFI / library-validation changes — your machine is already capable."*

This posture deliberately lists **no** SIP / AMFI / libval / arm64e-ABI check: none of them gate injection into a `get-task-allow` target. The only machine facts that matter are *is this an Apple Silicon host* and *is the arm64 injectable built*.

### `unrestricted.requires`

| Check | Source | Pass condition | `detail` (pass / fail) |
| --- | --- | --- | --- |
| `sip` | `csrutil status` | disabled (Permissive Security) | `disabled` / `enabled` |
| `amfi` | `nvram boot-args` | contains `amfi_get_out_of_my_way=0x1` — **the real gate** | `disabled` / `enforcing` |
| `libval` | LV plist | `DisableLibraryValidation` = true | `disabled` / `enabled` |
| `arm64e-abi` | `nvram boot-args` | contains `-arm64e_preview_abi` | `present` / `absent` |
| `arch` | `uname -m` | Apple Silicon host | the reported arch |
| `injectable-arm64e` | filesystem | the **arm64e** `UIToolBoot` dylib is present | `present` / `absent` |

> **note** ≈ *"Additionally required only to inspect apps you did NOT sign (system / notarized). Dedicated dev box; reversible from Recovery."*

These are exactly the existing per-check interpreters (`sip` / `amfi` / `libval` / `arm64e-abi` / `arch`) — their **frozen `detail` tokens and one-line remedies are unchanged**. What changed is the **grouping** (they now live under `unrestricted`, not in one flat array) and the **injectable split**: the single `uitool-built` check becomes two arch-specific checks, `injectable-arm64` (cooperative) and `injectable-arm64e` (unrestricted), because the cooperative path matches a plain-arm64 app and the unrestricted path matches the arm64e shared cache. A plain-arm64 dylib fails `dyld` **silently** against an arm64e target, and vice versa — so each posture must verify the slice it will actually load.

### Exit code

- **Exit 0** when `cooperative.usable` — the common case is reachable.
- **Exit 6** (`PRECONDITION_FAILED`, [[domain.uitool.ipc]]) otherwise.

**Rationale.** Cooperative is the common case, so its readiness drives the exit code; `unrestricted` being unusable on a stock Mac is the *expected* state, not a failure, and never forces a non-zero exit on its own. The structured error on stderr carries `PRECONDITION_FAILED` ([[error.uitool.doctor-precondition-failed]]).

## Today's state

The injection half (`UIToolBoot` / `UIToolServer`) is **not built yet**, so both `injectable-arm64` and `injectable-arm64e` are honestly **absent** and **neither posture is usable today**. `doctor` therefore exits **6** right now — but the report makes the gap legible: cooperative is blocked **only** by the deferred dylib (`injectable-arm64` absent), **not** by any missing machine defang. An agent reading the report sees that the cooperative path needs no `csrutil` / `nvram` / reboot — just the (deferred) arm64 dylib — and that nothing about this machine has to be weakened to inspect the user's own apps.

This is the load-bearing honesty of the new shape: the floor is "build the arm64 dylib", not "defang your Mac".

## Attach mechanism

| Path | Posture | v1? | Mechanism | Trade-off |
| --- | --- | --- | --- | --- |
| **launch** | cooperative (and unrestricted-relaunch) | **v1** | spawn the target under `DYLD_INSERT_LIBRARIES=…/UIToolBoot.dylib` (`posix_spawn`) | simplest, robust across OS/app updates; **loses current UI state** |
| **task-port attach** | cooperative | **v1** | resolve a **running** `get-task-allow` target's task port (lldb-style `task_for_pid`, same-user, `uitool` debugger-entitled) and remote-`dlopen` the dylib | **preserves live state** — the research default; heavier than launch but a known technique for your own apps |
| **first-party running-attach** | unrestricted | deferred | MIP-style `launchservicesd`-checkin hook + Mach thread-hijack (PAC-signed bootstrap; processor-set task-port route) | preserves live state; brittle, version-fragile, **the hard sub-project** |

Both **cooperative** paths — launch and task-port attach-to-running — ship in v1. Develop the walker / query layers against a self-built non-hardened harness (`SampleAppKit`) via the **launch path** first (zero task-port complexity, fastest loop), then bring up cooperative task-port attach against the same harness so the live-state default works on a stock Mac. The genuinely deferred route is the **unrestricted** running-attach — injecting into a target you did **not** sign (a system / notarized app) via the `launchservicesd` hook — which remains the hard sub-project (HANDOFF M5). The distinction that moved attach-to-running into v1: for **your own** `get-task-allow` app, `task_for_pid` + remote `dlopen` is the everyday lldb path and needs no machine defang; only a target with no per-app opt-in forces the brittle hook.

## Lifecycle

- `attach` → resolve the target → gate on the posture's preconditions → inject → poll (bounded) for the socket → bump the session epoch ([[domain.uitool.node-id]]).
- `detach` → close socket, drop registry.
- Idempotent: a second `attach` on an already-injected target reuses the existing server.
- A post-attach verb that finds no live session surfaces `NOT_ATTACHED` (exit 4) per [[domain.uitool.ipc]] — it never silently re-attaches.

## Invariants

- `doctor` / `sip-preflight` gate **every** injection path; on a failed precondition for the posture being used, exit 6 — never silently proceed. `doctor` never mutates boot security implicitly — remediation requires the explicit `--fix` flag, and `--fix` only touches the **unrestricted** stack (the cooperative posture has nothing to remediate).
- **Cooperative needs no machine defang** — but it is not "no requirements": it still needs a `get-task-allow` target (per-target, checked at attach) and the **arm64** `UIToolBoot` dylib (machine, checked by `doctor`). Do not overclaim it as free; do not under-claim it as needing SIP off.
- **Unrestricted needs the full defang** — SIP off, AMFI boot-arg, libval off, arm64e ABI boot-arg, and an **arm64e** injectable. It is required **only** for targets the user did not sign.
- Each precondition is judged independently; no check is skipped because another failed.
- v1 is read-only — no write/mutation ops.
- **Signed-artifact containment holds for BOTH postures.** The signed `UIToolBoot` dylib (and any framework / CLI) is **gitignored and never distributed** — dev box only; it is an attack tool on any other machine ([[architecture]] → "Dual-use & safety posture"). Cooperative being a stock-Mac posture does **not** relax this — the injectable is still a signed code-loading primitive that must not leave the dev box.

## Relationships

- [[domain.uitool.boot]] — the dylib both postures load into the target; the foothold whose constructor starts the server. Its `injectable-arm64` / `injectable-arm64e` presence is what `doctor` checks.
- [[domain.uitool.server]] — the in-target unit the boot dylib starts; the thing on the far end of the socket.
- [[domain.uitool.ipc]] — the wire the server speaks, and the `NOT_ATTACHED` error a failed / absent session surfaces.
- [[domain.uitool.node-id]] — the session epoch bumped on `attach` / `launch`.
- Consumed by the `doctor`, `list-apps`, [[command.uitool.launch]], [[command.uitool.attach]], `detach` commands.

## Notes

- `-arm64e_preview_abi` is a single point of failure for the **unrestricted** posture only — perpetually "preview", removable by Apple in any point release. The cooperative posture does not depend on it. Track Apple's dyld / AMFI hardening as an existential dependency of the unrestricted path.
- arm64e injection is actively regressing on Tahoe 26 — pin one 26.x build on the dev box for the unrestricted posture; keep the AX fallback wired. The cooperative posture (plain-arm64 into a `get-task-allow` app) is unaffected by the arm64e regression.
- **The launch path is the v1 bring-up order, not the v1 ceiling.** Oracle development (M0–M4) starts on the launch path against `SampleAppKit` — zero task-port complexity, fastest loop — and cooperative **task-port attach-to-running** follows in the same v1, so the live-state research default ("inspect this app as it sits right now") works on a stock Mac for your own apps. What stays **deferred** is preserving live state for a target you did **not** sign: the *unrestricted* running-attach via the `launchservicesd` hook (HANDOFF M5). Live-state inspection is v1 for cooperative targets and deferred only for non-cooperative ones.
- **`doctor` detects and instructs by default; `doctor --fix` opts into auto-remediation** of the **unrestricted** stack only — running the `nvram boot-args` / `DisableLibraryValidation` `defaults write` commands with sudo. `--fix` echoes each command before running it, never runs implicitly, and cannot complete steps requiring Recovery (SIP via `csrutil`) or a reboot — it sets what it can, then prints exactly which manual steps + reboot remain. There is nothing to `--fix` for the cooperative posture: its only deferred blocker is building the arm64 dylib.


## Source: `Specs/models/domain.uitool.boot.md`

---
id: domain.uitool.boot
kind: domain
depends-on: [domain.uitool.injection, domain.uitool.ipc, domain.uitool.server]
---

# Domain: the boot dylib (`UIToolBoot`)

The smallest possible piece of `uitool` that runs inside the target. Its entire
job is to **come up cleanly when loaded and start [[domain.uitool.server]]** — it
is the foothold, not the tool. [[domain.uitool.injection]] pins *how it gets in*
(the postures and mechanisms); this model pins what it *does once there* and the
discipline that keeps it from harming the host or escaping the dev box.

> **Scope note.** This is the **deferred injection half** of `uitool`. The
> cooperative postures both depend on this dylib existing — it is why `doctor`
> reports `injectable-arm64` (and `injectable-arm64e`) as *absent* today
> ([[domain.uitool.injection]] → "Today's state"). Building it is the load-bearing
> floor: "build the arm64 dylib", not "defang your Mac."

## What it is

A standalone dynamic library with a **constructor** and nothing resembling a UI.
It is loaded into the target one of two ways ([[domain.uitool.injection]] attach
mechanism):

- **at launch** — the target is spawned with `DYLD_INSERT_LIBRARIES=…/UIToolBoot.dylib`,
  so dyld loads it before `main` (the `launch` command, [[command.uitool.launch]]);
- **into a running process** — a remote `dlopen` of this dylib in an
  already-running, debuggable target (the `attach` command, [[command.uitool.attach]]).

Either way, **the constructor is the only entry point.** Once it has started the
server, the dylib is inert — it holds the server alive and does nothing else.

## The constructor contract

```c
// SPEC: domain.uitool.boot
__attribute__((constructor)) static void uitool_boot(void) { /* … */ }
```

On load, the constructor must, in order:

1. **Derive the socket path** from the live pid — `/tmp/uitool-<getpid()>.sock`
   ([[domain.uitool.ipc]] transport). The path is computed in-process, never
   passed in, so a stale env var can never point it at the wrong socket.
2. **Start [[domain.uitool.server]]** on a dedicated background thread, which
   binds the socket `chmod 0600` and begins accepting. The server start is what
   creates the socket the CLI polls for at attach/launch
   ([[command.uitool.attach]] step "poll for the socket").
3. **Return immediately.** The constructor must not block — it spawns the server
   thread and returns so the target's own launch (or running run loop) is never
   stalled. No AppKit call, no main-thread work, no I/O beyond binding the socket
   happens on the loading thread.

A constructor that throws, blocks, or touches the main thread is a defect: it
either deadlocks the host or silently fails to load, which surfaces to the agent
as `INJECTION_FAILED` (exit 4) — "the socket never appeared"
([[error.uitool.attach-injection-failed]]). The whole point of the bounded poll
at attach is to turn a silent dylib-load failure into a clean exit 4.

## Two architecture slices

dyld silently refuses a slice that does not match the target's
([[domain.uitool.injection]] — "A plain-arm64 dylib fails `dyld` **silently**
against an arm64e target, and vice versa"). So the dylib ships in two builds, each
gating a different posture:

| Build | Posture | Matches | `doctor` check |
| --- | --- | --- | --- |
| **arm64** | cooperative | a normal Xcode app you build and sign (`get-task-allow`) | `injectable-arm64` |
| **arm64e** | unrestricted | the arm64e dyld shared cache (system / notarized targets) | `injectable-arm64e` |

The v1 cooperative MVP needs only the **arm64** build. The arm64e build is built
the same way with `-arm64e_preview_abi`; it is required only for the unrestricted
posture and inherits that posture's deferral ([[domain.uitool.injection]]).

## Teardown

On `detach`, `dlclose`, or app quit, the dylib stops the server, which closes and
**unlinks** the socket and drops the registry ([[domain.uitool.server]] lifecycle;
[[domain.uitool.ipc]] threading — "on dylib unload: close socket, unlink path,
drop the registry"). A leftover socket from a half-open or crashed session is not
a healthy server to reuse; the next attach treats it as a fresh attach
([[command.uitool.attach]] idempotency invariant).

## Invariants

- **Constructor only; non-blocking; off the main thread.** The dylib does its
  whole job at load time by starting the server thread and returning. It never
  blocks the loader and never touches AppKit on the loading thread.
- **The socket path is derived in-process from the pid.** Never trusted from the
  environment — a stale path is how an agent silently talks to the wrong process.
- **Arch must match the target.** Ship arm64 for cooperative, arm64e for
  unrestricted; a mismatch is a silent dyld no-load, caught only by the bounded
  attach poll as exit 4.
- **Containment is absolute and is the reason this dylib is dangerous.** The
  signed `UIToolBoot.dylib` (either slice) is `.gitignore`d, **never committed**,
  **never** added to a shippable target or a release CI job
  ([[domain.uitool.injection]] containment; [[architecture]] → "Dual-use & safety
  posture"). It is a signed code-loading primitive: on any machine but the dev box
  it is an attack tool. The cooperative posture running on a stock Mac does **not**
  relax this — a stock-Mac-capable injectable is, if anything, more dangerous to
  leak, not less.
- **No behavior beyond hosting the server.** Any reflection, walking, or IPC logic
  belongs in [[domain.uitool.server]] / `RuntimeKit`, not here. The dylib is the
  foothold; the moment it grows logic, it has stopped being auditable-at-a-glance.

## Relationships

- [[domain.uitool.injection]] — the postures and the two load mechanisms (launch
  `DYLD_INSERT`, running-process remote `dlopen`); the containment invariant.
- [[domain.uitool.server]] — the unit the constructor starts and holds alive.
- [[domain.uitool.ipc]] — the socket path it derives and the server binds.
- [[command.uitool.launch]] / [[command.uitool.attach]] — the CLI commands that
  cause this dylib to load.

## Notes

- **Why a separate dylib at all, rather than building the server into one image.**
  The boot/server split keeps the foothold (the thing that must load cleanly into
  a foreign process and is auditable in a screenful of C) separate from the server
  (the thing with the walker bridge and the socket protocol). The dylib is what
  dyld and the remote-`dlopen` care about; the server is plain Swift/ObjC behind
  it. The split also lets the arm64/arm64e concern live entirely in how this one
  small image is built.
- **Build, signing, and the `-arm64e_preview_abi` flag are build-script concerns,
  never baked into a product** ([[architecture]] §4.1). This model pins the
  *contract* (constructor behavior, arch match, containment); the codesigning and
  boot-arg mechanics live in the build scripts and `doctor`, not in the manifest.


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


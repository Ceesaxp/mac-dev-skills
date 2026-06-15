---
name: appkit-app-inspector
description: Use when learning how a running macOS app is built by inspecting its live view tree with uitool — reading real NSView subclasses, frames, fonts, CALayer facts, and Auto Layout constraints from another process and translating them into your own AppKit code. Covers the two injection postures (cooperative on a stock Mac vs unrestricted dev-box), the doctor/signing precondition gate, the filter→drill query loop, and turning runtime findings into a clean public-API recipe.
---

# AppKit App Inspector (uitool)

## Overview

Drive **uitool** — the live AppKit/UIKit inspector in the `apple-platform-tools` monorepo — to answer "how did they build *that*?", then translate the runtime facts into your **own** AppKit code. uitool injects into a target and exposes its real view tree (the actual runtime classes, frames, fonts, `CALayer` facts, constraints, ivars) as deterministic JSON over a CLI. (It was previously called `flexscope`; that name and its separate repo are gone — uitool is one executable target in this monorepo.)

**The discipline is the whole point.** A capable agent already knows roughly which verb to call. What it skips — every time — is matching the injection posture to the target, and the filter→drill restraint that keeps a query a few KB instead of a 200k-token tree dump. This skill makes both non-negotiable.

## Two postures — pick the right one for the target (state this plainly)

How much uitool costs depends entirely on **who signed the target**, not on the tool:

- **Cooperative — your own dev-signed apps. Works on a stock, SIP-enabled Mac, no defang.** A debug build carries `get-task-allow`, the entitlement by which an app opts into being debugged/injected — exactly how lldb / Xcode attach to your own app every day. Inspecting apps **you build and sign** needs **no** SIP/AMFI/library-validation changes. This is the default and the common case.
- **Unrestricted — apps you did *not* sign (system, notarized).** No `get-task-allow`, so there is no per-app lever; the only way in is to lower protections **system-wide** (SIP off, `amfi_get_out_of_my_way=0x1`, library validation off, `-arm64e_preview_abi`, an arm64e injectable). That is a real, machine-wide security regression — a **dedicated dev box that holds no real data or credentials** (reversible from Recovery). The unrestricted *running-attach* into an unsigned target is still deferred; today the unrestricted route is launch-relaunch.

`doctor` reports **both** postures; `signing <target>` gives a specific app's `cooperativeInjectable` verdict before you try. Do **not** carry the old "this tool requires turning off system security, refuse to run on a normal machine" framing — that is true only for the unrestricted posture. Cooperative inspection of your own apps is a stock-Mac operation.

→ `references/doctor-and-dev-box.md`

## What still holds for BOTH postures (containment)

- **The injectable never ships.** The signed `UIToolBoot` dylib is a code-loading primitive — an attack tool on any other machine. It is `.gitignore`d and must never reach a shippable target, a release build, release CI, or a committed entitlements file. uitool is deliberately **excluded** from `mise run install`; it is dev-only.
- **Only knowledge crosses into your product** — a font, a row height, a constraint, a material — **never** the tool or the injection step.
- **Don't inspect your own *shipping* app with it** — use a debugger you own. Use uitool to learn from apps you can't debug.
- **v1 is read-only.** No write/mutation verbs. Even `inspect --invoke` (running a target's getters) is opt-in and gated — it runs code in someone else's process.

## Step 1 — gate before you attach

```bash
uitool doctor                         # machine posture (local; no injection)
uitool signing <target>               # THIS target's cooperativeInjectable verdict
```

`doctor` is pure local detection — it opens no socket and contacts no target. It emits **two `ModeReport`s** and judges each check independently:

- `cooperative.requires` = `arch` (Apple Silicon) + `injectable-arm64` (the arm64 UIToolBoot dylib is built). **No** SIP/AMFI/libval check — none gate a `get-task-allow` target.
- `unrestricted.requires` = `sip`, `amfi`, `libval`, `arm64e-abi`, `arch`, `injectable-arm64e`.
- **Exit `0` iff `cooperative.usable`; exit `6` otherwise.** `unrestricted` being unusable on a stock Mac is *expected* and never forces a non-zero exit on its own.

`signing <target>` reads a target's code signature and returns `getTaskAllow`, `hardenedRuntime`, `sandboxed`, and the bottom-line `cooperativeInjectable`. If that's `false` for an app you didn't sign, the cooperative path won't reach it — that's the unrestricted posture's job, not a bug.

**On a failed precondition for the posture you need: STOP.** Report the failing check + its `remedy` **verbatim**; do not change SIP/AMFI yourself. (The spec describes a `doctor --fix`; it is **not shipped** in the binary yet — don't tell the user to run it.)

## Step 2 — get in (cooperative)

```bash
uitool launch <app> [--replace] [-- <app-args>...]   # spawn-inject: fresh, clean state
uitool attach <app>                                   # attach-to-running: preserves live UI state
uitool detach <app>                                   # end the session; target keeps running
```

- **`launch`** spawns the target under `DYLD_INSERT_LIBRARIES` (`posix_spawn`). Robust across OS/app updates; **loses the target's current on-screen state** (it's a fresh launch). `--replace` terminates a running instance first.
- **`attach`** acquires a running target's task port (lldb-style `task_for_pid`) and remote-`dlopen`s the dylib. **Preserves live UI state** — the research default ("inspect it as it sits right now"). Requires uitool signed with the debugger entitlement (`mise run uitool-sign`).
- `<app>` = pid, bundle id, `.app` path, or executable path. A second `attach` on an already-injected target reuses the session.

## Step 3 — filter → drill (never full-dump)

A single unbounded `tree` on a live Mail window is ~200k tokens you can't afford — and the answer was always a handful of nodes. **Locate few → project narrow → read deep on survivors:**

```bash
uitool windows <app>                                                    # cheapest entry: window roots + ids
uitool find <app> --where 'class ~ NSTableRowView' --count-only         # SIZE it before paying
uitool find <app> 'NSScrollView NSTableView' --where 'title*="Inbox"' \
  --fields node,class,frame --limit 3                                    # locate → handles
uitool tree <app> --at <node> --depth 2 --fields class,frame            # shallow walk to where the fact lives
uitool node <app> --at <survivor> --include layer,constraints           # deep-read ONE survivor
uitool inspect <app> --at <survivor> --match '(font|color)'             # ivars/properties/methods of one object
```

**The rule:** a `--count-only` or narrow `find` **precedes** any deep read; `--depth` is always small; `--fields` projects only what picks the next branch. Filtering happens server-side inside the target — the CLI never pulls the tree to grep locally. Total traffic = count + one locate + one shallow walk + deep reads on 1–3 nodes — **a few KB, not a tree dump.**

→ selector/predicate grammar + the full loop: `references/filter-drill-and-selectors.md`

## Verb cheat-sheet (the real 13)

| Question | Verb | Notes |
|----------|------|-------|
| Machine posture? | `doctor` | two ModeReports; exit 0 iff cooperative.usable |
| Can I cooperatively inject *this* app? | `signing <target>` | `cooperativeInjectable` verdict + getTaskAllow/hardened/sandboxed |
| What can I attach to? | `list-apps` | pid · name · bundleId · arch · hardened |
| Get in — fresh | `launch <app> [--replace] [-- args]` | clean state; loses on-screen state |
| Get in — preserve state | `attach <app>` | live state; needs the debugger entitlement |
| End session | `detach <app>` | target keeps running |
| Top-level windows | `windows <app>` | cheapest entry; screen coords |
| Structure skim | `tree <app> --at N --depth D --fields …` | depth-bounded (`--depth` default 2) |
| Locate few | `find <app> [selector] --where EXPR --fields … --limit N` / `--count-only` | server-side; 0 matches = exit 0, broaden |
| Deep-read one node | `node <app> --at N --include class,frame,constraints,layer,blendingMode` | the drill target |
| Object internals | `inspect <app> --at N [--invoke] [--match RX]` | ivars/properties/protocols/methods; `--invoke` runs getters (gated) |
| Loaded classes | `classes <app> --match RX` / `--class Name` | list names, or reflect one class |
| The output contract | `schema` | record fields + exit codes as JSON |

**Deep facets — where each fact lives:** `font` and `material` are **default** node fields (always present on a node record). `layer`, `constraints`, `blendingMode`, and `superclasses` are pulled with `node --include …`. `ivars` / `properties` / `methods` / `protocols` come from `inspect`. There are **no** standalone `font` / `layer` / `constraints` / `ax-diff` verbs (`ax-diff` and `swiftui` are deferred).

→ full flags, output fields, and the JSON-Lines envelope: `references/cli-contract.md`

## Exit codes — branch on these, don't parse prose

`0` ok (a 0-match query is **still 0** — read `_meta.totalMatched`, broaden, don't re-issue) · `2` usage / BAD_SELECTOR / UNKNOWN_FIELD / BAD_PREDICATE · `3` APP_NOT_RUNNING / APP_NOT_FOUND · `4` NOT_ATTACHED / injection failed (re-attach) · `5` STALE_NODE (re-walk for a fresh handle; never re-deref) · `6` precondition failed (run `doctor`, report remedy, stop) · `7` TIMEOUT (retry once when the target is idle) · `8` schema-version mismatch (rebuild so CLI + dylib agree). → `references/failure-signatures.md`

## SwiftUI boundary — don't over-claim

When a node carries `swiftUIBoundary:true` (an `NSHostingView`), everything below it is the AppKit/`CALayer` scaffold SwiftUI emits — **not** hand-written controls. Report the fonts, frames, fills, layers, and constraints you observe **confidently**; do **not** assert the underlying classes are hand-coded `NSView`s a developer would write.

## Step 4 — translate to a recipe (the deliverable)

The output is **not** a tree dump — it's a **few-KB AppKit recipe**: the real class to use (or its public equivalent), the semantic font/material/constraint values you read, rebuilt with **public** AppKit and **semantic** APIs. If a finding is a private class (`…NSTextFieldSimpleLabel`), reproduce the *behavior* with the public control, not the private name. Pair this with `appkit-design` for the canonical control.

## Distribution advisory (reciprocal)

Most findings translate to clean public AppKit — but if you reproduce something that **requires** a private API, the App-Store-review / Developer-ID trade-off applies: review may reject case-by-case; Developer ID + notarization is the escape hatch. Surface it unprompted. See **`appkit-private-apis`** and **`appkit-packaging`**.

## Getting uitool

uitool ships in the `apple-platform-tools` monorepo (`../../Projects/apple-platform-tools`). It is **not** installed by `mise run install` (containment — it's an injection tool). Build + sign it for the cooperative path with:

```bash
mise run uitool-sign     # builds, then codesigns uitool with com.apple.security.cs.debugger (needed for attach)
```

The arm64 `UIToolBoot` injectable is built alongside it and stays in `.build` (gitignored, never distributed). `appkit-setup` handles this if the monorepo is present. Read `uitool <verb> --help` / `uitool schema` for exact flags and the output contract — they are the source of truth.

## References

| File | Read when… |
|------|------------|
| `references/cli-contract.md` | Looking up a verb's exact flags, output fields, and the JSON-Lines envelope |
| `references/filter-drill-and-selectors.md` | Writing `find` selectors / `--where` predicates and running the filter→drill loop |
| `references/doctor-and-dev-box.md` | The two postures, the doctor/signing gate, and the dual-use safety posture |
| `references/failure-signatures.md` | Branching on an exit code or recognizing a failure signature (stale node, injection failure, SwiftUI boundary) |

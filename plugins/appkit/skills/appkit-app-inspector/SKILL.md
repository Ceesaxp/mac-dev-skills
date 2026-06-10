---
name: appkit-app-inspector
description: Use when learning how a running macOS app is built by inspecting its live view tree with flexscope — reading real NSView subclasses, frames, fonts, CALayer facts, and Auto Layout constraints from another process and translating them into your own AppKit code. Covers the doctor precondition gate, the filter→drill query loop, the dual-use/dev-box safety posture, and turning runtime findings into a clean public-API recipe.
---

# AppKit App Inspector (flexscope)

## Overview

Drive **flexscope** — a macOS runtime inspector that injects into a running app and exposes its real view tree (class names, frames, fonts, `CALayer` facts, constraints) over a CLI — to answer "how did they build *that*?", then translate the runtime facts into your **own** AppKit code. flexscope is the user's separate repo (not vendored here); this skill targets its **frozen CLI contract**.

**The discipline is the whole point.** A capable agent already knows roughly which verb to call. What it skips — every time — is the dev-box safety framing and the filter→drill restraint. This skill makes both non-negotiable.

## Dev-box reality — state this plainly, unprompted

flexscope works by **injecting code into another process**, which requires turning off system security. Say this up front, every session:

- **A dedicated dev box only.** SIP **+** AMFI **+** library-validation off is a real, **system-wide** security regression — *any* process can load code into any other. The machine must hold **no real data or credentials**. (Reversible from Recovery.) Refuse to run on a normal machine.
- **The tool never ships.** The injected dylib / FLEX-mac framework / `flexscope` CLI only work on a defanged box and are an attack tool elsewhere. They must **never** reach a shippable target, a release build, or a committed entitlements file.
- **Only knowledge crosses into your product** — a font, a row height, a constraint, a material — **never the tool or the injection step.**
- **Don't inspect your own shipping app with it** — use a debugger you own. Use flexscope to learn from apps you *can't* debug.

→ `references/doctor-and-dev-box.md`

## Step 1 — `doctor` gate (always first)

```bash
flexscope doctor
```

Runs locally, no injection. Six checks, fixed order: **`sip`, `amfi`, `libval`, `arm64e-abi`, `arch`, `flexmac-built`** — *all six* must pass (`ok:true`, exit `0`). Any failure → exit `6` with a per-check `remedy`.

**On non-green: STOP.** Report exactly which check failed and its `remedy` **verbatim**; do **not** proceed to attach; do **not** change SIP/AMFI yourself (remediation is the explicit `--fix` flag's job, and even then a reboot-pending state stays exit `6`). SIP-off alone is necessary but **not** sufficient — AMFI (`amfi_get_out_of_my_way=0x1`) is the real gate, and a plain-arm64 dylib fails dyld **silently**.

## Step 2 — Filter → drill (never full-dump)

A single unbounded `tree` on a live Mail window is ~200k tokens you can't afford — and the answer was always a handful of nodes. **Locate few → project narrow → read deep on survivors:**

```bash
flexscope attach com.apple.mail                                  # pid or bundle id
flexscope windows com.apple.mail                                 # cheapest entry: window roots
flexscope find com.apple.mail --where 'class ~ NSTableRowView' --count-only      # size it BEFORE paying
flexscope find com.apple.mail --where 'title*="Inbox"' --fields node,class,frame --limit 3   # locate → handles
flexscope tree com.apple.mail --at <node> --depth 2 --fields class,frame         # shallow walk to where the fact lives
flexscope font com.apple.mail --at <survivor>                    # deep-read ONE survivor
flexscope layer com.apple.mail --at <survivor>                   # where "the look" lives (cornerRadius, backgroundFilters, shadow)
flexscope constraints com.apple.mail --at <survivor>             # Auto Layout, both directions + intrinsic size
```

**The rule:** a count-only or narrow `find` **precedes** any deep read; `--depth` is always small; `--fields` projects only what picks the next branch. Total traffic = count + one locate + one shallow walk + deep reads on 1–3 nodes — **a few KB, not a tree dump.** Filtering happens server-side inside the target; the CLI never pulls the tree to grep locally.

→ selector/predicate grammar + the full loop: `references/filter-drill-and-selectors.md`

## Verb cheat-sheet

| Question | Verb | Notes |
|----------|------|-------|
| Preconditions OK? | `doctor` | gate; all-6-green or stop |
| What can I attach to? | `list-apps [--match …]` | pid · name · bundleId |
| Open/close a session | `attach <app>` / `detach <app>` | `<app>` = pid or bundle id |
| Top-level windows | `windows <app>` | cheapest entry; screen coords |
| Structure skim | `tree --at N --depth D --fields …` | depth-bounded; descend only `truncated` branches |
| Locate few | `find --where EXPR --fields … --limit N` / `--count-only` | server-side; 0 matches = exit 0, broaden |
| Deep-read one node | `node --at N --include class,frame,font,constraints,layer,ivars` | the drill target |
| Typography | `font --at N` / `fonts [--at N]` | `fonts` = de-duped subtree inventory |
| The look | `layer --at N` | cornerRadius, backgroundFilters, shadow (CALayer facts only) |
| Vibrancy material | `node --at N` | `material` / `blendingMode` are **node** fields (NSVisualEffectView), not `layer` output |
| Auto Layout | `constraints --at N` | both directions + hugging/compression + intrinsic |
| Prove it beats AX | `ax-diff --at N` | side-by-side AX vs FLEX |

→ full flags, output fields, and the JSON-Lines envelope: `references/cli-contract.md`

## Exit codes — branch on these, don't parse prose

`0` ok (a 0-match query is **still 0** — read `_meta.totalMatched`, broaden, don't re-issue) · `2` usage/bad selector (fix the query) · `3` app not running (attach-time; launch + retry) · `4` not attached / injection failed (re-attach; injection-failed → read message: arch vs AMFI/LV) · `5` stale node (re-walk with `find`/`tree` for a fresh handle; never re-deref) · `6` precondition (report remedy, stop) · `7` timeout (retry once) · `8` schema mismatch (rebuild so CLI+dylib agree). → `references/failure-signatures.md`

## SwiftUI boundary — don't over-claim

When a node carries `swiftUIBoundary:true`, everything below it is the AppKit/`CALayer` scaffold SwiftUI emits — **not** hand-written controls. Report the fonts, frames, fills, layers, and constraints you observe **confidently**; do **not** assert the underlying classes are hand-coded `NSView`s a developer would write.

## Step 3 — Translate to a recipe (the deliverable)

The output is **not** a tree dump — it's a **few-KB AppKit recipe**: the real class to use (or its public equivalent), the semantic font/material/constraint values you read, rebuilt with **public** AppKit and **semantic** APIs. If a finding is a private class (`…NSTextFieldSimpleLabel`), reproduce the *behavior* with the public control, not the private name. Pair this with `appkit-design` for the canonical control.

## Distribution advisory (reciprocal)

Most findings translate to clean public AppKit — but if you reproduce something that **requires** a private API, the App-Store-review / Developer-ID trade-off applies: review may reject case-by-case; Developer ID + notarization is the escape hatch. Surface it unprompted. See **`appkit-private-apis`** and **`appkit-packaging`**.

## Getting flexscope

flexscope is a separate repo, spec-complete and built with SwiftPM (`swift build -c release`), then code-signed for injection on the dev box (`scripts/sign.sh`). `appkit-setup` builds it only if present at its path; otherwise clone/build it per its own README and run `flexscope doctor` to confirm the box is ready. The CLI contract this skill targets is frozen; some flag *defaults* are still unspecified — don't invent them, read `--help` / the schema.

## References

| File | Read when… |
|------|------------|
| `references/cli-contract.md` | Looking up a verb's exact flags, output fields, and the JSON-Lines envelope |
| `references/filter-drill-and-selectors.md` | Writing `find --where` selectors and running the filter→drill loop |
| `references/doctor-and-dev-box.md` | The 6 doctor checks, remediation, and the dual-use safety posture |
| `references/failure-signatures.md` | Branching on an exit code or recognizing a failure signature (stale node, arm64e mismatch, SwiftUI boundary) |

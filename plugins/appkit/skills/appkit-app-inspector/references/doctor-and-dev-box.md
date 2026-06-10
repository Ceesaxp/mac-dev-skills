# Doctor gate & dual-use safety

> The 6 frozen `doctor` checks + their remedies, and the non-negotiable dev-box-only posture. `doctor` runs locally, opens no socket, hits no target.

## 1. The 6 checks (frozen, fixed order)

`flexscope doctor` evaluates the machine-wide precondition stack — every check **except** `target running` (that one needs a named target `doctor` doesn't take; it's evaluated only by `attach`). The `check` ids and `detail` tokens are a **byte-stable snapshot contract**: fixed order, fixed token per state, never free prose.

| # | `check` | source | `detail` pass | `detail` fail | notes |
|---|---------|--------|---------------|---------------|-------|
| 1 | `sip` | `csrutil status` | `disabled` | `enabled` | Permissive Security on Apple Silicon. Necessary, **not sufficient** alone. |
| 2 | `amfi` | `nvram boot-args` | `disabled` | `enforcing` | **The real gate** — `amfi_get_out_of_my_way=0x1`. |
| 3 | `libval` | LV plist (`DisableLibraryValidation`) | `disabled` | `enabled` | |
| 4 | `arm64e-abi` | `nvram boot-args` | `present` | `absent` | `-arm64e_preview_abi`. Perpetually "preview" — Apple can remove it in any point release. |
| 5 | `arch` | `file`/`lipo` on the dylib | `arm64e` | `arm64` \| `x86_64` (the built arch) | A plain-**arm64** dylib **fails dyld silently** — looks built, never loads. |
| 6 | `flexmac-built` | filesystem stat | `present` | `absent` | `FLEXMac.framework` built? |

**The aggregate:** `ok` is true only when **all six** pass.

| Result | Exit | Output |
|--------|------|--------|
| all 6 green | `0` | verdict object on stdout |
| any check fails | `6` | verdict object **with per-check `remedy`** + one-line structured error on stderr |

❌ Don't branch on `ok` by parsing stdout prose, or treat SIP-off as enough.
✅ Do branch on the **exit code** (`0` vs `6`), then read the failing check's `remedy` from JSON.

> **AMFI is the load-bearing link.** SIP, LV, and the ABI flag can all be green and injection still fails — if `amfi` is `enforcing`, dyld refuses the load. Any single failed link produces an identical-looking "dylib didn't load"; `doctor` exists to name *which* one.

### Output shape (frozen)

```jsonc
{
  "ok": false,
  "osBuild": "26.3 (26D...)",            // OS-build-specific; normalized out of snapshots, like sessionId
  "checks": [
    { "check": "sip",          "pass": true,  "detail": "disabled" },
    { "check": "amfi",         "pass": false, "detail": "enforcing",
      "remedy": "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot" },
    { "check": "libval",       "pass": true,  "detail": "disabled" },
    { "check": "arm64e-abi",   "pass": true,  "detail": "present" },
    { "check": "arch",         "pass": true,  "detail": "arm64e" },
    { "check": "flexmac-built","pass": true,  "detail": "present" }
  ]
}
```

`remedy` is present **only** on a failing check, and is exactly one line — never a stack trace. `doctor` answers before any IPC socket exists, so its result object is **not** bound by the JSON-Lines `schemaVersion`/`sessionId`/`_meta` envelope (that governs post-attach query verbs).

## 2. Agent reaction on non-green

❌ Don't run `csrutil`, edit `nvram boot-args`, or touch the LV plist autonomously to "unblock" yourself.
✅ Do report the failing `check` + its `remedy` **verbatim**, then **STOP**. Do not proceed to `attach`.

- `doctor` is **detect-and-instruct by default** — it never mutates machine state unless `--fix` is passed.
- `doctor --fix` opts into sudo auto-remediation of the *remediable* checks (`nvram boot-args`, `DisableLibraryValidation`). It **echoes each command before running it**, never runs anything implicitly, and **cannot** complete steps that need Recovery (SIP via `csrutil`) or a reboot.

| `--fix` outcome | Exit |
|-----------------|------|
| remediated everything; **no** Recovery/reboot step remained | `0` (re-run after any reboot to confirm) |
| remediated what it could; a **Recovery or reboot** step remains | **still `6`** — prints the echoed commands + exactly which manual steps + reboot remain |

A reboot-pending box is **not ready**. Stay stopped at exit `6` until a fresh `doctor` returns `0`.

## 3. The dual-use posture (read once, then it's settled)

State this **unprompted, every session** — a capable agent skips it by default; this makes it non-negotiable.

| Rule | Why |
|------|-----|
| **Dedicated dev box only.** | SIP **+** AMFI **+** LV off is a real, **system-wide** regression: *any* process can load code into *any* other. The box must hold **no real data or credentials.** Reversible from Recovery. |
| **v1 is read-only.** | No write/mutation verbs. Even `ivars`/value reads are opt-in + timeout-bounded — they run code in someone else's process. |
| **The tool NEVER ships.** | The signed `flexscope-boot.dylib` / `FLEXMac.framework` / CLI only work on a defanged box and are an **attack tool** on any other machine. They must never reach a shippable target, release build, release CI job, or committed entitlements file. |
| **Only knowledge crosses into the product** | A font name, a row height, a constraint, a material — **never** the tool or the injection step. |
| **Refuse to inspect your own shipping app** | Use a debugger you own for that. flexscope is for apps you *can't* debug. |
| **Refuse to run on a non-dev-box** | If the machine holds real data/creds, stop. |

❌ Don't copy a private class name (`_NSTextFieldSimpleLabel`) into product code, or vendor the dylib "just for CI."
✅ Do extract the *semantic fact* (e.g. `NSFont.preferredFont(forTextStyle:)`, a `cornerRadius`, a vibrancy material) and rebuild it with **public, semantic** AppKit.

## 4. Remediation table

Each remedy is the one-line `remedy` string the failing check emits. Defaults for some flags and the exact IPC op-name strings are **unspecified in the frozen spec — see `--help` / the schema, don't invent them.**

| Failing check | `detail` | Remedy (verbatim from `doctor`) | Channel |
|---------------|----------|----------------------------------|---------|
| `sip` | `enabled` | reboot to **Recovery**, run `csrutil disable` (or `csrutil enable --without ...` per Apple's current Permissive flow), reboot | Recovery — `--fix` **cannot** do this |
| `amfi` | `enforcing` | `sudo nvram boot-args="amfi_get_out_of_my_way=0x1 -arm64e_preview_abi" && reboot` | `--fix` sets boot-args; **reboot remains** |
| `libval` | `enabled` | `sudo defaults write <LV plist domain> DisableLibraryValidation -bool true` | `--fix` can run this |
| `arm64e-abi` | `absent` | add `-arm64e_preview_abi` to `nvram boot-args` (folded into the `amfi` remedy above) `&& reboot` | `--fix` sets boot-args; **reboot remains** |
| `arch` | `arm64` \| `x86_64` | rebuild the dylib **arm64e** + re-sign (`scripts/sign.sh`) — a plain-arm64 build fails dyld silently | local rebuild |
| `flexmac-built` | `absent` | build `FLEXMac.framework` (`swift build -c release`) then re-run `doctor` | local build |

> Recovery- and reboot-gated rows (`sip`, `amfi`, `arm64e-abi`) keep the box at exit `6` until the reboot completes and a clean `doctor` returns `0`. Never assume readiness from a partial `--fix`.

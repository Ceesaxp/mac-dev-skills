# Doctor / signing gate & the two postures

> `uitool doctor` (machine posture) and `uitool signing <target>` (per-app verdict) — both run locally, open no socket, hit no target. The whole point: know *before* you attach whether the cheap cooperative path reaches this target, or whether it needs the unrestricted dev-box.

## The reframe (read this first)

macOS gates injection **per target**, and which gate applies depends on **who controls the target's code signing**. There is no single "is this machine ready to inject?" question — there are two:

- **Cooperative** — for an app **you build and sign** for development, the target opts in (a debug build carries `get-task-allow`). Injection works on a **stock, SIP-enabled Mac** — the same way lldb / Xcode / Reveal attach to your own builds every day. **No machine defang.**
- **Unrestricted** — for an app **you did not sign** (Mail, Finder, a notarized third-party app) there is no per-app opt-in, so the only path is to lower system protections **machine-wide**. That is the defanged dev box.

`doctor` reports both so an agent knows what it can reach from here. The old "this tool requires turning off system security; refuse to run on a normal machine" framing is the **worst case, not the floor** — it applies only to the unrestricted posture.

## 1. `doctor` — two ModeReports

`uitool doctor` emits two posture reports and judges each check **independently** (a half-configured machine yields an itemized verdict, never one mystery failure). It takes no target.

```jsonc
{
  "cooperative": {
    "note": "Inspect apps you build and sign for development (get-task-allow). No SIP / AMFI / library-validation changes — your machine is already capable.",
    "requires": [
      { "name": "arch",            "detail": "arm64",   "status": "ok" },
      { "name": "injectable-arm64","detail": "present", "status": "ok" }
    ],
    "usable": true
  },
  "unrestricted": {
    "note": "Additionally required only to inspect apps you did NOT sign (system / notarized). Dedicated dev box; reversible from Recovery.",
    "requires": [
      { "name": "sip",              "detail": "enabled",   "status": "failed", "remedy": "boot to Recovery and run: csrutil enable --without kext --without dtrace; csrutil authenticated-root disable" },
      { "name": "amfi",             "detail": "enforcing", "status": "failed", "remedy": "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot" },
      { "name": "libval",           "detail": "unread",    "status": "unknown" },
      { "name": "arm64e-abi",       "detail": "absent",    "status": "failed", "remedy": "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot" },
      { "name": "arch",             "detail": "arm64",     "status": "ok" },
      { "name": "injectable-arm64e","detail": "absent",    "status": "failed", "remedy": "build the arm64e UIToolBoot injectable (the injection half is not yet built)" }
    ],
    "usable": false
  },
  "osBuild": "26A5353q"
}
```

| Posture | `requires` checks | When usable |
|---------|-------------------|-------------|
| `cooperative` | `arch` (Apple Silicon), `injectable-arm64` (the arm64 UIToolBoot dylib is built) | your own `get-task-allow` apps, **stock SIP-on Mac** |
| `unrestricted` | `sip`, `amfi`, `libval`, `arm64e-abi`, `arch`, `injectable-arm64e` | any app incl. system; **dedicated dev box** |

- Each check is `{name, detail, status}` (+ `remedy` when `status != "ok"`). `status` ∈ `ok` / `failed` / `unknown` (e.g. `libval` reads `unread`/`unknown` when its plist isn't readable).
- A `ModeReport.usable` is true only when **every** check in its `requires` is `ok`.
- **Exit `0` iff `cooperative.usable`; otherwise exit `6`.** `unrestricted` being unusable on a stock Mac is *expected* and never forces a non-zero exit on its own.
- `osBuild` is reported for context, is **not** a check, never affects usability, and is normalized out of snapshots (like `sessionId`).

❌ Don't read `doctor` as "all checks must pass." ✅ Do branch on the exit code (`0` = cooperative reachable) and, for an unrestricted target, read `unrestricted.usable` + each failing check's `remedy`.

> **AMFI is the load-bearing link of the *unrestricted* stack.** SIP, LV, and the ABI flag can all be green and injection still fail if `amfi` is `enforcing` — dyld refuses the load. None of this touches the cooperative posture.

## 2. `signing <target>` — the per-app verdict

`doctor` can't judge a *target* (it has no target). `uitool signing <target>` reads one app's code signature and returns the bottom line:

```jsonc
{
  "target": "/System/Applications/Calculator.app",
  "identifier": "com.apple.calculator",
  "signed": true,
  "authority": "macOS Software Signing",
  "getTaskAllow": false,        // the cooperative opt-in — false on Apple-signed apps
  "hardenedRuntime": false,
  "sandboxed": true,
  "entitlements": { "com.apple.security.app-sandbox": true },
  "cooperativeInjectable": false  // bottom line: cooperative path can't reach this target
}
```

`<target>` = a running pid, a bundle id, or a path to a `.app` / executable. Use it before attaching: `cooperativeInjectable: true` (your own dev build) → `attach`/`launch` on a stock Mac; `false` (a system/notarized app) → only the unrestricted posture reaches it.

## 3. Agent reaction on non-green

❌ Don't run `csrutil`, edit `nvram boot-args`, or touch the LV plist autonomously to "unblock" yourself.
✅ Do report the failing `check` + its `remedy` **verbatim**, then **STOP** for that posture.

- The spec describes a `doctor --fix` (opt-in sudo remediation of the *unrestricted* stack only). It is **not shipped in the binary** yet (`uitool doctor --help` shows no flags). Do not instruct anyone to run `uitool doctor --fix` until it lands.
- Recovery- and reboot-gated steps (`sip`, `amfi`, `arm64e-abi`) keep the box not-ready until the reboot completes and a fresh `doctor` shows `unrestricted.usable`.

## 4. The dual-use posture (read once, then it's settled)

| Rule | Why |
|------|-----|
| **The unrestricted defang is a dedicated dev box only.** | SIP **+** AMFI **+** LV off is a real, **system-wide** regression: *any* process can load code into *any* other. That box must hold **no real data or credentials.** Reversible from Recovery. **Cooperative needs none of this.** |
| **Cooperative is a stock-Mac operation.** | Inspecting your own `get-task-allow` apps changes no machine security. Don't refuse it. |
| **The injectable NEVER ships.** | The signed `UIToolBoot` dylib only works on its built box and is an **attack tool** elsewhere. It is `.gitignore`d and must never reach a shippable target, release build, release CI, or committed entitlements file — for **both** postures. uitool is excluded from `mise run install`. |
| **v1 is read-only.** | No write/mutation verbs. Even `inspect --invoke` (value reads) is opt-in + gated — it runs code in someone else's process. |
| **Only knowledge crosses into the product.** | A font name, a row height, a constraint, a material — **never** the tool or the injection step. |
| **Don't inspect your own *shipping* app with it.** | Use a debugger you own. uitool is for apps you can't debug. |

❌ Don't copy a private class name (`_NSTextFieldSimpleLabel`) into product code, or vendor the dylib "just for CI."
✅ Do extract the *semantic fact* (`NSFont.preferredFont(forTextStyle:)`, a `cornerRadius`, a vibrancy material) and rebuild it with **public, semantic** AppKit.

## 5. Build / sign

- **uitool + the arm64 injectable:** `mise run uitool-sign` (builds, then `codesign -s - --force --entitlements scripts/uitool-debugger.entitlements`, granting `com.apple.security.cs.debugger` — required for `attach`). The arm64 `UIToolBoot` dylib is built into `.build` and stays there (gitignored).
- The **unrestricted** posture additionally needs the machine defang above **and** an **arm64e** injectable — and the unrestricted running-attach is still deferred.

# PrivateHeaderKit — install & dump macOS private headers

Install PrivateHeaderKit, dump macOS AppKit private headers, then grep them for a real selector. Static dumper — no SIP changes.

PrivateHeaderKit reconstructs Objective-C headers by reading `/System/Library/{Frameworks,PrivateFrameworks}` with `xcrun` tooling. It is a **dumper only**: it ships zero guidance on *calling* or swizzling private APIs — that is this skill's job. Because it is **static** (no runtime injection), it needs **no SIP / AMFI / library-validation changes and no special entitlements**. That is the key contrast with runtime injection (`appkit-app-inspector`).

Repo: <https://github.com/lynnswap/PrivateHeaderKit> (MIT, not vendored). Requires Xcode command-line tools (`xcrun`), swift-tools 6.2, macOS 14+.

## 1. Install

```bash
git clone https://github.com/lynnswap/PrivateHeaderKit && cd PrivateHeaderKit
swift run -c release privateheaderkit-install
```

Installs three binaries into `~/.local/bin`:

| Binary | Role |
|--------|------|
| `privateheaderkit-dump` | The dumper you invoke (next section) |
| `headerdump` | Installed helper binary — **not** the dump command |
| `headerdump-sim` | Installed helper binary (simulator-oriented) |

| Install flag | Effect |
|--------------|--------|
| `--prefix <dir>` | Install root (binaries go under `<prefix>/bin`) |
| `--bindir <dir>` | Override the bin directory directly |

Ensure `~/.local/bin` is on `PATH` afterward.

## 2. Dump macOS headers

The dump command is **`privateheaderkit-dump`** (not `headerdump`). The default `--platform` is **`ios`** — for AppKit you **MUST** pass `--platform macos`, or you dump the wrong SDK.

```bash
# Dump just AppKit into a local, grep-friendly tree
privateheaderkit-dump --platform macos --target AppKit --out ./private-headers --layout headers
```

| Flag | Effect |
|------|--------|
| `--platform macos` | **Required for AppKit** — default is `ios` |
| `--target <Framework>` | Framework to dump; repeatable (`--target AppKit --target HIServices`) |
| `--target @frameworks` | Preset: all public + private frameworks |
| `--target @system` | Preset: system framework set |
| `--target @all` | Preset: everything available |
| `--out <dir>` | Output dir (default `~/PrivateHeaderKit/generated-headers/<platform>/<version>`) |
| `--layout headers` | Strip the `.framework` suffix → flat dir, easier to grep |
| `--layout bundle` | Preserve `Foo.framework/…` bundle structure |
| `--force` | Re-dump even if output exists |
| `--skip-existing` | Skip targets already dumped |
| `--no-nested` | Don't recurse into nested/embedded frameworks |
| `-D`, `--verbose` | Verbose diagnostics |

**Output location:** `~/PrivateHeaderKit/generated-headers/<platform>/<version>` unless `--out` is given (e.g. `…/generated-headers/macos/27.0`). Any frameworks that fail to dump are recorded in `_failures.txt` in the output dir — check it.

## 3. Browse / grep → find a real selector, then verify at runtime

Grep the dump for the behavior you want, then read the surrounding `@interface` to recover the **owning class** and **argument types**.

```bash
# Find candidate selectors mentioning "titlebar"
grep -rn "titlebar" ./private-headers/AppKit/ | head

# Read the declaring interface for the class + arg types
grep -rn -B2 "setTitlebarSeparatorStyle:" ./private-headers/AppKit/NSWindow.h
```

A grep hit is only a *historical* fact about one SDK build. Private symbols move or vanish between OS versions — **verify the class and selector still exist at runtime before relying on them**. This uses only public Objective-C runtime symbols:

```swift
import AppKit
import ObjectiveC.runtime

/// Returns true only if `cls` exists AND its instances respond to `sel` on THIS OS.
func privateAPIExists(class className: String, selector selName: String) -> Bool {
    guard let cls = NSClassFromString(className) else { return false }   // class may be gone
    let sel = NSSelectorFromString(selName)
    // instancesRespondToSelector: covers methods provided by categories/dynamic resolution.
    guard cls.instancesRespond(to: sel) else { return false }
    // Belt-and-suspenders: confirm a concrete IMP is installed.
    return class_getInstanceMethod(cls, sel) != nil
}

// Guard the call site — degrade, never crash, when the OS changed under you.
let window: NSWindow = .init()
if privateAPIExists(class: "NSWindow", selector: "setTitlebarSeparatorStyle:"),
   window.responds(to: NSSelectorFromString("setTitlebarSeparatorStyle:")) {
    window.perform(NSSelectorFromString("setTitlebarSeparatorStyle:"), with: 1)
} else {
    // fall back to public API / no-op
}
```

BAD foil — trusting the dump and calling blind:

```swift
// ❌ Selector was real on macOS 14 but renamed by 15. perform(_:) → unrecognized selector → crash.
window.perform(NSSelectorFromString("setTitlebarSeparatorStyle:"), with: 1)
```

`NSClassFromString`, `NSSelectorFromString`, `instancesRespondToSelector:` / `respondsToSelector:`, and `class_getInstanceMethod` are all public SDK symbols — confirmed against the macOS 27.0 SDK headers.

## 4. ❌ Don't / ✅ Do

| ❌ Don't | ✅ Do |
|---------|------|
| Run `privateheaderkit-dump --target AppKit` and dump the **iOS** SDK by default | Pass `--platform macos` explicitly for AppKit |
| Call `headerdump` expecting it to dump | `headerdump` is just an installed binary name; the dumper is `privateheaderkit-dump` |
| Disable SIP / AMFI to "let the dumper read the frameworks" | It is a **static** `xcrun` read — needs **no** SIP/AMFI/entitlement changes (that's the *inspector*, not this) |
| Trust a grepped selector forever | Re-verify class + selector at runtime each OS (`NSClassFromString` + `instancesRespond(to:)`) |
| Dump into the default tree, then grep `Foo.framework/…` paths | Use `--layout headers` for a flat, grep-friendly tree; check `_failures.txt` |

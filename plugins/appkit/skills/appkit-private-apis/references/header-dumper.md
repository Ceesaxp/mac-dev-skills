# headerdump — recover macOS private headers

Dump an Objective-C framework's headers with `headerdump`, then grep them for a real selector and verify it at runtime. Static dumper — no SIP changes.

`headerdump` reconstructs Objective-C headers (classes, methods, properties, ivars, protocols, categories) from a Mach-O framework or the dyld shared cache. It is a **dumper only** — it ships no guidance on *calling* or swizzling private APIs; that is this skill's job. Because it is **static** (it reads the binary / shared cache, no runtime injection), it needs **no SIP / AMFI / library-validation changes and no special entitlements**. That is the key contrast with the runtime inspector (`appkit-app-inspector` / `uitool`).

It ships in the `apple-platform-tools` monorepo (a Swift port of lynnswap's PrivateHeaderKit — the `PH_*` env var names are the surviving lineage) and installs with the other static tools:

```bash
mise run install      # builds + ad-hoc signs + installs sdk-api, sdk-search, headerdump, redump → ~/.local/bin
```

Ensure `~/.local/bin` is on `PATH` afterward.

## 1. Invocation

`headerdump` is a legacy-style CLI — **no subcommands, single-letter flags**. The positional argument is a **path** (a framework bundle or a Mach-O file), not an SDK target name.

```
headerdump [<options>] <filename|framework>
headerdump [<options>] -r <sourcePath>
```

| Flag | Effect |
|------|--------|
| `-o <dir>` | Output directory (default: the current directory) |
| `-r` | Recurse a source path, dumping every framework found |
| `-b` | Rebuild the original directory structure under the output dir |
| `-h` | Add a `Headers/` folder for bundles — **a real flag, NOT help** (use no args for usage) |
| `-s` | Skip files already dumped |
| `-j <name>` | Dump only a single class/protocol name |
| `-c` | Use the dyld shared cache (recommended for simulator runtimes) |
| `-D` | Verbose logging |
| `-R` | Prefer Objective-C runtime metadata (auto-enabled inside a simulator) |

```bash
# Dump one framework into a local, grep-friendly tree
headerdump -o ./private-headers /System/Library/Frameworks/AppKit.framework

# A single class only
headerdump -o ./private-headers -j NSWindow /System/Library/Frameworks/AppKit.framework
```

There is **no** `--platform` / `--target` / `--out` / `--layout` flag. Pass the actual framework path; unknown long flags are ignored (a stray `--target AppKit` makes `headerdump` treat `AppKit` as a filename and silently produce nothing). On modern macOS most system frameworks live only in the dyld shared cache — use `-c` to dump from there.

## 2. Simulator / other runtimes

There is no separate `headerdump-sim` binary — simulator runtimes are handled in-tool:

- `-c` (use the dyld shared cache) and `-R` (prefer runtime metadata, auto inside a simulator).
- The `DYLD_ROOT_PATH` / `PH_RUNTIME_ROOT` env override points at a runtime root; under `simctl spawn` use the `SIMCTL_CHILD_` prefix (`SIMCTL_CHILD_PH_RUNTIME_ROOT=…`) so it survives into the spawned process.

## 3. Browse / grep → find a real selector, then verify at runtime

Grep the dump for the behavior you want, then read the surrounding `@interface` to recover the **owning class** and **argument types**.

```bash
grep -rn "titlebar" ./private-headers/ | head
grep -rn -B2 "setTitlebarSeparatorStyle:" ./private-headers/NSWindow.h
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

`NSClassFromString`, `NSSelectorFromString`, `instancesRespondToSelector:` / `respondsToSelector:`, and `class_getInstanceMethod` are all public SDK symbols.

## 4. ❌ Don't / ✅ Do

| ❌ Don't | ✅ Do |
|---------|------|
| `headerdump --target AppKit` (silently dumps nothing — long flag ignored, `AppKit` read as a filename) | Pass the framework **path**: `headerdump -o <dir> /System/Library/Frameworks/AppKit.framework` |
| Read `-h` as "help" | `-h` adds a `Headers/` folder; run `headerdump` with no args for usage |
| Expect a system framework on disk on modern macOS | Use `-c` to dump from the dyld shared cache |
| Disable SIP / AMFI to "let the dumper read the frameworks" | It's a **static** read — needs **no** SIP/AMFI/entitlement changes (that's the *inspector*, not this) |
| Trust a grepped selector forever | Re-verify class + selector at runtime each OS (`NSClassFromString` + `instancesRespond(to:)`) |

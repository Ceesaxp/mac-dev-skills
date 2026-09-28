---
name: appkit-private-apis
description: Use when discovering, declaring, or calling a private/undocumented AppKit or Objective-C API from a macOS app — dumping private framework headers, declaring a private interface (ObjC category, bridging header, @objc protocol, or dlsym for C), calling it from Swift, or method swizzling (method_exchangeImplementations / setImplementation, capturing the original, restoration, thread-safety). Targets native macOS AppKit (Swift 6 / ObjC).
---

# AppKit Private APIs

## Overview

Discover a private AppKit/Objective-C symbol, declare an interface to it, call it from Swift, and — when you must change framework behavior — swizzle it safely. This is legitimate for research, debugging, internal tools, and Developer-ID apps. **The technique is the easy part; shipping it responsibly is the part that gets skipped.**

> **This skill informs, it never gates.** It will help you use private APIs and swizzling. It also tells you the trade-off so you decide with eyes open — see the advisory below, and surface it *unprompted* whenever the code could ship.

## Distribution advisory — say this unprompted when the code might ship

Private-API use is a **distribution** decision, not a correctness one. Whenever you hand someone private-API or swizzling code that could go into a shipped app, volunteer this — don't wait to be asked:

- **App Store review may or may not reject it.** Apple judges private-API usage **case-by-case** — not every use is auto-rejected, and there's no public allow-list. Assume it *might* be rejected.
- **Dodging the static scanner is not safety.** Hiding a private class name (no string literals, `object_getIvar` instead of KVC, runtime-built selectors) only defeats *static* analysis. Runtime use can still be detected and rejected. **Never frame scanner-evasion as "now it's safe to ship."**
- **Developer ID + notarization is the escape hatch.** If review rejects it — or to avoid the question entirely — distribute **outside** the Mac App Store: Developer-ID-signed, notarized, shipped via web / Sparkle / direct download. Private APIs are allowed there (you own the risk of OS updates breaking them). See **`appkit-packaging`** for the full distribution picture.
- **Tone:** "here's the trade-off and your options," never "you may not."

→ Full wording + the packaging end: `references/distribution-advisory.md`

## The workflow

### 1. Discover the private surface — headerdump + redump

Two **static** tools from [apple-platform-tools](https://github.com/markmals/apple-platform-tools), installed together with `brew install markmals/tap/apple-platform-tools`. Both read the binary / dyld shared cache — **no SIP/AMFI changes, no entitlements** (unlike runtime injection — see `appkit-app-inspector`).

- **`headerdump`** recovers an Objective-C framework's headers (class/method/property/ivar/protocol). Legacy-style CLI, single-letter flags, positional **path** (not an SDK target name):

```bash
headerdump -o ./private-headers /System/Library/Frameworks/AppKit.framework   # add -c to read the dyld shared cache
```

- **`redump`** answers "what's actually *in* this Mach-O?" — symbols, imports, exports, strings, segments (native reads; disassembly is a gated, not-shipped slice):

```bash
redump exports <binary> | grep -i titlebar      # is the symbol there?
redump imports <binary> --library CoreUI        # which dylib provides it?
redump strings <binary> --filter FeatureFlag    # telling strings
```

→ `references/header-dumper.md`, `references/redump.md`

### 2. Browse / grep the dumped headers

`grep -rn "titlebar" ./private-headers/AppKit.framework` etc. Find the real selector, its argument types, and the owning class. **Verify the class/selector still exists at runtime** before relying on it — private symbols move between OS versions.

### 3. Declare the interface

Pick the lightest mechanism that compiles:

| You have | Declare via | Notes |
|----------|-------------|-------|
| ObjC method on a known class | **ObjC category** in a bridging header / `.h` | Cleanest; type-checked; `@interface NSWindow (Private)` |
| Swift-only target, one method | **`@objc protocol`** + `unsafeBitCast(obj, to:)` | No bridging header needed |
| A private **ivar** | `object_getIvar(_:_:)` / `value(forKey:)` | `object_getIvar` avoids the KVC string scanner |
| A C function in a framework | **`dlsym`** on an `dlopen` handle | For non-ObjC entry points |

→ `references/declaring-and-calling.md`

### 4. Call it

Through the declared interface. Resolve classes at runtime with `NSClassFromString(_:)` and selectors with `NSSelectorFromString(_:)` when you must avoid literals; guard every optional (`responds(to:)`) so an OS change degrades instead of crashing.

### 5. Swizzle — only when you must change existing behavior

Swizzling replaces a method's implementation process-wide. Do it **correctly or not at all** — a half-swizzle corrupts every instance of the class.

```swift
// Minimal correct shape — full patterns (restoration, thread-safety, when-not-to) in references/swizzling.md
extension NSView {
  private static let _swizzleOnce: Void = {
    let cls: AnyClass = NSView.self
    guard
      let original = class_getInstanceMethod(cls, #selector(NSView.draw(_:))),
      let replacement = class_getInstanceMethod(cls, #selector(NSView.swizzled_draw(_:)))
    else { return }
    method_exchangeImplementations(original, replacement)   // reversible: call again to restore
  }()

  static func installDrawSwizzle() { _ = _swizzleOnce }     // idempotent: the static runs once

  @objc dynamic func swizzled_draw(_ dirtyRect: NSRect) {
    self.swizzled_draw(dirtyRect)   // NOT recursion — post-swap this calls the ORIGINAL draw(_:)
    // your behavior here
  }
}
```

**Non-negotiables for any swizzle** (details + the IMP-capture variant in `references/swizzling.md`):
1. **Call the original.** Capture it (the exchanged selector, or a stored `IMP`) and invoke it — never drop it.
2. **Idempotent install.** A `static let`/`dispatch_once` so a double-install can't double-swap (which silently un-swizzles).
3. **Restoration path.** Keep a way back (`method_exchangeImplementations` again, or stash the original `IMP` and `method_setImplementation` it back). "Uninstall isn't worth it" is not acceptable for anything beyond a throwaway.
4. **Thread-safety.** Install before threads race the method; don't swap a hot method live.
5. **Know when not to.** Subclasses that override the method, layer-backed draw paths, and KVO-affected methods make swizzling fragile — prefer a delegate, subclass, or notification if one exists.

## Anti-patterns

| ❌ Don't | ✅ Do |
|---------|------|
| "Avoid the string literal and it's App-Store-safe" | Scanner-evasion ≠ policy-safe; name the case-by-case risk + Developer-ID escape hatch |
| Swizzle and never call the original | Capture and invoke the original IMP every time |
| Swizzle in a non-idempotent `+load`/init | One-time `static let` guard |
| "Restoring is too hard, I'll leave it" | Stash the original IMP; provide an uninstall |
| Private symbol from memory | Dump with `headerdump` (or confirm with `redump`) + verify it exists at runtime (`responds(to:)` / `NSClassFromString`) |
| Treat header dumping as needing SIP off | `headerdump` / `redump` are static reads — no SIP changes (that's the *inspector*, not this) |

## References

| File | Read when… |
|------|------------|
| `references/header-dumper.md` | Dumping macOS private headers with `headerdump` (install, flags, simulator, runtime verification) |
| `references/redump.md` | Finding symbols / imports / exports / strings in a Mach-O with `redump` |
| `references/declaring-and-calling.md` | Declaring a private interface (category / bridging / `@objc` protocol / `dlsym`) and calling it |
| `references/swizzling.md` | Writing a correct, restorable, thread-safe swizzle (and deciding whether to) |
| `references/distribution-advisory.md` | The App-Store-review / Developer-ID trade-off to surface, and the `appkit-packaging` cross-reference |

---
*Companion: `appkit-app-inspector` (uitool) learns private structure from a **running** app (runtime injection — cooperative on a stock Mac for your own apps; the unrestricted defang only for apps you didn't sign). This skill works from **static** binaries — `headerdump` / `redump`, no SIP changes.*

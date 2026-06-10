# Declaring & calling a private interface

Given a private selector/class (from a header dump or runtime probe), declare a typed Swift/ObjC interface, call it, and degrade gracefully when the OS changes.

## Mechanism table

| Mechanism | Declare with | Call from Swift | Use when |
|---|---|---|---|
| **ObjC category** | `@interface NSWindow (Priv)` in a header behind the **bridging header** | direct dot/method syntax, fully typed | private method on a **public** class; you want compiler-checked types |
| **`@objc protocol` + `unsafeBitCast`** | `@objc protocol P { func _foo() }` then `unsafeBitCast(obj, to: P.self)` | typed call after a `responds(to:)` guard | private method, no bridging header, pure-Swift target |
| **`object_getIvar` / `class_getInstanceVariable`** | look the `Ivar` up by C-string name, read with `object_getIvar(obj, ivar)` | returns `id`; cast the result | private **instance variable** (not a method); avoids KVC string-literal bait |
| **`dlopen` / `dlsym`** | `dlsym(handle, "SomeCFunc")` → `unsafeBitCast` to a `@convention(c)` pointer | call the function pointer | private **C function** in a (possibly private) framework |
| **`NSClassFromString` / `NSSelectorFromString`** | build `Class` / `SEL` from a runtime-assembled string | `cls.responds(to:)` then `perform(_:)` or `@objc protocol` cast | private **class** you must not name with a literal; defeats the *static* scanner |

`unsafeBitCast`, `@convention(c)`, and `@objc protocol` are Swift language features (no header). But the **selectors, classes, ivars, and C symbols** you feed them must be real — confirm each against a header dump (`appkit-private-apis` → PrivateHeaderKit) before shipping.

## Example — call a private ObjC method via `@objc protocol`, guarded

Goal: call `-[NSWindow _setTransformForAnimation:animate:]` (illustrative private selector) without a bridging header, with a runtime class fallback and no string-literal class name.

```swift
import AppKit
import ObjectiveC.runtime

// 1. Typed shape for the private selector. @objc protocol = no `@objc` runtime class emitted.
@objc protocol _PrivateWindowAnimating {
    func _setTransformForAnimation(_ t: CGAffineTransform, animate: Bool)
}

extension NSWindow {
    /// Returns true if the private animation was applied; false if unavailable.
    @discardableResult
    func tryPrivateTransform(_ t: CGAffineTransform, animate: Bool) -> Bool {
        // 2. Build the selector at runtime — no static string the scanner can flag whole.
        let sel = NSSelectorFromString("_setTransformForAnimation:animate:")

        // 3. GUARD: if a future macOS drops/renames the selector, degrade instead of crash.
        guard responds(to: sel) else { return false }

        // 4. unsafeBitCast to the typed protocol, then call with full type checking.
        let shim = unsafeBitCast(self, to: _PrivateWindowAnimating.self)
        shim._setTransformForAnimation(t, animate: animate)
        return true
    }
}

// Runtime-lookup fallback when the class itself is private (here NSWindow is public; shown for shape):
func makePrivateScroller() -> NSObject? {
    // 5. NSClassFromString returns nil if the class is gone — never force-unwrap.
    guard let cls = NSClassFromString("NSScrollerImp") as? NSObject.Type else { return nil }
    return cls.init()
}
```

Callers always check the `Bool` / `nil` and fall back to public API:

```swift
if !window.tryPrivateTransform(t, animate: true) {
    window.animator().setFrame(targetFrame, display: true)  // public-API fallback path
}
```

### BAD foil — same call, no guards

```swift
// ❌ unsafeBitCast + direct call with no responds(to:) check.
let shim = unsafeBitCast(window, to: _PrivateWindowAnimating.self)
shim._setTransformForAnimation(t, animate: true)   // unrecognized selector → CRASH on the OS that drops it
```

`unsafeBitCast` does **no** conformance check, so a missing selector is not caught at the cast — it explodes at the call site on a future macOS. The guard is mandatory.

## Graceful degradation — guard before every private touch

| Touching… | Guard with | On failure |
|---|---|---|
| a private **method** | `obj.responds(to: sel)` (or `cls.instancesRespond(to:)`) | run the public-API fallback |
| a private **class** | `NSClassFromString("X") != nil` | skip the feature, log once |
| a private **ivar** | `class_getInstanceVariable(cls, "name") != nil` | treat value as absent |
| a private **C symbol** | `dlsym(handle, "f") != nil` | no-op the call path |

- ❌ Don't force-unwrap `NSClassFromString(...)!` or assume `responds(to:)` — an OS update *will* remove a private symbol eventually.
- ✅ Do gate every private access and keep a public-API path so an OS change **degrades the feature**, never crashes the app.
- ✅ Do probe once and cache the `Bool`/`SEL`/`Ivar`; don't re-`dlsym` on a hot path.

## ❌ literal name vs ✅ runtime lookup — and what it does *not* buy you

```swift
// ❌ Static-scanner bait: the private class name sits in the binary as a contiguous literal.
let c = NSScrollerImp.self                      // direct symbol reference
window.setValue(x, forKey: "_privateState")     // KVC literal — also scannable

// ✅ Runtime lookup: name assembled at runtime; ivar read without KVC string.
guard let cls = NSClassFromString("NSScroller" + "Imp") else { return }
if let ivar = class_getInstanceVariable(object_getClass(obj), "_privateState") {
    let value = object_getIvar(obj, ivar)       // no KVC literal in the binary
}
```

> ⚠️ This defeats **static analysis only.** Apple's review can still detect private-API use **at runtime**, and there is no public allow-list. Runtime lookup is *not* a path to App Store safety — never frame it that way. Surface the case-by-case-rejection risk and the Developer-ID / notarization escape hatch: see **`references/distribution-advisory.md`** (and `appkit-packaging` for the distribution end).

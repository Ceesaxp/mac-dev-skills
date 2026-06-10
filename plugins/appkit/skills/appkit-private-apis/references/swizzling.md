# Method Swizzling — Correctly, or Not at All

Swap an Objc method's `IMP` at runtime safely, reversibly, idempotently — or don't touch it. A half-swizzle corrupts **every instance** of the class process-wide.

## 1. Two mechanisms

| Approach | What it does | Restore | Notes |
|---|---|---|---|
| `method_exchangeImplementations(m1, m2)` | Swaps the two `Method`s' `IMP`s. Your "swizzled" selector and the original trade places. | Call `method_exchangeImplementations` again with the same pair. | Your replacement is a *second selector* you add. Calling original = call the now-renamed selector (looks like recursion but isn't). Convenient, but pollutes the class with an extra method and is fragile under repeat installs. |
| Capture an `IMP` + `method_setImplementation` | `let orig = method_getImplementation(m)`, stash it, then `method_setImplementation(m, myIMP)`. Inside `myIMP`, call `orig` via a typed `@convention(c)` cast. | `method_setImplementation(m, orig)`. | Preferred. No extra selector. Original is an explicit captured pointer — restoration is exact. `imp_implementationWithBlock` builds `myIMP` from a Swift closure capturing `orig`. |

`class_replaceMethod(cls, sel, imp, types)` **returns the previous `IMP`** (or installs via `class_addMethod` if absent). Use its return value as the stash — one call gives you install + the restore handle.

```swift
// Calling the original from inside your replacement: cast the stashed IMP.
typealias OrigFn = @convention(c) (AnyObject, Selector) -> Bool
let callOriginal = unsafeBitCast(orig, to: OrigFn.self)
let result = callOriginal(obj, selector)   // exact original behavior, then your logic
```

## 2. The five non-negotiables

| # | Rule | Why | How |
|---|---|---|---|
| 1 | **Call the original.** | You replaced framework behavior; skipping it breaks layout, drawing, state. | Stash `orig`, invoke it via `@convention(c)` cast before/after your code. |
| 2 | **Idempotent, one-time install.** | A second swizzle double-wraps or (with exchange) un-swizzles. `+load` runs once per class but `dispatch_once`/`static let` survives multiple call sites. | `static let install: Void = { ... }()` or `dispatch_once`. Never put non-idempotent swizzle in plain `+load` without a guard. |
| 3 | **Thread-safety.** | Two threads installing concurrently race the `IMP` swap. | Do the install behind the same `static let`/`dispatch_once`. The runtime mutators are atomic per-call, but *read-modify-write* (get IMP → set IMP) is not. |
| 4 | **A restoration path.** | Tests, plugin unload, feature toggles need the class clean. | Exchange-back, or `method_setImplementation(m, stashedOrig)`. Keep the stash for the process lifetime. |
| 5 | **Know when NOT to swizzle.** | Many cases have a supported hook. | See table below. |

### ❌ Don't swizzle / ✅ Do instead

| ❌ Swizzling | ✅ Supported alternative |
|---|---|
| Overriding behavior you own | **Subclass** and override the method |
| `-drawRect:` / layer-backed draw | Subclass + override, or set `layer.delegate` / `CALayerDelegate` |
| Reacting to property changes | **KVO** (`observe(_:options:)`) — swizzling setters fights KVO's own isa-swizzling |
| Intercepting delegate callbacks | Wrap/proxy the **delegate**, or `NotificationCenter` |
| One object's behavior | `object_setClass` to a dynamic subclass (KVO-style) — *not* a class-wide IMP swap |

Swizzling a **hot method live** (e.g. `-drawRect:`, `-layout`) while instances are mid-render risks calling a half-installed `IMP`. Install before the class is used, never during active dispatch.

## 3. Complete example — idempotent install + working uninstall

```swift
import ObjectiveC.runtime

enum WindowProbe {
    // Stash the original IMP so uninstall is exact and reversible.
    private static var originalIMP: IMP?
    private static let lock = NSLock()
    private static let selector = #selector(NSWindow.makeKeyAndOrderFront(_:))

    typealias MakeKeyFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    /// Idempotent, thread-safe install. Safe to call from any number of sites.
    static func install() {
        lock.lock(); defer { lock.unlock() }
        guard originalIMP == nil else { return }  // one-time guard
        guard let m = class_getInstanceMethod(NSWindow.self, selector) else { return }

        let orig = method_getImplementation(m)
        originalIMP = orig
        let origFn = unsafeBitCast(orig, to: MakeKeyFn.self)

        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, sender in
            NSLog("makeKeyAndOrderFront on \(obj)")   // our added behavior
            origFn(obj, selector, sender)              // RULE 1: call the original
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }

    /// Restoration path: put the captured original IMP back.
    static func uninstall() {
        lock.lock(); defer { lock.unlock() }
        guard let orig = originalIMP,
              let m = class_getInstanceMethod(NSWindow.self, selector) else { return }
        method_setImplementation(m, orig)  // RULE 4: exact restore
        originalIMP = nil
    }
}
```

### BAD foil — recursion + no restore (teaches what breaks)

```swift
// ❌ Does NOT call the captured original; calls the live selector → infinite recursion.
let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, sender in
    (obj as! NSWindow).makeKeyAndOrderFront(sender)  // re-enters the swizzled IMP forever
}
// ❌ No stashed IMP, no lock, no guard: second install double-wraps; nothing can undo it.
```

## 4. Failure-mode table

| ❌ Don't | ✅ Do |
|---|---|
| Replacement that never invokes the original `IMP` | Stash `orig`, call it via `@convention(c)` cast every path |
| Non-idempotent swizzle in `+load` (or any plain call site) | Guard with `static let`/`dispatch_once`; check a stash before swapping |
| "Uninstall isn't worth it" — leave the class mutated | Keep the captured `IMP`; provide `method_setImplementation(m, orig)` |
| Swizzle a hot method (`-drawRect:`, `-layout`) while instances render | Install at launch before first use; for hot paths, subclass instead |
| Read IMP on one thread, set on another with no lock | Serialize the get→set under one `NSLock`/`dispatch_once` |
| Swizzle to override behavior you own | Subclass and override |

**Type-encoding note:** if you `class_addMethod`/`class_replaceMethod` a brand-new method, pass `method_getTypeEncoding(m)` from the original `Method` so the runtime ABI matches.

**Probing private symbols first:** confirm a private `IMP`/function exists before swizzling near it — `dlopen` the framework and `dlsym(RTLD_DEFAULT, "symbol")`; a non-nil result means the symbol is present this OS version.

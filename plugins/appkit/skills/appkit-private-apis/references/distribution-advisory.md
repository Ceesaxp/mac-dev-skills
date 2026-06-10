# Distribution Advisory — Private APIs & the App Store

Surface this **unprompted** whenever private-API or swizzling code could ship: the accurate review trade-off, the Developer ID escape hatch, and the packaging hand-off. Inform; never gate.

---

## 1. The review reality

App Store review of private-API usage is **case-by-case** — there is no automatic verdict.

| Myth | Reality |
|------|---------|
| "Any private API = instant rejection." | Apple judges **case-by-case**. Some usage passes; some is rejected. |
| "There's a list of allowed private APIs." | **No public allow-list exists.** You cannot pre-clear a symbol. |
| "It passed once, so it's blessed." | A pass is not a guarantee. The next reviewer or build may reject it. |

**Default assumption: it MIGHT be rejected.** Plan for that outcome before you submit, not after.

- ❌ Don't tell the user "this will pass review" or "this will be rejected" — you cannot know either.
- ✅ Do tell the user "review is case-by-case; assume it might be rejected, and here's your fallback."

---

## 2. Scanner-evasion ≠ policy-safety

Hiding a private symbol from Apple's **static** scanner does **not** make shipping it policy-safe.

| Technique | What it actually defeats | What it does NOT do |
|-----------|--------------------------|---------------------|
| No string-literal class names (`NSClassFromString` from parts) | Static string scan | Stop runtime detection |
| `object_getIvar` instead of `value(forKey:)` (KVC) | Static KVC-key scan | Stop runtime detection |
| Runtime-built selectors (`NSSelectorFromString`) | Static selector scan | Stop runtime detection |

These beat **static analysis only.** Runtime instrumentation can still observe the call and reject the build.

- ❌ Don't say "obfuscate the class name and it's safe to ship to the App Store." That is false and gets users burned.
- ✅ Do say "these techniques avoid *static* detection; runtime use is still detectable — they are not a policy shield."

> Evasion is a **research/robustness** tool (degrade gracefully across OS versions), not a compliance strategy.

---

## 3. Developer ID + notarization — the escape hatch

Distributing **outside** the Mac App Store removes the review question entirely.

| | Mac App Store | Developer ID (web / Sparkle / direct) |
|---|---------------|----------------------------------------|
| Gatekeeper | App Review | **Notarization** (automated malware scan) |
| Private APIs | Case-by-case; may reject | **Allowed** |
| Channel | App Store only | Direct download, Sparkle auto-update, `.dmg`/`.pkg` |
| You own | — | **OS-update breakage risk** (private symbols move between releases) |

Notarization is **not** App Review — it scans for malware, it does not police private-API usage. A Developer-ID-signed, notarized, stapled app ships private APIs legitimately.

**The trade you accept:** when macOS updates, a private symbol may vanish or change shape. You own that breakage. Guard every call (`responds(to:)`, `NSClassFromString != nil`) so an OS change **degrades** instead of crashing.

- ❌ Don't ship a private call unguarded — one OS update and every user crashes on launch.
- ✅ Do gate behind a runtime capability check and fall back to public behavior when the symbol is gone.

### One excellent example — guarded, evasion-aware, degrade-don't-crash

```swift
import AppKit
import ObjectiveC.runtime

/// Reads a private ivar off NSWindow without tripping the static KVC scanner,
/// and *degrades* (returns nil) if the symbol moved in a macOS update.
/// Legitimate for a Developer-ID app — never assume this clears App Review.
func privateThemeFrame(of window: NSWindow) -> NSView? {
    // Build the class name at runtime — no "_NSThemeFrame" string literal in the binary.
    let name = ["_NS", "Theme", "Frame"].joined()
    guard let themeFrameClass = NSClassFromString(name) else { return nil }   // symbol gone → degrade

    guard let contentView = window.contentView,
          let frame = contentView.superview,
          frame.isKind(of: themeFrameClass) else { return nil }

    // object_getIvar avoids value(forKey:) — the KVC path the static scanner reads.
    guard let ivar = class_getInstanceVariable(themeFrameClass, "_titlebarContainerView") else {
        return nil   // ivar renamed in this OS → degrade, don't crash
    }
    return object_getIvar(frame, ivar) as? NSView
}
```

```swift
// BAD foil — teaches the two failures this skill exists to prevent.
func privateThemeFrame_bad(of window: NSWindow) -> NSView {
    let frame = window.contentView!.superview!
    // 1. value(forKey:) is the exact KVC string the static scanner flags.
    // 2. Force-unwrap → the day Apple renames the ivar, EVERY user crashes on launch.
    return frame.value(forKey: "titlebarContainerView") as! NSView
}
```

The good version is **not** "now App-Store-safe" — runtime use is still detectable. It is *Developer-ID-safe and OS-update-resilient*. Keep those two claims separate.

---

## 4. Packaging hand-off & tone

The build/sign/notarize/staple mechanics live in **`appkit-packaging`** (Developer ID signing, `notarytool`, stapling, `.dmg`/`.pkg`, Sparkle, CI) — point there for the distribution end.

**Tone, always:**

- ❌ "You may not ship private APIs." / "This is against the rules."
- ✅ "Here's the trade-off and your options — App Store review is case-by-case; Developer ID + notarization ships it cleanly and you own the OS-update risk."

Inform, never gate. Surface this advisory **unprompted** the moment private-API or swizzling code could end up in a shipped build.

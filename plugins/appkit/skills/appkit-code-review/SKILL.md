---
name: appkit-code-review
description: "Use when reviewing native macOS AppKit Swift code before committing — checks MVC/MVVM, Swift 6 concurrency and main-actor correctness, memory management (retain cycles), target-action vs bindings, accessibility, theming, security, and performance, catching issues the compiler and UI tests won't find."
---

### When to Use

Run a code review **after the app builds and before committing**. This catches quality issues that aren't build errors and aren't visible in UI tests — patterns that compile and run but are wrong, fragile, or slow.

### How to Review

Read through the project's Swift files and check each section below. Lean on three layers of tooling first, then human judgment:

1. **Compiler warnings.** Build with warnings visible (`xcodebuild ... | xcpretty`, or read the raw log). In Swift 6 language mode, **data-race and main-actor isolation violations are diagnostics** — treat them as must-fix, not noise. Enable `-warnings-as-errors` in CI once clean.
2. **swift-format.** Lint against the project's own `.swift-format` (a JSON config you commit at the repo root, not a compiled binary — no unsigned artifact to ship/verify). `swift-format` is Apple's official formatter/linter; it ships inside the Xcode toolchain (also runnable as `swift format …`) and via `brew install swift-format`. Lint without rewriting files:
   ```bash
   swift-format lint --strict --recursive --configuration .swift-format Sources/
   ```
   (`--strict` makes any finding a non-zero exit for CI; drop it for advisory-only. To auto-apply formatting: `swift-format format --in-place --recursive Sources/`.) The config should enable the lint rules that matter most for AppKit correctness — `NeverForceUnwrap`, `NeverUseForceTry`, `NeverUseImplicitlyUnwrappedOptionals` — plus consistent formatting (import ordering, lowerCamelCase, early-exits, no semicolons). `NeverUseImplicitlyUnwrappedOptionals` is the one most likely to be noisy for programmatic AppKit's "set-in-`viewDidLoad`" properties — turn it off in the config if that pattern is intentional in your codebase.

   **swift-format has no custom-rule mechanism** (unlike the WinUI Roslyn analyzer or SwiftLint's `custom_rules`), so the AppKit-*semantic* pitfalls below aren't enforced by it — cover them with the manual checklist plus these quick `grep` passes:
   ```bash
   grep -rnE 'DispatchQueue\.main\.sync|\.wait\(\)' Sources/                 # main-thread blocking / deadlock
   grep -rnE 'NSColor\((red|calibratedRed|srgbRed|deviceRed):' Sources/       # hardcoded RGB (won't theme)
   grep -rnE 'NSFont\(name:' Sources/                                         # hardcoded font (ignores type ramp)
   grep -rnE '\bUI(View|ViewController|Color|Button|Label|TableView)\b' Sources/  # UIKit leaked into AppKit
   grep -rLE 'setAccessibilityIdentifier' Sources/**/*ViewController*.swift   # controllers missing a11y ids
   ```
3. **The Swift static analyzer / Instruments.** For deeper checks: `xcodebuild analyze` (clang/Swift static analysis), and Instruments (Leaks, Allocations, Time Profiler) when you suspect leaks or hot paths.

### Architecture (MVC / MVVM)

- [ ] View models hold no AppKit view types (`NSView`, `NSColor`, `NSImage`, `NSViewController`) — those belong in the view layer or small mappers
- [ ] Controllers (`NSViewController`/`NSWindowController`) do navigation, sheet/dialog coordination, and wiring — not business logic
- [ ] State exposed as plain values (`String`, `Bool`, enums); the controller binds it to controls
- [ ] `async`/`await` for async work; completion handlers only at framework boundaries
- [ ] Collections updated via diffable snapshots, not in-place array replacement on a live data source

### Swift 6 Concurrency & Main-Actor Correctness

- [ ] UI types and view-model entry points annotated `@MainActor`
- [ ] No UI mutation off the main actor; hop back with `await MainActor.run { }` or `@MainActor` methods
- [ ] No main-thread blocking: no `DispatchQueue.main.sync`, no semaphore `.wait()` on the main thread, no `.result`-style sync waits — these deadlock the UI
- [ ] Heavy/IO work runs off the main actor (`Task.detached` / `await someActor.work()`), results applied on `@MainActor`
- [ ] `Sendable` respected across actor boundaries; no captured non-`Sendable` mutable state in concurrent closures
- [ ] No data races flagged by the Swift 6 checker left unaddressed

### Memory Management

- [ ] No retain cycles: `[weak self]` in escaping closures that outlive the call; `weak` delegates and target references where Cocoa expects them
- [ ] `NSWindowController`/top-level controllers retained for their lifetime (premature dealloc → window vanishes)
- [ ] Observers removed (`NotificationCenter`, KVO) on deinit if not using the block/`NSKeyValueObservation` token form
- [ ] Timers (`Timer`, `DispatchSourceTimer`) invalidated/cancelled; no strong `target` cycles
- [ ] Closures stored on long-lived objects don't strongly capture views/controllers unnecessarily

### Accessibility

- [ ] `setAccessibilityIdentifier` on every interactive control — unique and stable (UI tests depend on it)
- [ ] `setAccessibilityLabel` on icon-only controls / controls without visible text
- [ ] Semantic controls (`NSButton`, `NSPopUpButton`, …) rather than click handlers on plain views
- [ ] Keyboard operable end-to-end (`nextKeyView` loop, `keyEquivalent`s); focus ring visible
- [ ] No meaning conveyed by color alone

### Theming

- [ ] Semantic `NSColor`s / asset-catalog named colors only — no hardcoded RGB for chrome
- [ ] System text styles, not hardcoded fonts, for standard labels
- [ ] Materials for translucency (`NSVisualEffectView`; `NSGlassEffectView` on Tahoe, gated)
- [ ] Spacing/sizing on the 4/8 pt scale; system `controlSize`

### Security

- [ ] No secrets/API keys/tokens in source — use **Keychain** (`SecItem*` / a wrapper) for credentials
- [ ] App Sandbox / hardened runtime entitlements scoped to what's actually needed (least privilege)
- [ ] User-selected file access via `NSOpenPanel`/`NSSavePanel` + **security-scoped bookmarks**, not raw absolute paths
- [ ] External input validated/sanitized before use; no shelling out with unsanitized input (`Process` args, never a shell string)
- [ ] Networking over HTTPS (App Transport Security on); no disabling TLS validation
- [ ] `WKWebView` (if used) hardened: untrusted content isolated, JS disabled where not needed, navigation restricted
- [ ] No logging of PII/tokens/passwords

### Performance

- [ ] Long/dynamic lists use `NSTableView`/`NSOutlineView`/`NSCollectionView` (view recycling) — not a giant stack of views
- [ ] Cell views reused (view-based recycling), not rebuilt per reload
- [ ] Off-main work for parsing/IO/compute; UI never blocked
- [ ] Expensive results cached; images downsampled to display size before assignment
- [ ] `layoutSubtreeIfNeeded`/forced layout not called in hot paths; constraints not churned per frame
- [ ] `using`-equivalent resource cleanup (`defer`, scoped `FileHandle`/streams) for disposables

### Localization

- [ ] User-facing strings via `String(localized:)` / a string catalog (`.xcstrings`) — not hardcoded
- [ ] Dates/numbers via `FormatStyle` / `DateFormatter`+`NumberFormatter` with the current locale — not manual formats
- [ ] Layout uses leading/trailing anchors and adapts to RTL (`userInterfaceLayoutDirection`)
- [ ] No string concatenation for user-facing messages — use interpolation with localized format strings and pluralization rules

### Review Report

After reviewing, summarize:
1. **Issues found:** each with file, line, and what's wrong
2. **Severity:** Error (must fix), Warning (should fix), Note (could improve)
3. **Suggested fixes:** a concrete Swift change for each

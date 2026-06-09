---
name: appkit-migration
description: "Migrate apps to native macOS AppKit + Swift — Mac Catalyst / UIKit → AppKit (UIView→NSView, UIViewController→NSViewController, UITableView→NSTableView, UICollectionView→NSCollectionView, UINavigationController→NSSplitViewController/NSToolbar, UIColor→NSColor), Electron/web → AppKit, and Objective-C → Swift. Use when converting a Catalyst, UIKit, Electron, or Objective-C app to native AppKit, mapping UIKit types, or fixing migration build errors."
---

### Pick the migration

Three very different starting points land here. Identify which one you're doing — the work is not the same:

- **Mac Catalyst / UIKit → AppKit.** A UIKit codebase (Catalyst-on-Mac, or an iPad app) becoming a true AppKit app. Mostly a **type-and-idiom remap** (UIKit class → AppKit class) plus reworking navigation, which has no direct AppKit equivalent.
- **Electron / web → AppKit.** A rewrite, not a port: the JS/HTML UI is replaced by AppKit; only domain logic and assets carry over. Plan it as a new AppKit app (use `appkit-design` + `appkit-dev-workflow`) that reuses the backend.
- **Objective-C → Swift (already AppKit).** Same framework, new language. Migrate **file by file** behind the Obj-C/Swift bridging header; AppKit APIs stay the same.

This is the macOS analog of WinUI's WPF/Electron migration skill.

---

## Mac Catalyst / UIKit → AppKit

### Step 1: Audit the UIKit source
Inventory UIKit-specific APIs before writing code:
```bash
grep -rEn '\bUI[A-Z][A-Za-z]+' --include='*.swift' . | grep -v '/build/' | sort | uniq -c | sort -rn | head -60
```
List the controls used, the navigation model (nav controller / tab bar / modal presentation), custom views, gesture/touch handling, and any `#if targetEnvironment(macCatalyst)` branches (those hint at where AppKit-specific behavior already had to be bolted on).

### Step 2: Scaffold a native AppKit project
Create a programmatic AppKit app (`appkit-dev-workflow`: `Project.swift` + `tuist generate`), set the deployment target, and get an empty window building **before** porting any screen. Keep the old project to read from; don't edit in place.

### Step 3: Map the types

| UIKit | AppKit | Notes |
|---|---|---|
| `UIView` | `NSView` | `NSView` is not flipped by default — origin is bottom-left; override `isFlipped` for top-left layout |
| `UIViewController` | `NSViewController` | lifecycle differs: `viewDidLoad`/`viewWillAppear` exist; no `view(safeArea)` the same way |
| `UIWindow` | `NSWindow` (+ `NSWindowController`) | a window is heavier on macOS; pair with a controller |
| `UILabel` | `NSTextField` (label style: `isEditable=false`, `isBordered=false`, `drawsBackground=false`) | or `NSTextField(labelWithString:)` |
| `UIButton` | `NSButton` | set `bezelStyle`; for icon buttons use `image` + `imagePosition` |
| `UITextField` | `NSTextField` | commit on end-editing, not per keystroke (set `isContinuous` if needed) |
| `UITextView` | `NSTextView` inside an `NSScrollView` | text view doesn't scroll itself |
| `UISwitch` | `NSSwitch` | macOS 10.15+ |
| `UISegmentedControl` | `NSSegmentedControl` | |
| `UISlider` | `NSSlider` | |
| `UIStepper` | `NSStepper` | |
| `UIProgressView` / `UIActivityIndicatorView` | `NSProgressIndicator` (bar / spinning) | one class, `style` switches |
| `UITableView` | `NSTableView` (view-based, in an `NSScrollView`) | for a plain list use a single column; data source/delegate idioms differ |
| `UICollectionView` | `NSCollectionView` | use `NSCollectionViewCompositionalLayout` |
| (tree / outline) | `NSOutlineView` | no UIKit equivalent; native on macOS |
| `UINavigationController` | `NSSplitViewController` (sidebar→detail) **or** push-as-replace in a content view + `NSToolbar` back item | **no drill-down nav on macOS** — rethink as master/detail or toolbar-driven |
| `UITabBarController` | `NSTabViewController` (toolbar style) or a source-list sidebar | |
| modal `present(_:)` | a **sheet** (`window.beginSheet`) or a separate window/`NSPanel` | |
| `UIAlertController` | `NSAlert` | |
| `UIMenu` / context menu | `NSMenu` | |
| `UIColor` | `NSColor` | use semantic colors (`.labelColor`, `.controlAccentColor`, …) |
| `UIFont` | `NSFont` | `preferredFont`/`systemFont` text styles |
| `UIImage` | `NSImage` | SF Symbols: `NSImage(systemSymbolName:accessibilityDescription:)` |
| `UIBezierPath` | `NSBezierPath` | API nearly identical |
| `Auto Layout` (`NSLayoutConstraint`/anchors) | **same** | constraints/anchors port directly — the one thing that stays |
| `UIStackView` | `NSStackView` | |
| `UIGestureRecognizer` | `NSGestureRecognizer` (`NSClickGestureRecognizer`, …) | mouse, not touch; also consider overriding `mouseDown`/`mouseDragged` |
| `viewController.traitCollection` (dark mode) | `NSApp.effectiveAppearance` / `view.effectiveAppearance` | observe appearance changes via `viewDidChangeEffectiveAppearance` |

### Step 4: Rework navigation (the real work)
UIKit drill-down navigation has **no AppKit equivalent**. Don't emulate a nav stack — re-express the app's structure:
- list → detail becomes an `NSSplitViewController` (sidebar/list pane + detail pane).
- a flow of full-screen steps becomes content-view replacement driven by a toolbar or segmented control, or a sequence of sheets.
- mod/tab structure becomes a source-list sidebar or `NSTabViewController`.
See `appkit-design` Step 1 for the app-type → shell mapping.

### Step 5: Fix coordinate-system and event differences
- `NSView` origin is **bottom-left**; if you laid out with top-left math, set `override var isFlipped { true }` on container views.
- Touch handling (`touchesBegan`) → mouse handling (`mouseDown`/`mouseUp`/`mouseDragged`) or gesture recognizers.
- No `safeAreaInsets` the same way; use the window's layout margins / `contentLayoutGuide` and toolbar/sidebar safe areas (esp. for Tahoe edge-to-edge glass).

### Step 6: Concurrency & idioms
Adopt Swift 6 main-actor isolation for UI types (see `appkit-code-review`). Replace `DispatchQueue.main.async` UI hops with `@MainActor` methods / `await MainActor.run`. Keep domain/model code as-is where it's already platform-agnostic.

### Critical Rules (UIKit → AppKit)
- ❌ Don't try to recreate `UINavigationController` push/pop — use split view / toolbar / sheets.
- ❌ Don't assume top-left origin — handle `isFlipped`.
- ❌ Don't keep `#if targetEnvironment(macCatalyst)` shims — you're native AppKit now; delete them.
- ✅ Auto Layout constraints carry over; lean on them.
- ✅ Port screen-by-screen, building after each; don't do one giant rewrite.

---

## Electron / web → AppKit

This is a **rewrite of the UI**, so treat it as a new AppKit app that reuses logic, not a line-by-line port.

1. **Separate logic from UI.** Identify the domain/business logic in the JS. If it's portable algorithmically, reimplement in Swift; if it's a substantial engine, consider keeping it as a local service/CLI the app talks to, or porting incrementally.
2. **Rebuild the UI in AppKit** using `appkit-design` (real controls, HIG, Liquid Glass) — don't wrap the web app in a `WKWebView` and call it native; that keeps every Electron downside.
3. **Map web idioms to AppKit:**

| Web / Electron | AppKit |
|---|---|
| HTML form controls | native `NSTextField` / `NSPopUpButton` / `NSButton` / `NSSwitch` / … |
| CSS flexbox/grid layout | Auto Layout (`NSStackView`, constraints) |
| routing / SPA views | `NSSplitViewController` / `NSTabViewController` / view swapping |
| `BrowserWindow` | `NSWindow` + `NSWindowController` |
| Electron `Menu` / tray | `NSMenu` (main menu, `NSStatusItem` for the menu-bar extra) |
| `ipcRenderer`/`ipcMain` | direct Swift calls / `NotificationCenter` / a service layer |
| `fs` access | `FileManager` + `NSOpenPanel`/`NSSavePanel` + security-scoped bookmarks |
| notifications | `UNUserNotificationCenter` |
| auto-update (Squirrel) | Sparkle (Developer ID) or the App Store update mechanism |
| `localStorage` / config | `UserDefaults`, or files in Application Support |

4. **Reuse assets** (icons, images) but regenerate the **app icon** at macOS sizes and the **SF Symbols** equivalents for toolbar/menu glyphs.
5. **Distribute** via `appkit-packaging` (Developer ID + notarization, or the App Store) — not an Electron installer.

### Critical Rules (Electron → AppKit)
- ❌ Don't ship a `WKWebView` shell as "native" — rebuild the UI in AppKit.
- ✅ Keep portable domain logic; rewrite only the presentation layer.

---

## Objective-C → Swift (already AppKit)

Same framework, new language — migrate **incrementally** behind the bridging header.

1. **Set up bridging.** A mixed target uses an Obj-C **bridging header** (Swift seeing Obj-C) and the generated `-Swift.h` (Obj-C seeing Swift). In Tuist, set `SWIFT_OBJC_BRIDGING_HEADER` in the target's `settings:`. New Swift files can call existing Obj-C immediately.
2. **Migrate leaf files first.** Convert classes with the fewest dependents (models, utilities), one at a time; build after each. Keep the Obj-C version until the Swift one compiles and tests pass, then delete it.
3. **Translate idioms:**

| Objective-C | Swift |
|---|---|
| `@property (nonatomic, strong)` | `var` (strong by default) |
| `@property (weak)` delegate | `weak var delegate:` |
| nullable/`_Nullable` | optionals (`?`) — audit each for true nullability |
| `NSArray`/`NSDictionary` | `Array`/`Dictionary` with concrete element types |
| `id` | a concrete type or protocol; `Any` only as a last resort |
| manual `respondsToSelector:` | optional protocol requirements / `?.` |
| `dispatch_async(dispatch_get_main_queue(), …)` | `await MainActor.run { }` / `@MainActor` |
| KVO via `observeValueForKeyPath:` | `NSKeyValueObservation` (`observe(_:options:changeHandler:)`) |
| target-action `@selector(...)` | `#selector(...)` (keep `@objc` on the action method) |
| `#define` constants | `let` / `enum` |
| error via `NSError**` | `throws` / `Result` |

4. **Keep `@objc` where Cocoa needs it.** Selectors (target-action, menu validation, KVC/KVO, NSToolbar/NSMenu items) require `@objc` on the Swift method/property. Don't strip it just because Swift allows omitting it.
5. **Adopt Swift 6 concurrency last**, once files are in Swift — annotate UI types `@MainActor` and resolve isolation diagnostics (see `appkit-code-review`).

### Critical Rules (Obj-C → Swift)
- ✅ Migrate file-by-file behind the bridging header; build/test after each.
- ✅ Audit `_Nullable`/`id` — don't blindly make everything non-optional or `Any`.
- ✅ Keep `@objc` on anything reached by selector/KVO/Cocoa bindings.

---

## Post-Migration Validation

```bash
# No UIKit left (UIKit→AppKit migration)
grep -rEn '\bimport UIKit\b|\bUI(View|ViewController|Color|Button|Label|TableView)\b' --include='*.swift' . | grep -v '/build/'

# Build and run
./BuildAndRun.sh
```
Then run `appkit-ui-testing` to confirm behavior and `appkit-code-review` for quality (concurrency, memory, accessibility, theming). Visual-check the window against the `appkit-ui-testing` Step 3.5 checklist — migrated layouts often need resizing per `appkit-design` Step 4.

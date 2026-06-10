# Design Anti-Patterns

The full catalog of AppKit design mistakes a capable agent makes from memory — each paired with the verified, corpus-grounded correction.

HIG anchors: [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) · [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) · [Color](https://developer.apple.com/design/human-interface-guidelines/color) · [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views) · [Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures). Every symbol below is verified with `appkit-api`; align every "when to use" with the cited page.

> **The trap:** you reach for the right control name from memory, then ship the part that actually breaks — an invented or wrong symbol, a false equivalence (`.inset` = glass), a hardcoded frame, zero accessibility identifiers. The corrections are SDK-verified, not recalled.

## The catalog — ❌ Don't / ✅ Do

| # | ❌ Anti-pattern | ✅ Correction | Deep-dive · corpus id |
|---|----------------|---------------|------------------------|
| 1 | Cell-based `NSTableView` (`NSCell`, `setObjectValue:`, `dataCell`) | View-based: `makeView(withIdentifier:owner:)` vending `NSTableCellView`, wire `cell.textField` | `control-selection.md` · `tableview-view-based-reuse` |
| 2 | Bare `NSSplitView` with hand-set dividers/thickness | `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)` | `app-type-anchors.md` · `splitviewcontroller-sidebar-inspector` |
| 3 | Hardcoded color (`NSColor(red:green:blue:)`, hex) | Semantic: `.labelColor`, `.secondaryLabelColor`, `.controlAccentColor`, `.textBackgroundColor`, `.controlBackgroundColor`, `.separatorColor`, `.windowBackgroundColor` | `semantic-color.md` · `semantic-nscolor-system-colors` |
| 4 | Literal `NSFont.systemFont(ofSize: 13)` for content text | Semantic `NSFont.preferredFont(forTextStyle: .body)` (AppKit adds optional `options:`, default `[:]`) | `typography.md` · `semantic-font-text-style` |
| 5 | "Implicit glass" — claiming `tableView.style = .inset` or "a sidebar" is Liquid Glass | Explicit `if #available(macOS 26, *)` → `NSGlassEffectView` / `NSVisualEffectView` material **and** a populated `NSToolbar` | `liquid-glass.md` · `glass-effect-view-basic` |
| 6 | Hardcoded window frame (`NSRect(x:y:width:900,height:640)`) | Content-derived: size from `fittingSize` / Auto Layout, set `contentMinSize`, `window.center()` | `window-sizing.md` · `windowcontroller-content-viewcontroller` |
| 7 | `override func mouseDown(with:)` to make a view clickable | Target-action on a control, or `NSClickGestureRecognizer` / `NSPanGestureRecognizer` via `addGestureRecognizer(_:)` | `control-selection.md` · `gesture-recognizers-basics` |
| 8 | No accessibility identifier on interactive controls | `control.setAccessibilityIdentifier("saveButton")` — distinct from the VoiceOver **label** | `accessibility.md` · `accessibility-identifier-ui-testing` |
| 9 | Custom `NSView` reimplementing a standard control (drawn "button", hand-rolled disclosure, bespoke list) | The standard control: `NSButton`, `NSOutlineView`, view-based `NSTableView`, `NSSwitch`, `NSPopUpButton` | `control-selection.md` · `tableview-view-based-reuse` |

### Identifier ≠ Label (anti-pattern #8, the most-skipped)

Two different `NSAccessibilityProtocol` methods, both needed:

| Method | Purpose | Min macOS |
|--------|---------|-----------|
| `setAccessibilityIdentifier(_:)` | Stable string for **UI testing** (`appkit-ui-testing` queries it) — not spoken | 10.10 |
| `setAccessibilityLabel(_:)` | Spoken **VoiceOver** label | 10.10 |
| `NSImage.accessibilityDescription` | VoiceOver text for an image / SF Symbol | 10.6 |

Baselines set a label and call it done, or set neither. Set the identifier on every interactive control.

## Top 3, corrected — adapted from the corpus

### #1 Cell-based → view-based `NSTableView`

HIG [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables): use a table for structured rows the user scans or sorts. The identifier you pass to `makeView` must match the cell's `identifier`, or reuse silently breaks and you allocate a view per row.

```swift
import AppKit

// ❌ BAD — cell-based: NSCell, dataCell, objectValue plumbing (legacy, no Auto Layout per row)
//   column.dataCell = NSTextFieldCell(); tableView.usesAlternatingRowBackgroundColors = true
//   func tableView(_:objectValueFor:row:) -> Any? { people[row] }

// ✅ GOOD — view-based reuse via makeView(withIdentifier:owner:) → NSTableCellView
final class PeopleTableController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
  let tableView = NSTableView()
  var people: [String] = ["Ada", "Grace", "Alan"]
  private let cellID = NSUserInterfaceItemIdentifier("NameCell")

  func numberOfRows(in tableView: NSTableView) -> Int { people.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
      let view = NSTableCellView()
      let text = NSTextField(labelWithString: "")
      text.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(text)
      view.textField = text                 // wire the outlet so selection/backgroundStyle work
      view.identifier = cellID              // MUST equal the makeView identifier or reuse breaks
      NSLayoutConstraint.activate([
        text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
        text.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      return view
    }()
    cell.textField?.stringValue = people[row]
    cell.setAccessibilityIdentifier("person.\(row)")   // UI-test hook (anti-pattern #8)
    return cell
  }
}
```

### #5 Fake glass → explicit, gated `NSGlassEffectView`

HIG [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): use materials to convey hierarchy; avoid stacking glass on glass. `.inset` is a **table style**, not Liquid Glass. `NSVisualEffectView` (10.10) gives vibrancy in places — that predates Liquid Glass and is **not** adoption. Adoption means gating on `macOS 26` and reaching for `NSGlassEffectView` (26.0), plus a real, populated toolbar.

```swift
import AppKit

// ❌ BAD — asserting glass you never adopt; empty toolbar renders nothing
//   tableView.style = .inset                 // a table style, NOT glass
//   window.toolbar = NSToolbar()             // no items → no chrome

// ✅ GOOD — explicit adoption, version-gated, with a pre-26 vibrancy fallback
@MainActor
final class GlassCardController: NSViewController {
  override func loadView() {
    let label = NSTextField(labelWithString: "Liquid Glass")
    label.font = NSFont.preferredFont(forTextStyle: .title2, options: [:])  // options: defaults to [:]
    label.textColor = .labelColor                                           // semantic, not hex
    label.translatesAutoresizingMaskIntoConstraints = false

    if #available(macOS 26, *) {
      let glass = NSGlassEffectView()                  // 26.0 — gate it
      glass.cornerRadius = 16                           // set on the glass, not a clipping layer
      glass.tintColor = .controlAccentColor.withAlphaComponent(0.15)
      glass.contentView = label                         // assign — never addSubview
      view = glass
    } else {
      let fallback = NSVisualEffectView()               // 10.10 — vibrancy, not glass
      fallback.material = .menu                          // pick by role, not to fake a color
      fallback.blendingMode = .behindWindow
      fallback.state = .followsWindowActiveState
      fallback.addSubview(label)
      NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: fallback.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: fallback.centerYAnchor),
      ])
      view = fallback
    }
  }
}
```

`NSGlassEffectView.effectIsInteractive` is **27.0** — gate it separately if you use it.

### #4 Hardcoded font → semantic text style

HIG [Typography](https://developer.apple.com/design/human-interface-guidelines/typography): favor built-in semantic text styles so text inherits system metrics, weight, and accessibility scaling. AppKit's signature adds an `options:` parameter (default `[:]`), so `preferredFont(forTextStyle: .body)` and `preferredFont(forTextStyle: .body, options: [:])` both compile (UIKit has no `options:`). `NSFont.TextStyle` is a struct (11.0+): `.body`, `.title1`, `.headline`, etc.

```swift
// ❌ BAD — literal point size: ignores the system ramp, weight, accessibility scaling
label.font = NSFont.systemFont(ofSize: 13)

// ✅ GOOD — semantic style (options: defaults to [:]; supply it for tracking, etc.)
title.font   = NSFont.preferredFont(forTextStyle: .title2, options: [:])
body.font    = NSFont.preferredFont(forTextStyle: .body,   options: [:])
caption.font = NSFont.preferredFont(forTextStyle: .caption1, options: [:])

// ✅ ACCEPTABLE — explicit weight ONLY when no text style models the role
badge.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
```

## Quick rules

- ❌ `NSCell` / `dataCell` tables → ✅ view-based `makeView` + `NSTableCellView`.
- ❌ Bare `NSSplitView` → ✅ `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)`.
- ❌ Literal RGB/hex → ✅ semantic `NSColor`. ❌ `ofSize:` literal → ✅ `preferredFont(forTextStyle:options:)`.
- ❌ `.inset`/"a sidebar" called glass → ✅ `if #available(macOS 26, *)` + `NSGlassEffectView` + populated toolbar.
- ❌ Magic window frame → ✅ `fittingSize` + `contentMinSize`. ❌ `mouseDown` override → ✅ target-action / gesture recognizer.
- ❌ No `setAccessibilityIdentifier` → ✅ one per interactive control (and it is **not** the VoiceOver label).
- ❌ Custom view reimplementing a standard control → ✅ the standard control (`NSButton`, `NSOutlineView`, `NSSwitch`, `NSPopUpButton`).

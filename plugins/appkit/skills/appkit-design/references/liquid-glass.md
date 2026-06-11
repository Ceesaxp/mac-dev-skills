# Liquid Glass & Materials (macOS 26/27)

Adopt the macOS 26/27 look explicitly with availability gates — implicit vibrancy is not adoption.

HIG: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [Layout](https://developer.apple.com/design/human-interface-guidelines/layout). Use system materials and coherent rounded geometry to convey hierarchy; never custom blur stacks, opaque overlays, or hand-tuned radius math. Avoid stacking glass on glass — it muddies legibility.

## Version table

Every modern symbol must be `@available`/`if #available` gated. Verified with `sdk-api availability`.

| Symbol | Min macOS | Gate required |
|---|---|---|
| `NSVisualEffectView` | 10.10 | no |
| `NSFont.preferredFont(forTextStyle:options:)` | 11.0 | no |
| `NSGlassEffectView` | **26.0** | yes |
| `NSGlassEffectContainerView` | **26.0** | yes |
| `NSBackgroundExtensionView` | **26.0** | yes |
| `NSButton.BezelStyle.glass` | **26.0** | yes |
| `NSScrollEdgeEffectStyle` (+ `.soft`/`.hard`/`.automatic`) | **26.1** | yes |
| `…AccessoryViewController.preferredScrollEdgeEffectStyle` | **26.1** | yes |
| `NSGlassEffectView.effectIsInteractive` | **27.0** | yes |
| `NSView.cornerConfiguration` | **27.0** | yes |
| `NSViewCornerConfiguration` (`.uniformCorners(radius:)`) | **27.0** | yes |
| `NSViewCornerRadius.containerConcentric` | **27.0** | yes |
| `NSView.effectiveCornerRadii` → `NSViewCornerRadii?` | **27.0** | yes |

> `NSFont.preferredFont(forTextStyle:options:)` adds an `options:` parameter (default `[:]`), so `preferredFont(forTextStyle: .body)` also compiles (UIKit has no `options:`). `NSFont.TextStyle` is a struct (11.0+): `.body`, `.title1`, `.title2`, `.headline`.

## When to use which

| Need | Use | Min macOS |
|---|---|---|
| Floating, content-forward glass chrome (cards, panels, overlays) | `NSGlassEffectView` | 26.0 |
| Window / sidebar / header / HUD vibrancy by **semantic role** | `NSVisualEffectView` + `.material` | 10.10 |
| Merge several adjacent glass shapes into one continuous surface | `NSGlassEffectContainerView` | 26.0 |
| Concentric nested corners that track a rounded ancestor | `NSView.cornerConfiguration` + `.containerConcentric` | 27.0 |
| Titlebar / split-view accessory scroll-edge fade | `NSScrollEdgeEffectStyle` on accessory controller | 26.1 |
| Glass-bezeled control with semantic tint | `NSButton.bezelStyle = .glass` | 26.0 |

❌ **Don't** `addSubview` onto an `NSGlassEffectView` — it manages its own hierarchy.
✅ **Do** assign your view to `contentView` and set `cornerRadius` on the glass view (not a clipping layer) so the edge stays crisp.

❌ **Don't** pick a material to fake a color (`.sidebar` for "gray").
✅ **Do** pick by role (`.sidebar`, `.headerView`, `.menu`, `.hudWindow`); the system adapts it per appearance and `state = .followsWindowActiveState`.

### GOOD: wrap content in glass, gated (adapted from `glass-effect-view-basic`)

```swift
import AppKit

@MainActor
final class GlassCardController: NSViewController {
  override func loadView() {
    let label = NSTextField(labelWithString: "Liquid Glass")
    label.font = .preferredFont(forTextStyle: .title2)        // options: defaults to [:]
    label.translatesAutoresizingMaskIntoConstraints = false

    if #available(macOS 26, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = 16
      glass.tintColor = .controlAccentColor.withAlphaComponent(0.15) // semantic, not hex
      glass.contentView = label                                // NOT addSubview
      view = glass
    } else {
      // Pre-26 fallback: vibrancy, not glass adoption.
      let fallback = NSVisualEffectView()
      fallback.material = .menu
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

### Merging adjacent glass (adapted from `glass-effect-container-merging`)

```swift
@available(macOS 26, *)
@MainActor
func makeMergedGlassToolbar(buttons: [NSView]) -> NSGlassEffectContainerView {
  let container = NSGlassEffectContainerView()
  container.spacing = 12                 // merge DISTANCE between glass shapes, not padding
  let row = NSStackView(views: buttons.map { content in
    let glass = NSGlassEffectView()
    glass.contentView = content
    glass.cornerRadius = 12
    return glass
  })
  row.orientation = .horizontal
  row.spacing = 8
  container.contentView = row
  return container
}
```

A container only earns its keep when shapes should *merge*; a single `NSGlassEffectView` needs none.

## Concentric corners (27.0)

Set an explicit radius on the rounded ancestor (e.g. `glass.cornerRadius`). `NSView.cornerConfiguration` is **read-only** — a nested child declares its corner style by **overriding the getter** (never by assignment), so inner and outer curves share a center with no `parentRadius - inset` math:

```swift
@available(macOS 27, *)
final class ConcentricHeader: NSView {
  override var cornerConfiguration: NSViewCornerConfiguration? {
    .uniformCorners(radius: .containerConcentric)
  }
}
```

Reading effective radii — `effectiveCornerRadii` is **read-only** (`NSViewCornerRadii?`); observe, never assign. Override `viewDidChangeEffectiveCornerRadii()` (call `super`) to react; use `invalidateCornerConfiguration()` only for changes AppKit can't observe.

```swift
@available(macOS 27, *)
override func viewDidChangeEffectiveCornerRadii() {
  super.viewDidChangeEffectiveCornerRadii()
  if let radii = effectiveCornerRadii {          // .topLeft/.topRight/.bottomLeft/.bottomRight
    layer?.cornerRadius = radii.topLeft
    needsDisplay = true
  }
}
```

`.containerConcentric` resolves to a non-zero radius only when an ancestor actually defines a corner radius; with no rounded ancestor it renders square.

## Scroll edge effects (26.1)

Set `preferredScrollEdgeEffectStyle` on a **titlebar or split-view accessory view controller**, not on the scroll view. `.hard` keeps floating content crisp; `.soft` gives a gentle fade; `.automatic` defers to the system.

```swift
@available(macOS 26.1, *)
@MainActor
func installScrollEdgeAccessory(in window: NSWindow, sidebarItem: NSSplitViewItem) {
  let titlebar = NSTitlebarAccessoryViewController()
  titlebar.layoutAttribute = .top
  titlebar.view = NSView()
  titlebar.preferredScrollEdgeEffectStyle = .hard
  window.addTitlebarAccessoryViewController(titlebar)

  let sidebarAccessory = NSSplitViewItemAccessoryViewController()
  sidebarAccessory.view = NSView()
  sidebarAccessory.preferredScrollEdgeEffectStyle = .soft
  sidebarItem.addTopAlignedAccessoryViewController(sidebarAccessory)
}
```

## Not Liquid Glass adoption

❌ `tableView.style = .inset` — `.inset` is a **table style**, not glass.
❌ Adding "a sidebar" / an `NSVisualEffectView` — that gives **vibrancy** in places; it predates Liquid Glass (10.10) and is not the same as adopting `NSGlassEffectView` (26.0).
✅ Adoption = gating on `if #available(macOS 26, *)` and reaching for `NSGlassEffectView` / `NSGlassEffectContainerView` / `.glass` bezels, with 27.0 concentric corners where content nests.

Sidebars still use `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)`, never a bare `NSSplitView`. Glass changes the *material*, not the structure.

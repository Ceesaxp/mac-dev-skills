# Window Sizing

Size a window from its content, not a magic frame — let the `contentViewController` drive the size so the window fits its layout on every display.

HIG: [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) (and [Split Views](https://developer.apple.com/design/human-interface-guidelines/split-views) for multi-pane). The HIG favors standard, content-fitting windows so people can predict where navigation and commands live; a window should open at a size that shows its content without clipping or wasted chrome.

## The rubric

Derive the size; do not hardcode a `contentRect`. A fixed frame clips on small displays and wastes space on large ones, and breaks the moment fonts, locale, or Dynamic Type change the layout.

| Step | Do this |
|---|---|
| Source of truth | The `contentViewController`'s Auto Layout. Set its constraints, then read `view.fittingSize`. |
| Apply | `window.setContentSize(_:)` from the derived size, or set `viewController.preferredContentSize` and let the window adopt it. |
| Floor | `window.contentMinSize` = the smallest the layout stays usable (derive from `fittingSize`, not a guess). |
| Ceiling | `window.contentMaxSize` only when content genuinely shouldn't grow (e.g. a fixed form). Resizable content needs none. |
| Round | Round the derived size **up**. Clipping is worse than a few points of slack. |
| Persist | `setFrameAutosaveName(_:)` so the user's resize survives relaunch — never re-impose the derived size after first launch. |

`fittingSize` returns the smallest size satisfying the view's constraints (the Auto Layout fitting size). `preferredContentSize` lets the controller advertise a size the enclosing window/popover honors. There is **no** `systemLayoutSizeFitting(_:)` in AppKit — that is UIKit; use `fittingSize`.

| Symbol | Use for |
|---|---|
| `NSView.fittingSize` | Read the content's derived size after constraints are set. |
| `NSViewController.preferredContentSize` | Advertise a size the window/popover adopts. |
| `NSWindow.setContentSize(_:)` | Apply a derived size to the window's content area. |
| `NSWindow.contentMinSize` / `contentMaxSize` | Clamp the **content** area (not the framed window). |
| `NSWindow.setFrameAutosaveName(_:)` | Remember the user's chosen frame across launches. |
| `NSView.noIntrinsicMetric` (10.11+) | Sentinel when a view declares only one intrinsic axis. |

## GOOD vs BAD

❌ **Don't** hardcode a frame — it clips when the label wraps or the locale lengthens text:

```swift
// BAD: magic numbers, no relation to content. Clips on smaller text scales,
// wastes space on larger ones, and ignores the contentViewController entirely.
let window = NSWindow(
  contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
  styleMask: [.titled, .closable, .resizable],
  backing: .buffered, defer: false)
window.contentView = MyView()   // size and content now disagree
```

✅ **Do** let the `contentViewController` drive the size (adapted from the corpus `windowcontroller-content-viewcontroller` pattern):

```swift
import AppKit

@MainActor
final class EditorWindowController: NSWindowController {

  convenience init() {
    // A resizable window with no pre-baked contentRect. Style mask only —
    // the size comes from the content, applied in windowDidLoad().
    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    self.init(window: window)
    window.setFrameAutosaveName("EditorWindow")  // user's resize wins after launch
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    guard let window else { return }

    // The contentViewController owns the layout — it is the source of truth.
    let content = EditorViewController()
    window.contentViewController = content   // window now hosts the controller's view

    // Force a layout pass so fittingSize reflects the real constraints
    // (fonts, locale, Dynamic Type all already applied).
    let view = content.view
    view.layoutSubtreeIfNeeded()
    let derived = view.fittingSize          // the smallest size the layout needs

    // Round UP — a clipped control is worse than a few points of slack.
    let size = NSSize(width: ceil(derived.width), height: ceil(derived.height))
    window.setContentSize(size)             // apply derived size to the content area
    window.contentMinSize = size            // do not let the user shrink past usable

    window.center()                         // sensible first-launch placement
  }
}

@MainActor
final class EditorViewController: NSViewController {
  override func loadView() { view = NSView() }

  override func viewDidLoad() {
    super.viewDidLoad()
    let field = NSTextField(labelWithString: "Document title")
    field.font = .preferredFont(forTextStyle: .title2, options: [:])  // semantic font
    field.textColor = .labelColor                                     // semantic color
    field.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(field)

    // Constraints pin content to all four edges, so fittingSize is well-defined.
    NSLayoutConstraint.activate([
      field.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      field.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }
}
```

The semantic font call is `NSFont.preferredFont(forTextStyle:options:)`; `options:` defaults to `[:]`, so `preferredFont(forTextStyle: .body)` also compiles (UIKit has no `options:`).

## Sanity ranges

Derive the size from the layout, then sanity-check it against these heuristics. They are **ranges to validate against, not targets to hardcode** — if your derived size lands far outside, re-examine the constraints, don't paste a number.

| Window kind | Content-area heuristic | Notes |
|---|---|---|
| Single-purpose utility (palette, mini-tool) | ~240–360 × 200–400 pt | Often non-resizable; `contentMinSize == contentMaxSize`. |
| Form / single-page tool | ~400–560 × 320–520 pt | Fixed width, height grows with fields. Cap with `contentMaxSize` only if truly fixed. |
| Multi-pane (sidebar + content) | ~720–1000 × 480–700 pt | Width is the sum of pane `minimumThickness` values plus slack; see `splitviewcontroller-sidebar-inspector`. |
| Document / canvas | ~800–1200 × 600–860 pt, resizable | No `contentMaxSize`; large `contentMinSize` floor; always `setFrameAutosaveName`. |

For multi-pane windows the derived floor is the sum of each `NSSplitViewItem.minimumThickness` (e.g. sidebar 180 + content 260 + inspector 220 = 660 pt minimum content width). Use that sum as `contentMinSize.width` rather than a round number — it guarantees no pane collapses below its usable threshold.

## Pitfalls

- Read `fittingSize` **after** `layoutSubtreeIfNeeded()` — before the first layout pass it is `.zero` or stale.
- Set `contentMinSize`/`contentMaxSize` (content area), not `minSize`/`maxSize` (the framed window incl. titlebar) unless you specifically mean the frame.
- `fittingSize` is `.zero` if the content view has no constraints pinning it on both axes — the layout has no defined size to derive. Pin content to all four edges.
- Don't re-apply the derived size on every `windowDidLoad` if a frame autosave exists; AppKit restores the saved frame, and overwriting it discards the user's choice.
- A sidebar / `NSVisualEffectView` gives vibrancy; it is **not** Liquid Glass and does not change sizing. `.inset` is a table style, not a window-sizing concern.

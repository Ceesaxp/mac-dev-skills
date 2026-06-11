# App Type → Anchor Window Structure

Pick the window/view-controller spine that anchors a macOS app *before* selecting any control.

HIG references (align "when to use" with these pages):
[Windows](https://developer.apple.com/design/human-interface-guidelines/windows) ·
[Split views](https://developer.apple.com/design/human-interface-guidelines/split-views) ·
[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) ·
[Menus](https://developer.apple.com/design/human-interface-guidelines/menus) ·
[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

The HIG Windows guidance favors standard windows, toolbars, tabs, and split views so people can predict where navigation and commands live. Split Views guidance says split views help people "quickly scan, compare, or transfer information between panes without losing their place," and recommends the source-list sidebar as the primary navigation surface for apps with distinct top-level sections. Fix this top-level structure first; the corpus is the catalog of how to build each spine.

## App type → anchor structure

| App type | Anchor structure | Why this spine | Corpus pattern id |
|---|---|---|---|
| Settings / inspector | `NSSplitViewController` (sidebar item + content item) | Persistent, resizable panes; system source-list sidebar + collapse for free | `splitviewcontroller-sidebar-inspector` |
| Browser (Mail/Notes/Finder) | `NSSplitViewController` + view-based `NSTableView`/`NSOutlineView` in panes | Scan/compare across panes without losing place; three-pane sidebar→list→detail | `splitviewcontroller-sidebar-inspector`, `tableview-view-based-reuse` |
| Document / editor | `NSWindowController` + content `NSViewController` + unified `NSToolbar` | One window owns a document; toolbar hosts editor commands predictably | `windowcontroller-content-viewcontroller`, `unified-toolbar-window-style` |
| Peer panes / paged config | `NSTabViewController` (`.tabStyle = .toolbar`) | Each tab is a self-contained workflow; toolbar tabs at the top | `tabviewcontroller-paged-panes` |
| Menu-bar utility | `NSStatusItem` from `NSStatusBar.system` | Lives in the menu bar, no main window required | `statusitem-menubar-extra` |
| Utility / form / settings pane | `NSPanel` (or window) + `NSGridView` | Auxiliary task; grid aligns label/field pairs across sizes and localization | `gridview-label-field-form` |

Pull the real code with `sdk-search get <id>`; adapt it, don't rewrite from memory.

## Choosing the spine

| ❌ Don't | ✅ Do | Why |
|---|---|---|
| Bare `NSSplitView` for a sidebar | `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)` | Factory item sets `behavior = .sidebar`, holding priority, collapse, and source-list vibrancy; bare split views resize jaggedly |
| `NSTabViewController` when panes must be seen together | `NSSplitViewController` | Tabs hide peers; reach for tabs only when each tab is a self-contained workflow |
| Nest `NSSplitViewController` inside another | One root `NSSplitViewController`; compose with `NSViewController`/`NSTabViewController` children | Nested split views fight over the responder chain for `toggleSidebar(_:)` and produce double dividers |
| Drive an editor window from a bare `NSWindow` | `NSWindowController` owning a content `NSViewController` | The controller scopes per-document lifecycle, `windowDidLoad()`, and toolbar/first-responder wiring |
| Build a menu-bar app with a hidden main window | `NSStatusItem` + `NSMenu` | The status item is the app's whole surface; no window to manage |

## Worked example: settings/sidebar window structure

Adapted from `splitviewcontroller-sidebar-inspector`. A two-item split — a sidebar driving a content area — is the canonical settings/inspector spine. Use the `sidebarWithViewController:` factory (never a plain item), set `allowsFullHeightLayout` so the sidebar flows behind a unified toolbar, and wire `toggleSidebar(_:)` through the responder chain.

```swift
import AppKit

@MainActor
final class SettingsSplitController: NSSplitViewController {
  private let sidebar = SidebarController()
  private let content = ContentController()
  private var sidebarItem: NSSplitViewItem!

  override func viewDidLoad() {
    super.viewDidLoad()

    // init(sidebarWithViewController:) sets behavior = .sidebar — source-list
    // appearance, correct holding priority, thinner divider. Never a plain item.
    let item = NSSplitViewItem(sidebarWithViewController: sidebar)
    item.allowsFullHeightLayout = true        // macOS 11.0+: sidebar runs behind
                                              // the titlebar under a unified toolbar
    item.minimumThickness = 180
    item.maximumThickness = 320
    item.canCollapse = true
    sidebarItem = item

    let detail = NSSplitViewItem(contentListWithViewController: content)
    detail.minimumThickness = 320

    addSplitViewItem(item)
    addSplitViewItem(detail)

    sidebar.onSelectionChanged = { [weak self] node in
      self?.content.show(node: node)
    }
  }

  // NSSplitViewController.toggleSidebar(_:) walks splitViewItems and collapses
  // the first .sidebar item; it participates in the responder chain, so a
  // toolbar item or View > Hide Sidebar (⌃⌘S) drives it with no extra wiring.
  @IBAction func toggleSidebar(_ sender: Any?) { super.toggleSidebar(sender) }
}

@MainActor
final class SidebarController: NSViewController {
  var onSelectionChanged: ((SidebarNode) -> Void)?
  // Source-list style is the NSTableView.style (11.0+) inherited by NSOutlineView:
  //   outlineView.style = .sourceList
  // It supplies translucent background, selection highlight, and vibrancy.
  // Do NOT use the deprecated .selectionHighlightStyle = .sourceList (12.0).
  // Cells are view-based: makeView(withIdentifier:owner:) → NSTableCellView,
  // never cell-based. Labels use .labelColor / .secondaryLabelColor — never RGB.
  // Section titles size with NSFont.preferredFont(forTextStyle: .headline)
  // (AppKit's preferredFont adds an optional options: param, default [:]).
}
```

Bad foil — the reason the factory matters:

```swift
// ❌ Plain item: no behavior = .sidebar, no source-list styling, wrong divider.
let item = NSSplitViewItem(viewController: sidebar)
item.canCollapse = true   // collapses, but resizes jaggedly and looks opaque
addSplitViewItem(item)
```

## Unified toolbar + sidebar tracking separator

The unified toolbar and the sidebar's full-height layout are a pair — adopt both or neither (from `unified-toolbar-window-style`):

```swift
window?.toolbarStyle = .unified                       // macOS 11.0+
// Default item identifiers, in order:
[.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
```

- `NSSplitViewItem.allowsFullHeightLayout = true` (11.0+) lets the sidebar flow behind the titlebar.
- `NSToolbarItem.Identifier.sidebarTrackingSeparator` (11.0+) aligns the toolbar's divider to the live sidebar edge. Without **both**, the sidebar stops at the titlebar edge and the unified look breaks.
- `NSToolbarItem.Identifier.toggleSidebar` gives the standard collapse button, validated against the first responder automatically.

A source-list sidebar gives vibrancy in places — that is *not* the same as adopting `NSGlassEffectView` (Liquid Glass, 26.0+). `.inset` is a table style, not Liquid Glass.

## NSWindowController vs a bare window

| Use `NSWindowController` when… | A bare `NSWindow`/`NSPanel` is enough when… |
|---|---|
| The window owns a document or per-window state (editors, browsers) | The surface is transient or stateless (a quick utility panel) |
| You need `windowDidLoad()`, restoration, or title/represented-file wiring | No lifecycle hook or restoration is needed |
| Multiple windows of the same kind coexist | There is exactly one auxiliary panel |
| A toolbar/first-responder spine must be wired once at load | No toolbar, no first-responder routing |

`NSWindowController` hosts content through its `contentViewController`, which mirrors to `NSWindow.contentViewController`; set it in `windowDidLoad()`. For utility/form panels, an `NSPanel` hosting an `NSGridView` (`column(at:).xPlacement = .trailing`, `rowAlignment = .firstBaseline`) needs no controller.

Note: the accessibility **identifier** (`setAccessibilityIdentifier(_:)`, for UI tests) is distinct from the VoiceOver **label** (`setAccessibilityLabel(_:)` / `NSImage` `accessibilityDescription`). Both matter; set them on the panes and toolbar items, not just the window.

# Control Selection: Requirement → Canonical Control

Map each UI requirement to the modern AppKit control, and name the legacy forms to avoid.

HIG references (align "when to use" with these pages):
[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) ·
[Outline views](https://developer.apple.com/design/human-interface-guidelines/outline-views) ·
[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) ·
[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) ·
[Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders) ·
[Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) ·
[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) ·
[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)

The HIG favors recognizable, standard AppKit components with semantic appearance over custom row containers and bespoke controls. Pick from this table first.

## Requirement → control

| Requirement | Canonical control | Key entry point | Corpus pattern id |
|---|---|---|---|
| Tabular data the user scans/sorts/selects | View-based `NSTableView` + `NSTableViewDiffableDataSource` | `makeView(withIdentifier:owner:)`, `apply(_:animatingDifferences:)` | `tableview-view-based-reuse`, `tableview-diffable-datasource` |
| Hierarchy (tree, disclosure triangles) | `NSOutlineView` + `NSOutlineViewDataSource`/`Delegate` | `outlineView(_:child:ofItem:)`, `outlineView(_:viewFor:item:)` | `outlineview-datasource-delegate` |
| Grid / gallery of items | `NSCollectionView` + `NSCollectionViewCompositionalLayout` | `NSCollectionLayoutSection`/`Group`/`Item`, `NSCollectionViewDiffableDataSource` | `collectionview-compositional-layout` |
| Window-level commands / navigation | `NSToolbar` + `NSToolbarDelegate` | `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)`, `toolbarDefaultItemIdentifiers(_:)` | `toolbar-delegate-itemforidentifier` |
| Modal decision tied to a window | `NSAlert` as an async sheet | `beginSheetModal(for:)`, `NSApplication.ModalResponse.alertFirstButtonReturn` | `nsalert-sheet-modal-async` |
| Transient info/actions anchored to a control | `NSPopover` (`.transient`) | `show(relativeTo:of:preferredEdge:)`, `NSPopover.Behavior.transient` | `nspopover-transient` |
| Pick one of N modes / scopes | `NSSegmentedControl` | `init(labels:trackingMode:target:action:)`, `selectedSegment` | `segmented-control` |
| On/off boolean | `NSSwitch` (macOS 10.15+) | `NSSwitch.state` | `switch-slider-stepper-values` |
| Pick one from a list (compact) | `NSPopUpButton` | `addItem(withTitle:)`, `selectedItem`, `NSMenuItem.representedObject` | `popupbutton-population` |
| Continuous value in a range | `NSSlider` | `minValue` / `maxValue`, `doubleValue`, `isContinuous` | `switch-slider-stepper-values` |
| Increment/decrement discrete value | `NSStepper` | `increment`, `valueWraps` | `switch-slider-stepper-values` |
| Open / save files | `NSOpenPanel` / `NSSavePanel` + `UTType` | `allowedContentTypes`, `beginSheetModal(for:)`, `urls` | `open-save-panel-utype` |

Pull the real code with `sdk-search get <id>`; adapt it, don't rewrite from memory.

## Legacy forms to avoid

| ❌ Legacy / wrong | ✅ Modern canonical | Why |
|---|---|---|
| Cell-based `NSTableView` (`NSTableColumn.dataCell`, `NSCell` subclasses) | View-based `NSTableView` (`makeView(withIdentifier:owner:)` + `NSTableCellView`) | View-based recycles real `NSView`s; cells can't host Auto Layout, accessibility, or rich subviews |
| Bare `NSSplitView` for a sidebar | `NSSplitViewController` + `NSSplitViewItem(sidebarWithViewController:)` | The controller gives system sidebar vibrancy, collapse, and `toggleSidebar(_:)` for free |
| Custom `NSView` reimplementing a standard control | The standard control (`NSSwitch`, `NSSegmentedControl`, `NSPopUpButton`, …) | You lose semantic color, focus ring, accessibility, and Dark/High-Contrast for free |
| `NSAlert.runModal()` blocking the main thread | `beginSheetModal(for:)` with async/await | Sheet scopes the interruption to the window and never freezes drawing |
| `NSDrawer` / child `NSWindow` tracked by hand | `NSPopover` with `.transient` | Auto-dismiss and arrow anchoring are handled by AppKit |

Note: `.inset` is a *table style*, not Liquid Glass. A sidebar's vibrancy comes from `NSSplitViewItem`/`NSVisualEffectView` — that is not adopting `NSGlassEffectView` (26.0+). Set the accessibility **identifier** (`setAccessibilityIdentifier(_:)`, for UI tests) *and* the VoiceOver **label** (`setAccessibilityLabel(_:)` / `NSImage` `accessibilityDescription`) — they are different things.

## GOOD vs BAD: view-based vs cell-based table

Adapted from corpus pattern `tableview-view-based-reuse`. Use semantic fonts/colors and let `NSTableCellView` manage selection appearance via its `textField` outlet.

```swift
// ✅ GOOD — view-based NSTableView: real NSViews recycled via makeView
import AppKit

@MainActor
final class PeopleTableController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
  private let tableView = NSTableView()
  private var people: [String] = ["Ada", "Grace", "Alan"]
  private let cellID = NSUserInterfaceItemIdentifier("NameCell")

  func numberOfRows(in tableView: NSTableView) -> Int { people.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    // Reuse an existing NSTableCellView, or build one once. The identifier
    // MUST match the cell's identifier or reuse silently breaks.
    let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
      let view = NSTableCellView()
      let text = NSTextField(labelWithString: "")
      text.translatesAutoresizingMaskIntoConstraints = false
      text.font = .preferredFont(forTextStyle: .body)   // semantic font (forTextStyle:options:)
      text.textColor = .labelColor                       // semantic color, never hex
      view.addSubview(text)
      view.textField = text                              // wire outlet → selection appearance works
      view.identifier = cellID
      NSLayoutConstraint.activate([
        text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
        text.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      return view
    }()
    cell.textField?.stringValue = people[row]
    return cell
  }
}
```

```swift
// ❌ BAD — cell-based table: NSCell can't host subviews, Auto Layout, or accessibility
let column = NSTableColumn(identifier: .init("name"))
column.dataCell = NSTextFieldCell()        // deprecated style; no per-row NSView, no a11y
tableView.addTableColumn(column)
// numberOfRows + tableView(_:objectValueFor:row:) drives raw cell values — dead end.
```

`NSFont.preferredFont(forTextStyle:options:)` adds an `options:` parameter (default `[:]`), so `preferredFont(forTextStyle: .body)` also compiles (UIKit has no `options:`). `NSFont.TextStyle` (constants `.body`, `.headline`, `.title1`) is macOS 11.0+. If you adopt `NSGlassEffectView` or other Liquid Glass APIs (26.0+), gate them: `if #available(macOS 26.0, *) { … }`.

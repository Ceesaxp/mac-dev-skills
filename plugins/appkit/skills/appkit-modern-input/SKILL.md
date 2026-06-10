---
name: appkit-modern-input
description: Use when modernizing input handling in a macOS AppKit app — overriding mouseDown:/rightMouseDown:, hand-rolling mouse tracking loops with nextEvent(matching:), wiring selection / context menus / drag-and-drop by hand, fixing a control that won't respond to clicks (overlapping sibling views), broken Tab key-view navigation, or NSStatusItem status-bar items with a custom view or window. Targets modern macOS (macOS 26/27).
---

# Modernizing AppKit Input Handling

## Overview

**The modern way to handle mouse events in AppKit is gesture recognizers and dedicated view-based APIs — not `mouseDown:` overrides or `nextEvent(matching:)` tracking loops.** SwiftUI, UIKit (via Mac Catalyst), and AppKit all share gesture recognizers as a common event language, so adopting them gives cross-framework behavior for free.

Source: WWDC 2026 Session 289, "Modernize Your AppKit App." APIs marked **(new in macOS 27)** are post-2025; do not substitute older patterns for them.

## When to Use

- You're overriding `mouseDown(with:)` / `rightMouseDown(with:)` or running a manual `nextEvent(matching:)` tracking loop.
- A control "doesn't respond to a click."
- Tab / Shift-Tab focus order is wrong after views are added or removed.
- An `NSStatusItem` uses a custom view, or shows a custom window, and keyboard focus misbehaves.

## Replace each `mouseDown:` job with its dedicated API

`mouseDown:` is usually overridden for one of four jobs. Each has a better, more reliable home:

| If you override `mouseDown:` to… | Use instead |
|---|---|
| **Track selection** | Observe the `selected` property on `NSCollectionViewItem` / `NSTableRowView`, **or** the selection-change delegate callbacks (`NSTableViewDelegate`, `NSOutlineViewDelegate`). |
| **Show a context menu** | `NSView.defaultMenu` (class property — same menu for every instance), `NSResponder.menu` (instance property — per-responder menu), or `NSView.menu(for:)` (instance method — build the menu dynamically from the event). |
| **Drag and drop** (in collection container views) | Modern dragging delegate methods — `tableView(_:pasteboardWriterForRow:)` and the equivalents on `NSCollectionView`, `NSOutlineView`, `NSBrowser`. |
| **Select text outside `NSTextView`** | `NSTextSelectionManager` **(new in macOS 27)** — attach it to a view + a text selection data source for bidirectional selection, drag-and-drop with text, and toggling. |

### Modern dragging delegate

Create a pasteboard item, set its data, return it — AppKit drives the drag:

```swift
func tableView(_ tableView: NSTableView,
               pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
    let pasteboardItem = NSPasteboardItem()
    let value = items[row].id   // the String you want to drag
    pasteboardItem.setString(value, forType: .string)
    return pasteboardItem
}
```

## Control events (familiar from UIKit, now in AppKit)

For reacting to user-driven tracking state changes on **standard controls** (buttons, sliders), register a target/action for a control event instead of writing tracking logic. **No subclassing required.** (Most control events have been available since macOS 11 — surfacing them is the modern path.)

```swift
let button = NSButton()
button.addTarget(
    self,
    action: #selector(trackingEndedOutsideHandler),
    for: .trackingEndedOutside
)
```

For more control, add a standard `NSGestureRecognizer`; for maximum flexibility, subclass your own. See Apple's "Gestures" documentation.

## "My control won't respond to clicks" → overlapping sibling

Gesture recognizers operate on a view **and its subviews**. An overlapping sibling view silently swallows the click before it reaches the control underneath.

- **Fix first:** resize the overlapping view so it no longer covers the control.
- **If it must stay** (it's an intentional overlay), override `hitTest(_:)` to return `nil` so hit-testing falls through to the content beneath:

```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
}
```

## Keyboard navigation

The **key view loop** is the order Tab / Shift-Tab cycle controls. To keep it correct automatically as views are added or removed, enable it on the window:

```swift
window.autorecalculatesKeyViewLoop = true
```

If you don't set this, **you** own creating and maintaining the loop (`nextKeyView`).

## Status items and keyboard focus

Keyboard navigation reaches into the menu bar and status items.

- **Status item that shows a menu** — already behaves like a menu bar menu. Nothing to do.
- **Status item that triggers an action** — set a target + action (and optionally an image) on `NSStatusItem.button`. It fires on Return during keyboard navigation, like a button.
- **Status item with a custom view** — set the view via the status item's `view` property, then add a target + action to the status item.
- **Status item that shows a custom window** — AppKit must know when that UI is active so keyboard focus behaves. Use the **expanded interface session API (new in macOS 27)**.

### Expanded interface session

Set the delegate when the item is created:

```swift
@main class LightAppDelegate: NSObject, NSApplicationDelegate {
    lazy var lightStatusItem: NSStatusItem = { /* ... */ }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        lightStatusItem.expandedInterfaceDelegate = self
    }
}
```

Implement the delegate — show the window on begin, order it out on end, and **cancel the session to request dismissal** (e.g. after the user picks an action):

```swift
extension LightAppDelegate: NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem,
                    didBegin session: NSStatusItemExpandedInterfaceSession) {
        // Show window
    }

    func statusItemDidEndExpandedInterfaceSession(
        _ statusItem: NSStatusItem, animated: Bool) {
        // Hide window
    }

    func selectedAction() {
        // Take the action, then request window dismissal:
        lightStatusItem.expandedInterfaceSession?.cancel()
    }
}
```

The session may also be canceled **for you** if focus naturally moves elsewhere. If this is (or could be) a SwiftUI app, `MenuBarExtra` does much of this automatically — see WWDC 2026 "Use SwiftUI with AppKit and UIKit."

## Common Mistakes

- **Reaching for a click `NSGestureRecognizer` to track selection in a table/collection view.** Observe `selected` or use the selection delegate callbacks instead — those are the dedicated APIs.
- **Calling `beginDraggingSession(...)` by hand for collection views.** Use the pasteboard-writer delegate methods; AppKit drives the session.
- **Showing context menus from `rightMouseDown:`.** Use `defaultMenu` / `menu` / `menu(for:)` — they also handle Control-click, the keyboard menu key, and accessibility.
- **Hand-maintaining `nextKeyView` for a dynamic view tree.** Turn on `autorecalculatesKeyViewLoop`.
- **Building a status-item window with a raw `NSPanel` + `canBecomeKey` hacks.** Use `NSStatusItemExpandedInterfaceDelegate` so AppKit manages focus.

## Recap

Find every `mouseDown:` override → move it to a view API, a control event, or a gesture recognizer. Prioritize user **intent** over tracking loops. Make the app fully keyboard-navigable.

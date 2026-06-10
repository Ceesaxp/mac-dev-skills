---
name: appkit-launch-continuity
description: Use when a macOS AppKit app blocks system shutdown/restart or won't quit while showing a sheet or modal, or when it should relaunch exactly where the user left off — restoring open windows, the selected item, and frontmost/minimized/full-screen state. Covers graceful termination (preventsApplicationTerminationWhenModal) and state restoration with NSWindowRestoration. Targets modern macOS.
---

# AppKit Launch Continuity: Graceful Quit + State Restoration

## Overview

**A great Mac app quits without pushback and comes back as if it was never quit.** People quit apps whenever they want — sometimes the system does it for them, e.g. an overnight reboot for a software update. The app should block quit *only* when it genuinely needs to, and on relaunch restore exactly where the user left off.

Source: WWDC 2026 Session 289, "Modernize Your AppKit App."

## When to Use

- The app blocks a system restart/shutdown because a sheet or modal is up.
- After quit + relaunch the app loses its open windows, selection, or window arrangement.

## Part 1 — Graceful termination

When a window is presenting a sheet, it may not be able to close — and if a window can't close, the app can't quit. The relevant property is:

```swift
window.preventsApplicationTerminationWhenModal = false
```

- It **defaults to `true`** — for good reason: it protects unsaved data (e.g. a "save this document?" sheet that genuinely needs a response).
- Set it to **`false`** for every sheet or modal that does **not** strictly require user intervention (inspectors, non-blocking dialogs). That lets the app terminate gracefully.

> You do **not** need to inspect the quit reason (`kAEQuitReason` Apple Events, `applicationShouldTerminate:` archaeology) to decide whether to block. Set this one property per-modal based on whether the modal is critical.

## Part 2 — State restoration (`NSWindowRestoration`)

Three steps: **opt in → encode UI state → decode to restore windows and UI.**

### Step 1: Opt in (in the window controller)

```swift
@MainActor class MainWindowController: NSWindowController, NSWindowDelegate {
    convenience init() {
        let window = NSWindow(/* ... */)
        window.identifier = NSUserInterfaceItemIdentifier(WindowIdentifiers.mainWindow)
        window.setFrameAutosaveName(WindowIdentifiers.mainWindow)
        window.isRestorable = true
        window.restorationClass = WindowRestorationHandler.self
    }
}
```

- **`identifier`** — stable identity for the window.
- **`setFrameAutosaveName`** — for *common* windows (main, preferences); restores to the same space with the same frame. **Not needed for document windows.**
- **`isRestorable = true`** — lets AppKit call `encodeRestorableState`/`restoreState`, and auto-restore which window was minimized, frontmost, and full-screen.
- **`restorationClass`** — invoked on relaunch to recreate the window.

### Step 2: Encode UI state

```swift
override func encodeRestorableState(with coder: NSCoder) {
    super.encodeRestorableState(with: coder)   // always call super
    coder.encode(selectedProduct?.identifier.uuid.uuidString,
                 forKey: RestorationKeys.productIdentifier)
}
```

- **Encode UI state only.** The goal is to reconstruct the *UI*, not re-serialize the app — **avoid encoding data that lives in your document or database.**
- All `NSResponder`s have `encodeRestorableState` — override it on views too, as needed.
- It's called **only when state has been invalidated.** Whenever a view-hierarchy change should alter saved state, call `invalidateRestorableState()`:

```swift
splitViewController.onProductSelected = { [weak self] product in
    self?.invalidateRestorableState()
}
```

AppKit then calls `encodeRestorableState` on everything invalidated, before quit.

### Step 3: Restore on relaunch — windows first, then state

**Restore windows** in the restoration class. This is called for *every* window being restored:

```swift
class WindowRestorationHandler: NSObject, NSWindowRestoration {
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        if identifier == .mainWindow, let window = appDelegate.mainWindowController?.window {
            completionHandler(window, nil)
        } else if identifier == .imageWindow {
            let controller = ImageWindowController()
            appDelegate.imageWindowControllers.append(controller)
            completionHandler(controller.window, nil)
        } else {
            completionHandler(nil, error)
        }
    }
}
```

> **Always call the completion handler — AppKit waits on every restorable window.** If creation fails, call it with the error. If you can't call it inside the method, save the handler and call it later, but *be absolutely sure to call it.*

**Then restore the UI** for each window with the same coder you encoded into:

```swift
override func restoreState(with coder: NSCoder) {
    super.restoreState(with: coder)
    if let productId = coder.decodeObject(
        of: [NSString.self],
        forKey: RestorationKeys.productIdentifier) as? String {
        splitViewController?.selectedProductId = productId
    }
}
```

## Common Mistakes

- **Over-engineering termination** by inspecting quit reasons / `applicationShouldTerminate:` instead of setting `preventsApplicationTerminationWhenModal = false` on non-critical modals.
- **Encoding document/database data** into restorable state. Encode only what's needed to rebuild the UI.
- **Forgetting to call the completion handler** in `restoreWindow(withIdentifier:state:)` — AppKit hangs waiting for it.
- **Omitting `super`** in `encodeRestorableState`/`restoreState`.
- **Never calling `invalidateRestorableState()`** — so `encodeRestorableState` never fires and nothing is saved.

## Recap

Make quit non-blocking for non-critical modals, then save and restore UI state so relaunch feels uninterrupted. See Apple's code sample "Restoring your app's state with AppKit."

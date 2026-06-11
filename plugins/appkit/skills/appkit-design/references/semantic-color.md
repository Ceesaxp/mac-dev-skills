# Semantic Color

Use semantic system `NSColor`s so the UI survives Dark Mode, Increase Contrast, and accent tint — never hardcode RGB/hex.

HIG reference: [Color](https://developer.apple.com/design/human-interface-guidelines/color) — "Use system-defined colors" and "Support Dark Mode and Increase Contrast." Semantic colors are dynamic: their resolved value depends on the current appearance, so the system adapts them for you.

All symbols below verified with `sdk-api`. All semantic `NSColor`s have existed since 10.10–10.14; none require macOS 26 gating.

## Semantic NSColor catalog

| Color | Since | Use for |
|---|---|---|
| `.labelColor` | 10.10 | Primary text — the main label on a control or row |
| `.secondaryLabelColor` | 10.10 | Subordinate text — subtitles, captions, less-prominent labels |
| `.tertiaryLabelColor` | 10.10 | Disabled / placeholder text, watermark-level content |
| `.textColor` | — | Text in editable / selectable document text fields |
| `.textBackgroundColor` | — | Background behind editable document text (text views, fields) |
| `.controlBackgroundColor` | — | Background of large content areas drawn under controls (scroll/table content) |
| `.windowBackgroundColor` | — | Window backgrounds and non-text content areas |
| `.controlAccentColor` | 10.14 | The user's chosen accent tint — highlights, focus rings, on-states |
| `.separatorColor` | 10.14 | Thin dividers between content sections |
| `.selectedContentBackgroundColor` | 10.14 | Background of selected rows/items in an emphasized, key list/table |
| `.linkColor` | 10.10 | Hyperlink text |

Rule of thumb: pick the color named for the *role* (label, separator, window), not the one whose default light-mode value looks right.

## ❌ Don't hardcode / ✅ Do use semantic

```swift
// ❌ BAD — fixed values. Black-on-dark in Dark Mode (unreadable),
// ignores the user's accent tint, and never shifts under Increase Contrast.
label.textColor      = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
divider.fillColor    = NSColor(white: 0.85, alpha: 1)
selectionView.color  = NSColor(red: 0/255, green: 122/255, blue: 1, alpha: 1) // "system blue"

// ✅ GOOD — semantic. Resolves correctly in light, dark, high-contrast,
// and honors the accent the user picked in System Settings.
label.textColor      = .labelColor
divider.fillColor    = .separatorColor
selectionView.color  = .controlAccentColor
```

Why the BAD breaks: a literal RGB has one value for all appearances, so Dark Mode and Increase Contrast can't override it. The hardcoded "system blue" also defeats the user's accent choice. Semantic colors carry per-appearance values the system selects at draw time.

## Layer-backed gotcha: resolve CGColor through `effectiveAppearance`

`CALayer` takes a `CGColor`, which is a *static snapshot* — `NSColor.cgColor` resolves against whatever appearance is current **at the moment you read it**, then the layer keeps that frozen value. So a layer color set once does NOT auto-update when the user flips Dark Mode or toggles Increase Contrast.

Fix: re-resolve in `viewDidChangeEffectiveAppearance()`, inside `performAsCurrentDrawingAppearance(_:)` so `.cgColor` resolves against the view's *new* appearance (not the app-global one). Also observe `accessibilityDisplayOptionsDidChangeNotification` so high-contrast/transparency changes (which are not appearance changes) re-trigger the refresh.

```swift
import AppKit

/// Layer-backed view whose CGColors stay correct across Dark Mode,
/// Increase Contrast, Reduce Transparency, and accent-tint changes.
final class SemanticLayerView: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Increase Contrast / Reduce Transparency are NOT appearance changes,
        // so subscribe to the workspace accessibility notification too.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // Fires on Dark Mode and accent-tint changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    @objc private func displayOptionsChanged() { applyColors() }

    private func applyColors() {
        // Re-resolve CGColors against THIS view's current appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor     = NSColor.separatorColor.cgColor

            // Read live accessibility state to branch behavior if needed.
            let ws = NSWorkspace.shared
            layer?.borderWidth = ws.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
            // ws.accessibilityDisplayShouldReduceTransparency -> drop blur, use opaque fills
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
```

Key points:
- `NSColor.cgColor` is fine — but only *inside* `performAsCurrentDrawingAppearance(_:)`, and only if re-run on appearance change. Outside it, you snapshot the wrong appearance.
- `effectiveAppearance` is the view's resolved appearance (`NSAppearanceCustomization`); prefer it over `NSApp.effectiveAppearance` so sidebars / vibrant containers resolve correctly.
- For high-contrast checks, read `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` / `...ShouldReduceTransparency`; refresh on `accessibilityDisplayOptionsDidChangeNotification`.
- Plain `NSView` / `NSTextField` that draw `NSColor` directly (not via a layer) update automatically — this dance is only for `CGColor` on a `CALayer`.

## Verify in every state

Before shipping, check the result in: Light, Dark, Increase Contrast (Accessibility → Display), a non-default accent tint, and Reduce Transparency. A correct semantic-color build needs zero code changes across all five.

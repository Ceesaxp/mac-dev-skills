# Accessibility Baseline

The non-negotiable accessibility floor for AppKit UI: every interactive control gets a UI-test **identifier** *and* a VoiceOver **label** — they are different things and both are required.

HIG: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) — accurate roles, concise labels, stable identifiers, keyboard-operable behavior, and respect for the user's display accommodations. Align every choice below with that page.

> All `setAccessibility*` methods below are on **`NSAccessibilityProtocol`** (adopted by `NSView`, `NSControl`, `NSCell`, …), introduced macOS 10.10 — *not* declared on `NSView` directly. Call them on any view/control instance.

## Identifier vs label — the #1 miss

They sound interchangeable. They are not. Setting one and calling a11y "done" is the most common failure.

| | `setAccessibilityIdentifier(_:)` | `setAccessibilityLabel(_:)` / `NSImage.accessibilityDescription` |
|---|---|---|
| **Purpose** | Stable handle for **UI tests** to find the control | **VoiceOver** text spoken to the user |
| **Audience** | Test code (`appkit-ui-testing` queries this) | A person using VoiceOver |
| **Spoken aloud?** | **No** — never surfaced to VoiceOver | **Yes** |
| **Value style** | Code-stable token: `"saveButton"` | Human phrase: `"Save"` |
| **Localized?** | No — keep constant across locales | **Yes** — localize it |
| **Symbol** | `NSAccessibilityProtocol.setAccessibilityIdentifier(_:)` | `NSAccessibilityProtocol.setAccessibilityLabel(_:)` · `NSImage.accessibilityDescription` (10.6) |

❌ **Don't** treat them as one thing:
```swift
button.setAccessibilityLabel("save-button")   // wrong on both counts: not a UI-test handle, and VoiceOver reads "save dash button"
```
✅ **Do** set both, each for its job:
```swift
button.setAccessibilityIdentifier("saveButton")  // test handle, not localized
button.setAccessibilityLabel("Save")             // VoiceOver text, localized
```

For icon-only images, the label rides on the image itself:
```swift
let icon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")  // sets the description in one call
```

## Label wording

| ❌ Don't | ✅ Do | Why |
|---|---|---|
| `"Save button"` | `"Save"` | The role already says "button"; don't repeat the type |
| `""` on an icon-only control | `"Add Item"` | Icon-only controls are silent without a label |
| `"img_trash_24"` | `"Delete"` | Labels are for humans, not asset names |
| Hardcoded English string | Localized string | Labels are spoken; localize them |

## Baseline checklist

| Requirement | API | Notes |
|---|---|---|
| Identifier on **every** interactive control | `setAccessibilityIdentifier(_:)` | The handle `appkit-ui-testing` queries |
| Meaningful label on every **icon-only** control | `setAccessibilityLabel(_:)` / `NSImage.accessibilityDescription` | Without it VoiceOver says nothing useful |
| Custom `NSView` exposed as an element | `setAccessibilityElement(true)` + `setAccessibilityRole(_:)` | A custom drawing view is invisible to AT until you opt in |
| Semantic role on custom views | `setAccessibilityRole(_:)` — `.button`, `.image`, `.group`, … | Lets VoiceOver describe *what it is* |
| Optional hint for non-obvious actions | `setAccessibilityHelp(_:)` | Extra context, spoken after the label |
| Respect **Increase Contrast** | `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` (10.10) | Pair with semantic `NSColor`; redraw on change |
| Respect **Reduce Motion** | `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (10.12) | Skip/shorten animations when true |
| Respect **Reduce Transparency** | `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` (10.10) | Drop vibrancy/glass for opaque fills |
| React to changes live | `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (10.10) | Observe on `NSWorkspace.shared.notificationCenter` |

Roles `.button`, `.image`, `.group` are members of the `NSAccessibility.Role` struct — verify others with `appkit-api members NSAccessibility.Role` before using.

## GOOD example — custom view as an accessibility element

Adapted from corpus `accessibility-custom-view-element` + `accessibility-identifier-ui-testing` + `high-contrast-display-options`. A custom-drawn badge that VoiceOver sees as a button, with a test handle, that respects Increase Contrast.

```swift
import AppKit

/// A custom-drawn control. Without the accessibility opt-in it is invisible to
/// VoiceOver; without the identifier it is unreachable from UI tests.
final class BadgeButton: NSView {
    var title: String { didSet { setAccessibilityLabel(title); needsDisplay = true } }
    var onClick: (() -> Void)?

    init(title: String, identifier: String) {
        self.title = title
        super.init(frame: .zero)

        // 1. Opt the custom view in as an accessibility element with a semantic role.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)        // NSAccessibility.Role.button

        // 2. VoiceOver text (localize `title`) + a UI-test handle. BOTH, different jobs.
        setAccessibilityLabel(title)         // spoken: "Run"
        setAccessibilityIdentifier(identifier)  // queried by tests: "run-badge"
        setAccessibilityHelp("Runs the selected task")  // optional spoken hint
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 3. Redraw with semantic colors so Increase Contrast + Dark Mode are honored.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.controlBackgroundColor.setFill()
            dirtyRect.fill()
            // Use a stronger separator when the user asked for more contrast.
            (highContrast ? NSColor.labelColor : NSColor.separatorColor).setStroke()
            NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    override func mouseUp(with event: NSEvent) { onClick?() }

    // Make the accessibility "press" actually trigger the action.
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
```

Observe display-accommodation changes once, app-wide, and re-render:
```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
    object: nil, queue: .main
) { [weak self] _ in
    self?.applyDisplayAccommodations()   // re-read shouldReduceMotion / IncreaseContrast / ReduceTransparency
}
```

## Verify before you ship

- `appkit-api check 'NSAccessibilityProtocol.setAccessibilityIdentifier(_:)'` — confirm the symbol and its 10.10 floor.
- `appkit-api members NSAccessibility.Role` — pick the *real* role for a custom view; don't guess the constant.
- Test in **light, dark, Increase Contrast, keyboard-only, and resized-window** states before calling it done.

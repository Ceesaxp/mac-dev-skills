# Typography

Use semantic `NSFont` text styles and system designs so text inherits system metrics, weight, and accessibility scaling — never hardcode a point size.

HIG: Typography — https://developer.apple.com/design/human-interface-guidelines/typography (corpus `semantic-font-text-style`). The HIG favors built-in semantic text styles and standard text controls over custom text drawing; align every choice below with that page.

Every symbol here is verified with `appkit-api`. All `NSFont.TextStyle` constants are macOS 11.0+; system designs are macOS 10.15+.

## Text-style ramp

Pick a `NSFont.TextStyle`, then `NSFont.preferredFont(forTextStyle:options:)`. Do not reach for `systemFont(ofSize:)`.

| `NSFont.TextStyle` | Use for |
|--------------------|---------|
| `.largeTitle` | Hero / splash heading, the largest prominent title |
| `.title1` | Primary view title |
| `.title2` | Section heading |
| `.title3` | Subsection heading |
| `.headline` | Emphasized lead-in, list-row primary line, grouped-control header |
| `.body` | Default running text, editable field text, descriptions |
| `.callout` | Slightly de-emphasized body, inline annotations |
| `.subheadline` | Secondary line under a headline |
| `.footnote` | Footnotes, fine print, ancillary detail |
| `.caption1` | Labels, timestamps, metadata under content |
| `.caption2` | Smallest caption / least prominent metadata |

## The signature gotcha — AppKit adds `options:`

The AppKit API is **`NSFont.preferredFont(forTextStyle:options:)`** (UIKit has no `options:`):

```swift
class func preferredFont(forTextStyle style: NSFont.TextStyle,
                         options: [NSFont.TextStyleOptionKey : Any] = [:]) -> NSFont
```

AppKit's signature adds an `options:` parameter defaulting to `[:]`, so **both** `preferredFont(forTextStyle: .body)` and `preferredFont(forTextStyle: .body, options: [:])` compile (UIKit has no `options:`). The real miss is the literal point size — it ignores the system ramp, weight, and accessibility scaling entirely.

```swift
// ❌ BAD — literal point size: the most common typography miss
label.font = NSFont.systemFont(ofSize: 13)

// ✅ GOOD — semantic text style (options: defaults to [:]; supply it for tracking, etc.)
label.font = NSFont.preferredFont(forTextStyle: .body)
titleLabel.font = NSFont.preferredFont(forTextStyle: .title2, options: [:])
```

## Complete example — labels, formatter, semantic font

Adapted from corpus `semantic-font-text-style` / `textfield-label-and-formatter`. Note the semantic `NSColor` (never literal RGB) and the accessibility **identifier** (for UI testing) — distinct from the VoiceOver **label**.

```swift
import AppKit

@MainActor
final class FormFieldController: NSViewController, NSTextFieldDelegate {
  override func loadView() {
    // Non-editable label: .init(labelWithString:) (macOS 10.12+)
    let title = NSTextField(labelWithString: "Contact")
    title.font = NSFont.preferredFont(forTextStyle: .title2, options: [:])
    title.textColor = .labelColor

    let caption = NSTextField(wrappingLabelWithString: "Numbers only.")
    caption.font = NSFont.preferredFont(forTextStyle: .caption1, options: [:])
    caption.textColor = .secondaryLabelColor

    // Editable, formatted field
    let field = NSTextField(string: "")
    field.placeholderString = "Phone"
    field.maximumNumberOfLines = 1
    field.formatter = NumberFormatter()
    field.delegate = self
    field.font = NSFont.preferredFont(forTextStyle: .body, options: [:])
    field.setAccessibilityIdentifier("contact.phone")   // UI-test hook, NOT the VoiceOver label

    let stack = NSStackView(views: [title, field, caption])
    stack.orientation = .vertical
    stack.alignment = .leading
    view = stack
  }

  func controlTextDidChange(_ obj: Notification) { }
}
```

## System designs — monospaced, rounded, serif

For monospaced or rounded text, **derive a descriptor from a semantic font** with `NSFontDescriptor.withDesign(_:)` — keep the style's size and metrics, swap only the design. `NSFontDescriptor.SystemDesign` values: `.monospaced`, `.rounded`, `.serif`, `.default` (all 10.15+).

```swift
// ✅ GOOD — monospaced digits/code that keeps semantic .body metrics
let base = NSFont.preferredFont(forTextStyle: .body, options: [:])
if let mono = base.fontDescriptor.withDesign(.monospaced) {       // -> NSFontDescriptor?
  codeLabel.font = NSFont(descriptor: mono, size: 0)              // size: 0 keeps descriptor size
}

// ✅ GOOD — rounded title
let titleBase = NSFont.preferredFont(forTextStyle: .title1, options: [:])
if let rounded = titleBase.fontDescriptor.withDesign(.rounded) {
  heroLabel.font = NSFont(descriptor: rounded, size: 0)
}
```

`withDesign(_:)` returns `Self?`, and `NSFont(descriptor:size:)` is failable — handle the `nil`; do not force-unwrap.

## Weights — only where a semantic style does not fit

Prefer a semantic style first (`.headline` already carries emphasis). Reach for an explicit weight **only** when no text style fits the role, via `NSFont.systemFont(ofSize:weight:)` with an `NSFont.Weight` constant (e.g. `.regular`, `.medium`, `.semibold`, `.bold`).

```swift
// ❌ BAD — re-deriving "bold body" by hardcoding size + weight
label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

// ✅ BETTER — let the semantic style carry the emphasis
label.font = NSFont.preferredFont(forTextStyle: .headline, options: [:])

// ✅ ACCEPTABLE — explicit weight only when no text style models the role
badge.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
```

## Quick rules

- ❌ `ofSize:` literals for body/label/title text → ✅ a `NSFont.TextStyle` via `preferredFont(forTextStyle:options:)`.
- ❌ literal `NSFont.systemFont(ofSize:)` for content text → ✅ `NSFont.preferredFont(forTextStyle:)` (pass `options:` only when you need it).
- ❌ Literal RGB/hex text color → ✅ `.labelColor` / `.secondaryLabelColor`.
- ❌ Bespoke monospaced/rounded font lookup → ✅ `fontDescriptor.withDesign(.monospaced/.rounded)`, `size: 0`.
- Accessibility **identifier** (`setAccessibilityIdentifier(_:)`, UI testing) ≠ VoiceOver **label** (`setAccessibilityLabel(_:)`). Both matter.

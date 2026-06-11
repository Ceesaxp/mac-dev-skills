# Layout & Spacing

Pin AppKit views with anchor constraints, pick NSStackView vs NSGridView correctly, and use HIG-grounded margins instead of guessed paddings.

**HIG reference:** [Human Interface Guidelines — Layout](https://developer.apple.com/design/human-interface-guidelines/layout). Align with its core themes: respect safe areas, keep margins and spacing consistent, group related elements, and design layouts that adapt to window resizing rather than fixed frames.

All symbols below verified against the macOS SDK with `sdk-api check`. Every API here ships in macOS 12+ (no Liquid Glass gating needed). Use semantic `NSColor` and `NSFont.preferredFont(forTextStyle:)` — never literal RGB or `systemFont(ofSize:)` for content text.

---

## 1. Auto Layout with anchors

Build constraints in code with `NSLayoutAnchor` and batch-activate them. This replaces stringly-typed VFL (`constraints(withVisualFormat:)`) and the legacy `constraintWithItem:` constructor.

| Step | API | Why |
| --- | --- | --- |
| Opt each view into Auto Layout | `translatesAutoresizingMaskIntoConstraints = false` | Leaving `true` adds conflicting implicit constraints |
| Pin to system insets | `view.safeAreaLayoutGuide` (macOS 11+) | Avoids camera housing / display features; HIG safe-area guidance |
| Make a constraint | `someAnchor.constraint(equalTo:constant:)` | Type-safe; axis-checked at compile time |
| Apply all at once | `NSLayoutConstraint.activate([...])` | Single solver pass, no intermediate layout |

Sign convention: leading/top constants are **positive** insets; trailing/bottom are **negative**. Add subviews to the hierarchy *before* activating — activating against a not-yet-added view silently anchors to nothing.

### Content hugging & compression resistance

For intrinsic-size controls (`NSTextField`, `NSButton`), priorities decide who stretches and who stays snug when space is tight.

| Priority | Meaning | Typical use |
| --- | --- | --- |
| Content hugging | Resistance to growing past intrinsic size | High on a label so it hugs its text |
| Compression resistance | Resistance to shrinking below intrinsic size | Low on a field so it yields/expands |

```swift
label.setContentHuggingPriority(.defaultHigh, for: .horizontal)   // label hugs its text
field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // field flexes
```

❌ **Don't** give two side-by-side views equal hugging — Auto Layout has no winner and logs an ambiguous-layout warning.
✅ **Do** make the label hug high and the field resist low, so the field absorbs slack on resize.

---

## 2. NSStackView vs NSGridView

| Use… | When | Axis |
| --- | --- | --- |
| `NSStackView` | One-axis flow: toolbars, button rows, a stacked column of controls | Single (`.horizontal` / `.vertical`) |
| `NSGridView` | Aligned label↔field forms; anything needing column **and** row alignment | Two |

Reach for a stack when items flow along one line and you want even spacing with `setCustomSpacing(_:after:)` for the odd gap. Reach for a grid when labels in column 0 must right-align against fields in column 1 and baselines must line up across rows — a stack can't align across a second axis.

### GOOD: NSGridView label/field form

Adapted from the corpus `gridview-label-field-form` pattern; right-aligned label column, baseline-aligned rows, HIG-standard 8pt column gap.

```swift
import AppKit

@MainActor
final class SettingsFormController: NSViewController {
  override func loadView() {
    let grid = NSGridView()
    grid.translatesAutoresizingMaskIntoConstraints = false
    grid.columnSpacing = 8           // inter-control gap (HIG-standard)
    grid.rowSpacing = 8
    grid.rowAlignment = .firstBaseline

    addRow(to: grid, "Name:", NSTextField(string: ""))
    addRow(to: grid, "Email:", NSTextField(string: ""))

    // Right-align the label column so colons line up against the fields.
    grid.column(at: 0).xPlacement = .trailing

    let root = NSView()
    root.addSubview(grid)
    NSLayoutConstraint.activate([
      grid.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 20),
      grid.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      grid.trailingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.trailingAnchor, constant: -20),
    ])
    view = root
  }

  private func addRow(to grid: NSGridView, _ title: String, _ field: NSTextField) {
    let label = NSTextField(labelWithString: title)
    label.font = .preferredFont(forTextStyle: .body)   // semantic font, options defaulted
    label.textColor = .secondaryLabelColor             // semantic color, never hex
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    grid.addRow(with: [label, field])
  }
}
```

### BAD foil

```swift
// Don't fake a form with a stack of horizontal stacks:
let row = NSStackView(views: [NSTextField(labelWithString: "Name:"), field])
row.orientation = .horizontal   // labels won't align across rows; colons drift
```

A vertical stack of horizontal stacks gives no cross-row column alignment — labels of different lengths leave fields ragged. That is exactly the case `NSGridView` exists for.

### Stack quick reference

```swift
let toolRow = NSStackView()
toolRow.orientation = .horizontal
toolRow.distribution = .fill
toolRow.spacing = 8                              // HIG-standard inter-control gap
toolRow.detachesHiddenViews = true               // hidden views collapse their space
toolRow.addArrangedSubview(addButton)
toolRow.addArrangedSubview(removeButton)
toolRow.setCustomSpacing(20, after: removeButton) // wider gap before a distinct group
```

---

## 3. HIG spacing metrics

The [HIG Layout page](https://developer.apple.com/design/human-interface-guidelines/layout) gives qualitative guidance — keep margins and spacing consistent, group related elements, respect safe areas, and adapt to window resizing — rather than a single quoted margin number. The concrete point values below are the long-standing macOS Aqua / Interface Builder standards that satisfy that guidance and that the corpus patterns use; treat them as defaults, not hard rules.

| Metric | Points | Apply via |
| --- | --- | --- |
| Window content margin (edge inset) | 20 | anchor `constant: 20` / `-20` against `safeAreaLayoutGuide` |
| Standard inter-control spacing | 8 | `NSStackView.spacing` / `NSGridView.columnSpacing` / `rowSpacing` |
| Spacing between distinct groups | 20 | `setCustomSpacing(20, after:)` |
| Related-control tight pairing | 8 | label-to-field gap in a grid row |

Guidance from the page, applied:

✅ **Do** pin content to `safeAreaLayoutGuide`, not the raw view bounds — keeps content clear of the title bar, toolbar, and display features.
✅ **Do** keep one margin value (20pt) and one base spacing value (8pt) across the window so alignment reads as intentional.
✅ **Do** group related controls and separate groups with the larger 20pt gap so structure is visible at a glance.
✅ **Do** let layouts reflow on resize via hugging/compression priorities instead of hard-coded frames.

❌ **Don't** hard-code frames or mix 7/9/11pt ad-hoc gaps — inconsistent spacing reads as broken.
❌ **Don't** anchor to `view.topAnchor` when you mean the safe area; content can slide under the toolbar.
❌ **Don't** invent paddings to "balance" a layout — adjust margins/spacing toward the standard values above.

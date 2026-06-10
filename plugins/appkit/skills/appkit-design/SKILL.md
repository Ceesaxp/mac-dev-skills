---
name: appkit-design
description: Use when designing or building any macOS AppKit user interface — choosing the control or layout for a new window/app, picking the canonical control for a requirement, adopting the macOS 26/27 Liquid Glass look, sizing a window to its content, applying semantic colors and typography, or reviewing AppKit UI for design correctness. Targets modern AppKit (macOS 26/27).
---

# AppKit Design

## Overview

Pick the canonical AppKit control and layout for a UI requirement, ground every choice in the Apple Human Interface Guidelines, and write modern, symbol-verified macOS 26/27 code.

**This skill ships two native tools next to this file** — `appkit-search` (BM25 search over a curated, HIG-grounded corpus of 69 canonical AppKit patterns) and `appkit-api` (SDK symbol + availability validator). Both are also on `PATH` after `scripts/build-tools.sh`. **The corpus is the control catalog; this skill is the discipline that makes you use it.**

> **You already know most of the controls. That is the trap.** A capable agent reaches for the right control from memory (`NSSplitViewController`, a view-based `NSTableView`, `NSGridView`) and then *skips everything that actually breaks*: it invents a symbol that doesn't exist, asserts a false equivalence (“`.inset` gives you Liquid Glass”), hardcodes a window frame, and ships zero accessibility identifiers. **Every recommendation below is verified against the SDK or the HIG, never from memory — because memory is exactly where the errors are.**

## The grounding mandate (do this first, every time)

**Before writing any AppKit UI, ground it. Two authorities, no exceptions:**

1. **`appkit-search`** for the canonical pattern. One focused query per feature you need:
   ```bash
   appkit-search search "settings sidebar" "file table" "toolbar"   # batch: one query per feature
   appkit-search get splitviewcontroller-sidebar-inspector          # full Swift + HIG ref + pitfalls
   appkit-search list                                                # browse categories (heavy)
   ```
2. **`appkit-api`** to verify *every* symbol and its macOS availability before you write it:
   ```bash
   appkit-api check 'NSGlassEffectView.effectIsInteractive'   # exists? → {exists, availability}
   appkit-api availability NSViewCornerConfiguration          # min macOS / deprecation
   appkit-api members NSSplitViewItem                         # discover the real members
   ```

**Workflow:** front-load all `search` calls for the page → `get` the best pattern IDs → verify the symbols you'll use with `appkit-api` → *then* write code, adapting the corpus snippets. Do not interleave searching with coding.

> **"This is just a code sketch, I'll answer directly."** No. That sentence is the #1 failure mode — it is how invented symbols and false claims ship. A sketch that names a wrong API is worse than no sketch. **Sketch or production, the grounding is the same two commands.** If the tools aren't installed, run `scripts/build-tools.sh` (or tell the user to) — don't fall back to memory.

## Non-negotiable design hygiene

Apply to **every** design, no matter how small. These are the things a strong model skips:

| # | Rule | Why it's here |
|---|------|---------------|
| 1 | **Accessibility identifier on every interactive control** — `control.setAccessibilityIdentifier("saveButton")`. This is **not** the VoiceOver label (`setAccessibilityLabel`/`accessibilityDescription`); both are needed and they are different things. | Identifiers are what `appkit-ui-testing` queries; baselines set a label and call it done. |
| 2 | **Semantic colors only** — `NSColor.labelColor`, `.secondaryLabelColor`, `.controlAccentColor`, `.textBackgroundColor`, `.controlBackgroundColor`, `.separatorColor`. Never literal RGB/hex; never assume a default for secondary text. | Hardcoded colors break Dark Mode, Increase Contrast, and accent tint. → `references/semantic-color.md` |
| 3 | **Semantic typography** — `NSFont.preferredFont(forTextStyle: .body)`, not `NSFont.systemFont(ofSize: 14)` for content text. (AppKit's signature adds an optional `options:`, default `[:]`.) | Respects the user's text size; the literal-size `ofSize:` form is the most common typography miss. → `references/typography.md` |
| 4 | **Content-derived window sizing** — size from the content view controller's `fittingSize` / Auto Layout, not a magic `900×640` frame. | Hardcoded frames clip or waste space across displays. → `references/window-sizing.md` |
| 5 | **Explicit Liquid Glass adoption** for the macOS 26/27 look — `NSGlassEffectView` / `NSVisualEffectView` materials and a real, populated unified toolbar. A table `style` or split-view sidebar gives you vibrancy in places, but **`.inset` is not Liquid Glass** and an empty `NSToolbar` renders nothing. | Baselines assert implicit glass they never actually adopt. → `references/liquid-glass.md` |

## Design workflow

### Step 1 — App type → anchor structure

Identify the app type; it fixes the window's spine. Then `appkit-search` the anchor pattern.

| App type | Anchor structure | Start from corpus |
|----------|------------------|-------------------|
| Settings / config / inspector tool | `NSSplitViewController` (sidebar + content [+ inspector]) | `splitviewcontroller-sidebar-inspector` |
| Document / editor | `NSWindowController` + content VC + unified `NSToolbar` | `windowcontroller-content-viewcontroller`, `unified-toolbar-window-style` |
| Browser / data-heavy | `NSSplitViewController` + view-based `NSTableView`/`NSOutlineView` | `tableview-view-based-reuse`, `outlineview-datasource-delegate` |
| Peer workflows / paged panes | `NSTabViewController` (toolbar tabs) | `tabviewcontroller-paged-panes` |
| Menu-bar utility | `NSStatusItem` menu bar extra | `statusitem-menubar-extra` |
| Single-purpose utility / form | `NSPanel` / window + `NSGridView` form | `gridview-label-field-form` |

→ Full mapping and window-structure code: `references/app-type-anchors.md`

### Step 2 — Requirement → canonical control

Map each requirement to a control, then `appkit-search get` the pattern. Don't write the plumbing from memory.

| Requirement | Control | Corpus pattern |
|-------------|---------|----------------|
| Sidebar / source list | `NSSplitViewItem(sidebarWithViewController:)` | `splitviewcontroller-sidebar-inspector` |
| Tabular data, selectable/sortable | **view-based** `NSTableView` + `NSTableViewDiffableDataSource` | `tableview-view-based-reuse`, `tableview-diffable-datasource` |
| Hierarchy / tree | `NSOutlineView` | `outlineview-datasource-delegate` |
| Tiles / grid | `NSCollectionView` + compositional layout | `collectionview-compositional-layout` |
| Toolbar | `NSToolbarDelegate` (don't skip the delegate) | `toolbar-delegate-itemforidentifier` |
| Form (label↔field rows) | `NSGridView` | `gridview-label-field-form` |
| Stacked controls / tool rows | `NSStackView` | `stackview-arranged-subviews` |
| Modal decision | `NSAlert` as async sheet | `nsalert-sheet-modal-async` |
| Transient detail | `NSPopover` | `nspopover-transient` |
| Pick one of few / modes | `NSSegmentedControl` | `segmented-control` |
| On/off | `NSSwitch` | `switch-slider-stepper-values` |
| File open/save | open/save panel + `UTType` | `open-save-panel-utype` |

→ Full control selection rationale + the deprecated forms to avoid (cell-based `NSTableView`, bare `NSSplitView`): `references/control-selection.md`

### Step 3 — Layout & spacing

Auto Layout via anchors; `NSStackView`/`NSGridView` for structure; HIG spacing metrics (don't invent paddings). → `references/layout-and-spacing.md`

### Step 4 — Size the window to its content

Derive the size from the layout's `fittingSize`, not a literal frame. Rubric + the `NSWindowController` setup that makes it work. → `references/window-sizing.md`

### Step 5 — Adopt Liquid Glass (macOS 26/27)

`NSGlassEffectView` (26.0) / `NSGlassEffectContainerView` (26.0) for floating glass chrome; `.effectIsInteractive` (27.0) for click-responsive glass; `NSVisualEffectView` materials for window/sidebar vibrancy; `NSViewCornerConfiguration` + `.containerConcentric` (27.0) for concentric corners; `NSScrollEdgeEffectStyle` (26.1) for scroll edges. **Gate everything below your deployment target with `if #available` — confirm each version with `appkit-api availability`.** → `references/liquid-glass.md`

### Step 6 — Accessibility baseline

Identifier on every interactive control (≠ label); semantic roles; respect Increase Contrast / Reduce Motion. → `references/accessibility.md`

## Anti-patterns

| ❌ Don't | ✅ Do | Why |
|----------|-------|-----|
| Cell-based `NSTableView` (`NSCell`, `dataCell`) | View-based: `makeView(withIdentifier:owner:)` + `NSTableCellView` | Cell-based is legacy; view-based is the modern reuse path |
| Bare `NSSplitView` for a sidebar | `NSSplitViewController` + sidebar `NSSplitViewItem` | Get collapsing, full-height layout, toolbar integration for free |
| `NSColor(red:green:blue:)` / hex literals | Semantic `NSColor` (`.labelColor`, …) | Survives Dark Mode + Increase Contrast |
| `NSFont.systemFont(ofSize: 14)` for body text | `NSFont.preferredFont(forTextStyle: .body, options: [:])` | Respects preferred text size |
| "`.inset` / a sidebar gives me Liquid Glass" | Explicit `NSGlassEffectView` / `NSVisualEffectView` + populated toolbar | Implicit vibrancy ≠ adopting glass; an empty toolbar renders nothing |
| Hardcoded `contentRect:` window frame | Content-derived sizing (`fittingSize`) | Adapts across displays |
| Overriding `mouseDown:` for clicks | Target-action / gesture recognizers / control events | → `appkit-modern-input`; `gesture-recognizers-basics` |
| Interactive control with no a11y identifier | `setAccessibilityIdentifier(_:)` on every one | Required for UI testing |
| Custom `NSView` subclass reimplementing a standard control | The standard control with configuration | Less code, free a11y + theming |

## Rationalizations — STOP if you think any of these

| Excuse | Reality |
|--------|---------|
| "It's just a code sketch, not a build task — I'll answer from memory." | The sketch is where wrong symbols enter. Run `appkit-search` + `appkit-api` anyway. |
| "I know `NSGlassEffectView`/this color/this font exists." | Then `appkit-api check` costs you 1 second to prove it and its min-macOS. Knowing isn't verifying. |
| "The sidebar/`.inset` style already gives the glass look." | Implicit material in one place ≠ adopting Liquid Glass. Adopt it explicitly where the design calls for it. |
| "I added an accessibility label, that covers a11y." | Label (VoiceOver text) ≠ identifier (UI-test handle). Set the identifier too. |
| "I'll size the window with a frame that looks about right." | Derive it from `fittingSize`. A guessed frame clips on the next display. |
| "HIG is for designers." | The corpus encodes HIG per pattern; `get` it. Control *behavior* (when a sheet vs a popover) is a HIG call. |

## References

| File | Read when… |
|------|------------|
| `references/app-type-anchors.md` | Choosing the window's anchor structure for an app type |
| `references/control-selection.md` | Mapping a requirement to the canonical control; avoiding deprecated forms |
| `references/layout-and-spacing.md` | Auto Layout, `NSStackView`/`NSGridView`, HIG spacing metrics |
| `references/semantic-color.md` | Semantic `NSColor`, Dark Mode, Increase Contrast, layer colors |
| `references/typography.md` | Semantic `NSFont` text styles, the `forTextStyle:options:` signature, system designs |
| `references/liquid-glass.md` | Adopting Liquid Glass / materials / concentricity with correct version gates |
| `references/window-sizing.md` | Content-derived window sizing rubric and setup |
| `references/accessibility.md` | Accessibility identifiers vs labels, semantic roles, the a11y baseline |
| `references/design-anti-patterns.md` | The full anti-pattern catalog with corrected code |

---
name: appkit-liquid-glass-concentricity
description: Use when updating a macOS AppKit app's look and feel for macOS 27 — picking up Liquid Glass refinements, the new interactive glass effect that responds to clicks, scroll edge effects, sidebar/toolbar changes, or making a custom NSView's rounded corners concentric with its container via NSViewCornerConfiguration / .containerConcentric. Targets macOS 27 / AppKit.
---

# AppKit Look & Feel for macOS 27: Liquid Glass + Concentricity

## Overview

In macOS 27 the Liquid Glass material (introduced in macOS 26) continues to evolve. **Many updates apply automatically just by building against the new SDK**; the main thing you opt into in code is **concentricity** — letting a view's corners follow the shape of its container.

Source: WWDC 2026 Session 289, "Modernize Your AppKit App."

## When to Use

- Updating an AppKit app's appearance for macOS 27 / verifying Liquid Glass adoption.
- A custom `NSView` near a container corner has rounded corners that fight the window's shape.
- You want controls to feel physically responsive (the new interactive glass effect).

## Liquid Glass updates: automatic vs. opt-in

If you adopted Liquid Glass in macOS 26, running on macOS 27 you get these **automatically**:

- `NSScrollEdgeEffectStyle` automatically resolves to a **hard-edge effect** when there's free-floating text, like the window title in the title bar.
- **Sidebars** extend to the window's edges; selection uses a **semi-bold text style** for emphasis; content still flows behind them.
- **Bordered toolbar items** over the sidebar adopt Liquid Glass.

**Opt-in:** the **interactive glass effect** (new in macOS 27) — glass that subtly *bounces when clicked*, giving the sense the control is responding to interaction. Maps uses it for a few custom controls.

- Use it **only** with controls and buttons, or glass containers of interactive controls. Not for every use of glass. **A little goes a long way.**
- The interactive-glass property is **`NSGlassEffectView.effectIsInteractive`** (`Bool`, get/set; macOS **27.0**) — SDK-verified with `sdk-api`. Gate it: `if #available(macOS 27, *) { glass.effectIsInteractive = true }`.

## Concentricity (`NSViewCornerConfiguration`)

Content meant for a corner can adapt to the shape of its container instead of feeling at odds with the window. **The closer a view sits to the container's corner, the more its radius should match.**

Steps:

1. **Subclass `NSView`.**
2. **Override `cornerConfiguration`** to return an `NSViewCornerConfiguration?`.
3. For the radius, use **`.containerConcentric(_:)` on `NSViewCornerRadius`** — it computes the radius from the container view. Pass a **minimum** so every corner is always rounded.
4. Pick a configuration factory; **`.uniformCorners(radius:)`** keeps the same radii on all four corners.

```swift
class LocalWeatherView: NSView {
    let minimumCornerRadius: CGFloat = 8

    override var cornerConfiguration: NSViewCornerConfiguration? {
        let radius: NSViewCornerRadius = .containerConcentric(minimumCornerRadius)
        return .uniformCorners(radius: radius)
    }
}
```

## Common Mistakes

- **Hardcoding `layer.cornerRadius` near a container corner.** That's exactly where `cornerConfiguration` + `.containerConcentric` belongs — audit those sites first.
- **Applying interactive glass everywhere.** Restrict it to interactive controls/buttons or their glass containers.
- **Guessing a macOS 27 symbol.** The interactive-glass property is `NSGlassEffectView.effectIsInteractive` (27.0) — verify any new symbol with `sdk-api check` rather than inventing one. (This property is the exact "TBD" that motivated building `sdk-api`.)

## Recap

Re-link against the macOS 27 SDK to pick up the automatic Liquid Glass refinements; adopt interactive glass sparingly on controls; and evaluate your view hierarchies to adopt concentricity in views and buttons near corners.

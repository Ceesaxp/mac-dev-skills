---
name: apple-hig
description: Use when a design decision turns on what the Apple Human Interface Guidelines actually say — the HIG rule/spec/best-practice for a control, pattern, layout, color, typography, accessibility, or platform convention; verifying a design claim against Apple's guidance; or needing an exact HIG specific (hit-target size, when to use one control vs another, per-platform behavior) for macOS/AppKit or any Apple platform. Bundles the complete HIG offline (snapshot 2026-06-10).
---

# Apple HIG (offline)

## Overview

This skill bundles the **complete Apple Human Interface Guidelines** as offline markdown — every control, pattern, foundation, technology, and input across **all Apple platforms** (iOS, iPadOS, macOS, tvOS, visionOS, watchOS, games), not just macOS. Snapshot: **2026-06-10**, sourced from `developer.apple.com/design/human-interface-guidelines`. Each file carries its source URL in frontmatter and links to related topics with relative links, so the tree self-navigates.

**Core principle: when a question turns on a HIG rule, open the actual file and answer from it — do not recite the HIG from memory.** Memory is where the wrong number and the invented "best practice" come from. The whole point of bundling the text is that the authoritative answer is one `grep`/`Read` away.

## The grounding mandate

A question is HIG-grounded when it asks **what Apple recommends, requires, or specifies** — the right control for a job, when to use A vs B, an exact metric (hit targets, layout margins, icon sizes), a platform convention, or whether a design claim is actually in the guidelines. For any of those:

1. **Find the file** (three ways, fastest first):
   - **Guess the kebab-case filename** — topics map directly: `buttons.md`, `sheets.md`, `color.md`, `sf-symbols.md`, `the-menu-bar.md`, `designing-for-macos.md`.
   - **Grep the corpus** — `grep -rl "<keyword>" references/hig/` when the filename isn't obvious.
   - **Scan the index** — `references/hig/INDEX.md` is the full topic list grouped by section, each with a one-line blurb. Use it to disambiguate.
2. **Read it and answer from the text** — quote or paraphrase the actual rule, and **name the file** you used (e.g. "per `buttons.md`…"). The frontmatter `url:` is the canonical source if the user wants to follow up.

Do not skip step 1 because the answer "seems obvious." The HIG specifics (the *exact* hit target, the *exact* condition for a sheet vs a popover) are precisely what gets misremembered.

## Section map — where things live

The HIG's six top sections; each `*.md` is a browse index linking its children.

| Section | What's in it | Index file |
|---------|--------------|------------|
| **Getting started** | Per-platform design guides + cross-platform principles | `references/hig/getting-started.md` |
| **Foundations** | Accessibility, color, dark mode, layout, materials, motion, typography, SF Symbols, icons, privacy, writing, inclusion, right-to-left | `references/hig/foundations.md` |
| **Components** | The control catalog — buttons, menus, toolbars, sheets, popovers, split views, lists/tables, sidebars, pickers, text fields, windows, panels, … (sub-grouped by Content / Layout / Menus / Navigation / Presentation / Selection / Status / System) | `references/hig/components.md` |
| **Patterns** | Task/experience guidance — modality, drag and drop, entering data, feedback, launching, onboarding, settings, undo/redo, searching, file management | `references/hig/patterns.md` |
| **Technologies** | Apple frameworks/services — Apple Pay, HealthKit, HomeKit, Maps, Sign in with Apple, Wallet, Siri, Machine learning, Generative AI, … | `references/hig/technologies.md` |
| **Inputs** | Control methods — keyboards, pointing devices, gestures, Apple Pencil, Digital Crown, Action button, game controls, eyes | `references/hig/inputs.md` |

**Full topic index with blurbs:** `references/hig/INDEX.md`.

## Relationship to appkit-design

These are complementary, not redundant:

- **`apple-hig` (this skill) = the authority on *what* and *why*.** Which control the HIG calls for, when to use a sheet vs a popover, the exact rule, the cross-platform convention. It is *prose guidance*, all platforms.
- **`appkit-design` = *how* to build it in modern AppKit.** Symbol-verified macOS 26/27 code, the control-selection corpus, Liquid Glass, semantic color/typography, window sizing — backed by the `sdk-search`/`sdk-api` tools.

For macOS UI work, use both: settle the design decision against the HIG here, then implement it with **`appkit-design`**. When a HIG topic has a macOS-specific control mapping (e.g. "sidebar" → `NSSplitViewItem(sidebarWithViewController:)`), `appkit-design` is where that mapping lives.

## Provenance & staleness

This is a **point-in-time snapshot (2026-06-10)**, not a live feed. It's authoritative for everything Apple had published as of that date. When a question is about a very recent OS change, or the user needs the current live wording, say the snapshot date and point them at the `url:` in the relevant file's frontmatter (or `developer.apple.com/design/human-interface-guidelines`) to confirm against the live HIG.

## Red flags — STOP if you think any of these

| Thought | Reality |
|---------|---------|
| "I know what the HIG says about buttons/sheets/color." | Then opening `buttons.md` costs one `Read` and proves it — including the exact number you're about to misquote. |
| "It's a quick design question, I'll just answer." | If it turns on a HIG rule, it's grounded. Find the file first. |
| "Close enough to the guideline." | "44×44 pt, 60×60 in visionOS" is the kind of specific that's only right if you read it. |
| "I'll cite the HIG without naming a file." | Name the file. An ungrounded "per Apple's guidelines" is indistinguishable from a guess. |
| "This snapshot is the live HIG." | It's dated 2026-06-10. For the newest wording, point at the source URL. |

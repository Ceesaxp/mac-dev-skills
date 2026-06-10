# mac-dev-skills

A Claude Code plugin for modern **macOS 26/27 AppKit** development — the macOS counterpart to Microsoft's `win-dev-skills`. Skills, an orchestrator agent, and grounded native Swift tooling that stops the agent guessing.

## Install
Add this marketplace, then install the `appkit` plugin:
- `/plugin marketplace add malstrom/mac-dev-skills`
- `/plugin install appkit`

## What's inside
- **13 skills** under `plugins/appkit/skills/` — `appkit-design` (the flagship: control selection, layout, semantic color/typography, Liquid Glass, window sizing, a11y — wired to both tools), setup, dev-workflow, code-review, ui-testing, packaging (Developer ID + TestFlight + Mac App Store), migration, three macOS-26/27 modernization skills (launch-continuity, modern-input, liquid-glass-concentricity), `appkit-private-apis` + `appkit-app-inspector` (advanced / dual-use), and `appkit-session-report`.
- **`appkit-dev` agent** — builds AppKit apps end-to-end.
- **Native tools** in `src/tools/` — `appkit-api` (SDK API + availability validator) and `appkit-search` (AppKit/HIG pattern search). Build them with `scripts/build-tools.sh`.

## Building the tools
```bash
scripts/build-tools.sh
```
Requires Xcode 26 or 27 (the macOS SDK), Swift 6.

## Status
Active development. See `docs/superpowers/specs/` for the design and `docs/superpowers/plans/` for implementation plans.

# Changelog

## [Unreleased]
### Added
- `appkit` plugin scaffold: marketplace + plugin manifests; 9 relocated AppKit skills + `appkit-dev` agent.
- `appkit-api` tool: SDK API + availability validator (symbol-graph backed) — `check`, `members`, `availability`, `search`, `enums`; built/signed/installed by `scripts/build-tools.sh`.
- `appkit-search` tool: BM25 search over a curated 69-pattern, HIG-grounded corpus — `search`, `get`, `list`, `debug`.
- `appkit-design` (flagship): control selection, layout & spacing, semantic color/typography, Liquid Glass, window sizing, accessibility — wired to `appkit-api` + `appkit-search`, with 9 references.
- `appkit-private-apis`: PrivateHeaderKit header dumps, declaring/calling private APIs, method swizzling; distribution advisory.
- `appkit-app-inspector`: drives flexscope runtime view inspection (doctor gate → filter→drill → AppKit recipe); dev-box-only.
- `appkit-session-report`: wraps `analyze-session.py` with a privacy gate (user-invoked).
- `appkit-packaging` elevated: Developer ID + TestFlight + Mac App Store (ASC API key, ExportOptions, App Sandbox) + 3 ship scripts.

### Fixed
- `build-tools.sh` installs `appkit-search`'s resource bundle alongside the binary (it fatal-errored on every query without it).
- Corpus compile-audit: all 69 `appkit-search` snippets typecheck against the macOS 27 SDK (13 latent won't-compile bugs fixed).

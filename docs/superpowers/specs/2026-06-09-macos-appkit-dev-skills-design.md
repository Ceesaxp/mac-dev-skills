# macOS AppKit Dev Skills — Design Spec

- **Date:** 2026-06-09
- **Status:** Approved (pending written-spec review)
- **Author:** mark@malstrom.me + Claude
- **Goal:** A polished Claude Code plugin suite for modern (macOS 26/27) AppKit development that rivals Microsoft's `win-dev-skills` (WinUI 3) — skills, an agent, native Swift tooling, and a TestFlight/Mac-App-Store-tailored distribution story.

---

## 1. North star

`win-dev-skills`' soul is **grounded native tooling that stops the agent guessing** (a BM25 sample search, a WinMD API/metadata CLI, a Roslyn analyzer) wrapped in a clean plugin + an orchestrator agent. We replicate that shape for AppKit, lean on the ~80% of skill prose that already exists in draft, fill the gaps (a flagship `appkit-design`, advanced dual-use skills, a session-report wrapper), and build the two highest-value Swift tools now (an SDK API/availability validator and an AppKit/HIG pattern search), deferring the lint/analyzer.

House style is inherited from the sibling `xcode-27-skills`: a **lean `SKILL.md` + a `references/` directory of focused task files**. `uikit-app-modernization` is the structural template.

## 2. Inputs (what exists today)

| Source | Contents | Use |
|---|---|---|
| `claude-brainstorm/` | 5 complete draft skills (`code-review`, `ui-testing`, `dev-workflow`, `setup`, `migration`), root `appkit-packaging` SKILL + `ci-and-app-store.md`, `Project.swift` (Tuist), `builkd-and-run.sh` (typo), `analyze-session.py`, README | Relocate + polish into the plugin |
| `modernize-appkit/` | 3 WWDC-2026 skills (`launch-continuity`, `modern-input`, `liquid-glass-concentricity`) + session-289 transcript/code | Relocate + polish; seed `appkit-search` corpus |
| `xcode-27-skills/` (sibling) | SwiftUI/UIKit/Xcode skills | House-style reference only (not vendored) |
| `.swift-format` | Strict swift-format config (no force-unwrap, ordered imports, 120 cols, 4-space) | Shared config used by `appkit-code-review` + tools |
| `flexscope` (separate repo) | Spec-complete, **unimplemented** running-app inspector CLI (FLEX injection, JSON-over-socket) | `appkit-app-inspector` drives its frozen CLI contract |
| PrivateHeaderKit (external) | CLI that dumps private framework headers from the live system | `appkit-private-apis` documents dump → browse → call → swizzle |

## 3. Architecture

### 3.1 Repo / plugin layout

```
mac-dev-skills/                              # cwd; becomes the plugin repo root
├── .claude-plugin/marketplace.json
├── .codex-plugin/marketplace.json          # Codex variant (cheap parity with win-dev)
├── README.md  CONTRIBUTING.md  CHANGELOG.md  LICENSE
├── .swift-format                           # shared (already present)
├── docs/superpowers/specs/                 # this spec lives here
├── plugins/appkit/
│   ├── plugin.json
│   ├── .claude-plugin/plugin.json
│   ├── agents/appkit-dev.agent.md
│   └── skills/
│       ├── appkit-setup/
│       ├── appkit-dev-workflow/            # ships build-and-run.sh + templates/Project.swift
│       ├── appkit-design/                  # NEW flagship; references/ + invokes both tools
│       ├── appkit-code-review/             # references/quality-rules.md + .swift-format
│       ├── appkit-ui-testing/
│       ├── appkit-packaging/               # references/ci-and-app-store.md + scripts/
│       ├── appkit-migration/
│       ├── appkit-launch-continuity/
│       ├── appkit-modern-input/
│       ├── appkit-liquid-glass-concentricity/
│       ├── appkit-private-apis/            # NEW
│       ├── appkit-app-inspector/           # NEW (flexscope driver)
│       └── appkit-session-report/          # NEW; ships analyze-session.py
├── src/tools/
│   ├── appkit-api/                         # Swift CLI — SDK API + availability validator
│   │   ├── Package.swift  Sources/  Tests/ (Swift Testing)
│   └── appkit-search/                      # Swift CLI — AppKit/HIG pattern search (BM25)
│       ├── Package.swift  Sources/  Tests/ (Swift Testing)  Data/ (curated corpus)
└── scripts/build-tools.sh                  # builds + ad-hoc-signs tools into skill dirs
```

### 3.2 Binary distribution decision

We do **not** commit prebuilt unsigned binaries (notarization/trust friction; contradicts the suite's security-conscious posture). Instead:

- Tool **source** lives in `src/tools/`.
- `scripts/build-tools.sh` builds release binaries with SwiftPM and ad-hoc-signs them, copying each into the skill dir that uses it (and/or `~/.local/bin`).
- `appkit-setup` runs `build-tools.sh` as part of machine setup.
- Each skill that invokes a tool checks for the binary first and, if missing, instructs the user to run `build-tools.sh` (never silently fails).

This is the same model flexscope uses for its own dev-box-only artifacts.

## 4. Skill roster (13)

Status legend: **have** (draft exists, polish), **NEW** (write from scratch).

| # | Skill | Status | Purpose | Tool wiring |
|---|---|---|---|---|
| 1 | `appkit-setup` | have → extend | Xcode 26/27, license, Homebrew, Tuist, swift-format, create-dmg; **builds native tools**; optional checks for PrivateHeaderKit + `flexscope doctor` | builds `appkit-api`, `appkit-search` |
| 2 | `appkit-dev-workflow` | have → polish | Tuist + `build-and-run.sh` inner loop; error table; prerequisites; critical rules | — |
| 3 | `appkit-design` | **NEW (flagship)** | App-type → anchor control; control selection; layout/spacing; semantic colors; typography; Liquid Glass adoption; window sizing; a11y baseline; design anti-patterns | `appkit-search` (canonical patterns) + `appkit-api` (verify symbols) |
| 4 | `appkit-code-review` | have → polish | swift-format + grep patterns + manual checklists (MVC/MVVM, Swift 6 concurrency/main-actor, retain cycles, a11y, theming, security, perf, localization) | `appkit-api` (availability sanity) |
| 5 | `appkit-ui-testing` | have → polish | **XCUITest** batch suite, element/value assertions, sheets/panels/menus, a11y audit, visual checklist | — |
| 6 | `appkit-packaging` | have → **elevate** | Developer ID (codesign/notarytool/staple/dmg), **TestFlight**, **Mac App Store** (ASC API key, ExportOptions, App Sandbox), CI; **private-API distribution advisory** | scripts/ |
| 7 | `appkit-migration` | have → polish | UIKit/Catalyst → AppKit, Electron/web → AppKit, ObjC → Swift | — |
| 8 | `appkit-launch-continuity` | have → polish | Graceful termination + `NSWindowRestoration` state restoration | `appkit-api` |
| 9 | `appkit-modern-input` | have → polish | Replace `mouseDown:` with view APIs/control events/gestures; status items; key-view loop | `appkit-api` |
| 10 | `appkit-liquid-glass-concentricity` | have → polish | macOS 27 Liquid Glass refinements; interactive glass; `NSViewCornerConfiguration` concentricity | `appkit-api` (**resolve the currently-TBD interactive-glass symbol**) |
| 11 | `appkit-private-apis` | **NEW** | Dump headers via PrivateHeaderKit; browse/grep; declare & call private APIs (ObjC runtime / `dlsym` / bridging); **method swizzling** patterns (exchange, restore, thread-safety, when/why); distribution advisory | — |
| 12 | `appkit-app-inspector` | **NEW** | Drive flexscope to learn from running apps: `doctor` gate → `windows`/`find --count-only` → `find --where --fields` → deep-read `node`/`font`/`layer`/`constraints`; map findings to your own AppKit/Liquid Glass code | flexscope |
| 13 | `appkit-session-report` | **NEW** | Wrap `analyze-session.py`; privacy notice; report sections | `analyze-session.py` |

**13 skills total** — the directory list under `plugins/appkit/skills/` in §3.1 is canonical.

**`disable-model-invocation: true`** on `appkit-setup` and `appkit-session-report` (user-invoked only), matching win-dev-skills.

## 5. Native tools (built here)

### 5.1 `appkit-api` — SDK API + availability validator (highest value)

**Problem solved:** the agent should never guess whether a symbol exists or what macOS version it needs — the exact failure mode in `appkit-liquid-glass-concentricity` ("interactive-glass API name TBD, verify in docs").

**Data source (verified 2026-06-09):** `swift symbolgraph-extract` JSON, not `.swiftinterface`. AppKit is an Objective-C framework whose availability lives in headers/apinotes, so a Swift interface is incomplete — but the symbol graph captures everything through the importer. Verified on this machine (Xcode 27 / macOS 27 SDK): `AppKit.symbols.json` = 16,933 symbols, each carrying `availability` (`{domain, introduced:{major,minor}, deprecated, message}`). It correctly reports `NSGlassEffectView` → macOS 26.0, `NSViewCornerConfiguration` → 27.0, `NSScrollEdgeEffectStyle` → 26.1, and **resolves the modern skill's currently-"TBD" interactive-glass API to `NSGlassEffectView.effectIsInteractive` (macOS 27.0)**. Extraction command:

```
swift symbolgraph-extract -module-name <Module> \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macos<ver> \
  -minimum-access-level public -output-dir <cache>
```

**Critical:** resolve the SDK with `xcrun --sdk macosx --show-sdk-path` (bare `xcrun` can resolve to a broken Command Line Tools SDK). Extraction of AppKit takes ~30s and emits ~31MB, so results are cached under `~/Library/Caches/appkit-api/<sdk-version>/<module>/` and reused until the SDK version changes. Symbol structure: `names.title`, `kind.identifier`, `pathComponents` (qualified name), `declarationFragments` (→ signature), `availability`; `relationships[kind=memberOf]` maps members to their container type.

**Verbs (JSON out):**
- `appkit-api search <query>` — fuzzy across types/members
- `appkit-api members <Type>` — members + signatures + availability
- `appkit-api check <Type>.<member>` — exists? → `{exists, availability, deprecated}`
- `appkit-api availability <symbol>` — min OS / deprecation
- `appkit-api enums <Type>` — cases

**Cache:** structured JSON under `~/Library/Caches/appkit-api/`, keyed by SDK build + framework; auto-refresh when the SDK path/build changes.

**Build:** SwiftPM executable, ArgumentParser, release + ad-hoc-signed by `build-tools.sh`. **Tests: Swift Testing** (parser fixtures from checked-in `.swiftinterface` snippets; parameterized cases for availability extraction).

### 5.2 `appkit-search` — AppKit/HIG pattern search (analog to `winui-search`)

**Problem solved:** "show me canonical code for X" without runtime scraping.

**Corpus (v1 = curated, embedded JSON in `Data/`):** canonical AppKit patterns — control selection, view-based `NSTableView`, `NSSplitViewController`, `NSToolbar`, sheets/panels, `NSGlassEffectView`/Liquid Glass, concentricity, state restoration, modern input — seeded from the WWDC-2026 session-289 code and hand-curated snippets. (Apple has no clean WinUI-Gallery analog to scrape; live sample-fetch is a documented later enhancement, not v1.)

**Grounding (mandatory — two authorities per pattern):**
1. **Apple HIG** for *canonical behavior* — when to use which control, layout/spacing conventions, the platform "feel". Every corpus entry's `whenToUse` guidance and control choice must be grounded in the relevant macOS Human Interface Guidelines page (`developer.apple.com/design/human-interface-guidelines/…`), and the entry carries a `higReference` (section title + URL). Corpus authors MUST consult the live HIG page for their pattern (WebFetch) and cite it; a quality gate rejects patterns whose guidance contradicts or omits the HIG.
2. **`appkit-api`** for *symbol/availability correctness* — every `keySymbol` and `minMacOS` in an entry is machine-verified against the SDK with the tool we shipped in Phase 1a.

So each pattern = HIG-grounded *guidance* + API-verified *code*. The schema therefore includes at least `whenToUse` and `higReference` fields in addition to the code/imports/pitfalls/availability fields.

**Verbs:** `appkit-search search "<feature>" …` (batch) · `get <id> …` · `list [--tag]`. Output: shortlist (search) → full snippet + namespace/import hints + pitfalls + HIG reference (get). Engine: BM25 + stop-words + synonyms (port the win-dev approach).

**Build/tests:** SwiftPM executable; **Swift Testing** for BM25 scoring, tokenization, and corpus-integrity tests.

## 6. External tool integration

### 6.1 flexscope (`appkit-app-inspector`)

- flexscope is the user's **separate, greenfield** repo — not vendored here. The skill targets its **frozen CLI contract** (doctor/windows/tree/find/node/font/layer/constraints/ax-diff, JSON-Lines, exit codes).
- `appkit-setup` builds flexscope **only if present** at its path; otherwise the skill explains how to obtain/build it.
- Skill workflow: **`doctor` gate first** (must be all-green; report remediation verbatim on failure) → canonical **filter → drill** loop (`windows` / `find --count-only` → `find --where --fields --limit` → deep-read one survivor) → translate runtime facts (real class, font, constraints, `CALayer.backgroundFilters`) into the developer's own AppKit code.
- **Dev-box reality** stated plainly: requires SIP/AMFI/library-validation disabled; the tool is never shipped; only *knowledge* crosses into the product.

### 6.2 PrivateHeaderKit (`appkit-private-apis`)

- Install via its own `swift run -c release privateheaderkit-install`; dump with `privateheaderkit-dump` / `headerdump`.
- Skill covers: dump → grep/browse generated headers → declare the interface (ObjC category / bridging header / `@objc` protocol / `dlsym` for C) → call it → **swizzle** (`method_exchangeImplementations`, capturing & calling the original, restoration, thread-safety, idempotent install, when it's appropriate vs. fragile).
- PrivateHeaderKit ships **no** usage/safety guidance — that guidance is original to this skill.

## 7. Private-API & distribution stance (advisory, never a gate)

The suite **never prevents** a developer from using or shipping private APIs, swizzling, or techniques learned via flexscope. It **informs**:

- Private-API usage **may or may not** pass App Store review — Apple judges case-by-case; not all private-API usage is auto-rejected.
- If a build is rejected, the developer can still distribute via **Developer ID + notarization** (web / Sparkle / direct download).
- `appkit-packaging` surfaces this as a **distribution advisory** and cross-references `appkit-private-apis` and `appkit-app-inspector`; those skills carry a reciprocal one-line advisory pointing back to packaging.
- flexscope-the-binary is a dev-box-only inspection tool and isn't something you ship regardless — but anything you *learn* from it is fair game (subject to the same review caveat).

The tone is "here's the trade-off and your options," not "you may not."

## 8. The agent

`plugins/appkit/agents/appkit-dev.agent.md` — `user-invocable: true`. Orchestrator that owns build end-to-end:
- Loads `appkit-dev-workflow` + `appkit-design` by default.
- Knows the native tools and prefers them over guessing.
- Enforces: Swift 6 strict concurrency / main-actor correctness; **accessibility identifiers on every interactive control**; no hardcoded colors/fonts; semantic AppKit APIs.
- Aware of the Developer-ID-vs-MAS fork and the advisory stance.
- Efficiency directives (batch edits, don't re-read just-written files, chain dependent commands).

## 9. Distribution emphasis (TestFlight + Mac App Store)

Concentrated in `appkit-packaging` + `references/ci-and-app-store.md` + `scripts/`:
- **Developer ID:** `codesign` → `notarytool submit --wait` → `stapler` → signed `.dmg`/`.pkg` (`create-dmg`).
- **TestFlight + MAS:** App Store Connect **API-key** auth, `ExportOptions.plist` templates, App Sandbox + entitlements, archive → export → upload (`xcrun altool`/`notarytool`/Transporter), internal/external testers, review notes.
- **Scripts:** `notarize.sh`, a TestFlight upload script, a MAS export/submit script (all using ASC API key, no interactive passwords).
- Repo discipline stays **lean** (README/CONTRIBUTING/CHANGELOG/`build-tools.sh`); Microsoft-style provenance CI is explicitly **out of scope for now**.

## 10. Testing strategy

- **Swift Testing is the default** for everything that can use it: `appkit-api` and `appkit-search` test suites, plus any logic tests in templates/samples (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`, parameterized `@Test(arguments:)`).
- **XCUITest (XCTest) is retained only where Swift Testing cannot go** — UI automation in `appkit-ui-testing` (Swift Testing has no UI-automation API as of 2026). The skill notes Swift Testing and XCTest **coexist in one target**, and that only UI automation stays on XCTest.
- **Skill TDD (writing-skills Iron Law):**
  - NEW skills (`design`, `private-apis`, `app-inspector`, `session-report`): full RED (subagent baseline) → GREEN (write) → REFACTOR (close loopholes).
  - Polished drafts: application-scenario verification with a subagent; fix gaps surfaced.
- **Tools:** classic TDD — write Swift Testing cases against fixtures before/with implementation.

## 11. Phasing (one spec → a plan per phase)

0. **Scaffold** — plugin repo, `marketplace.json` (+ codex), `plugin.json`, **copy** the 9 existing skills from `resources/` (gitignored reference inputs) into `plugins/appkit/skills/` verbatim (no content edits → no Iron-Law trip; polish comes later under TDD), fix `builkd-and-run.sh` → `build-and-run.sh`, author `appkit-dev` agent.
1. **Tools** — `appkit-api` (first), then `appkit-search`; `build-tools.sh`; wire into `appkit-setup`. Swift Testing suites.
2. **Flagship** — `appkit-design` wired to both tools, with `references/`.
3. **Advanced/dual-use** — `appkit-private-apis` + `appkit-app-inspector`; the advisory cross-references.
4. **Distribution** — elevate `appkit-packaging` (TestFlight + MAS) + scripts; `appkit-session-report`.
5. **Polish** — suite-wide TDD verification, README/CONTRIBUTING/CHANGELOG, consistency pass.

## 12. Defaults chosen (redline anytime)

- Tool names: `appkit-api`, `appkit-search`. Inspector skill: `appkit-app-inspector`.
- Ship a Codex `marketplace.json` variant alongside Claude.
- `appkit-search` corpus is curated/embedded for v1; live sample-fetch deferred.
- Repo is git-initialized as part of Phase 0 (it isn't a git repo yet).

## 13. Out of scope (YAGNI, for now)

- SwiftSyntax lint/analyzer (planned, deferred per decision).
- Microsoft-style release CI: version-sync, binary provenance checks, branch/promotion model.
- Live/online sample scraping for `appkit-search`.
- Vendoring flexscope or PrivateHeaderKit source into this repo.
- Shipping prebuilt/notarized tool binaries.

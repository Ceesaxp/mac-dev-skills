# Handoff — `mac-dev-skills` (status through Phase 1b)

- **Date:** 2026-06-09
- **Branch:** `feat/appkit-search` (ready to merge to `main`)
- **Repo:** `/Users/orion/Developer/Templates/skills/mac-dev-skills`

## What this project is

Building `mac-dev-skills` — a Claude Code plugin suite for modern (macOS 26/27) AppKit development that rivals Microsoft's `win-dev-skills`.

## Status

- **Phase 0** ✅ shipped (merged to main) — plugin scaffold: marketplace + plugin manifests, 9 relocated AppKit skills, `appkit-dev` agent.
- **Phase 1a** ✅ shipped (merged to main) — `appkit-api`: SDK API/availability validator (symbol-graph backed, Swift Testing).
- **Phase 1b** ✅ shipped (merged to main) — `appkit-search`: BM25 search over a **curated 69-pattern corpus** of canonical AppKit patterns. Engine: faithful winui-search BM25 port, 4 CLI verbs, **44 Swift Testing tests**. Corpus: 69 patterns, HIG-grounded, keySymbols verified against the macOS 27 SDK.
- **Phase 2** ✅ shipped (merged to main, `7a3dfd4`) — `appkit-design` flagship skill wired to both tools.
  - `SKILL.md` (grounding mandate + hygiene checklist + 6-step workflow + anti-patterns + rationalization table) + 9 `references/` (app-type anchors, control selection, layout & spacing, semantic color, typography, Liquid Glass, window sizing, accessibility, anti-patterns) — each HIG-grounded and `appkit-api` symbol-verified.
  - Authored under the writing-skills loop: **RED** (4 baselines without the skill: tool-use 1/4, a11y identifiers 0/4, hardcoded frames, false `.inset`==glass) → **GREEN** → **adversarial symbol-audit** → **GREEN-verify** (4/4 ground with the tools, set a11y identifiers, derive window size, adopt glass explicitly; **0 evasions**).
  - Fixed `build-tools.sh` to install `appkit-search`'s resource bundle next to the binary (it was fatal-erroring on every real query).
  - **Audit found + fixed 2 latent 1b corpus bugs** (passed structural tests, wouldn't compile): read-only `NSView.cornerConfiguration` was *assigned* (→ override the getter) in 2 patterns; 6 patterns cited the dead `/human-interface-guidelines/tables` (→ `/lists-and-tables`).
  - `appkit-dev` agent un-hedged: loads `appkit-design` by default.
  - Reusable audit harness committed at `scripts/wf-appkit-design-audit.js` (generalize for Phase 5).

- **Phase 3** ✅ shipped (merged to main) — the two dual-use skills + the §7 advisory cross-references.
  - `appkit-private-apis` (SKILL.md + 4 refs): discover → declare (category / bridging / `@objc` protocol / `dlsym`) → call → swizzle (IMP-capture + restoration + idempotent + when-not-to). PrivateHeaderKit for discovery — **static dump, no SIP needed**. Every ObjC-runtime symbol SDK-verified.
  - `appkit-app-inspector` (SKILL.md + 4 refs): drive **flexscope** (the user's separate repo at `/Users/orion/Developer/Projects/flexscope`, spec-complete/unbuilt) against its **frozen CLI contract** — doctor gate (6 checks → exit 6) → filter→drill (never full-dump) → translate to an AppKit recipe. **flexscope = runtime injection, dev-box only (SIP+AMFI+LV off).** Authored against the frozen spec; unspecified flag defaults left as "see --help".
  - `appkit-packaging` carries the reciprocal **distribution advisory** (review is case-by-case; Developer ID + notarization is the escape hatch; scanner-evasion ≠ safety; tooling never ships, only knowledge crosses).
  - writing-skills loop for both: RED (caveat/dual-use/restoration gaps) → GREEN → adversarial audit (private-apis 5/5 clean; fixed 4 flexscope spec-accuracy bugs in app-inspector) → GREEN-verify (4/4 scenarios, 0 residual, 0 evasions).
  - Audit harness committed at `scripts/wf-appkit-phase3-audit.js`.

**Next:** Phase 4 (elevate `appkit-packaging` — TestFlight + MAS scripts; author `appkit-session-report`).

**⚠️ Phase 4 carry:** `appkit-packaging/SKILL.md` references a bundled `notarize.sh` (lines ~42/163/198) that **does not exist yet** — Phase 4 adds the `scripts/` (`notarize.sh`, TestFlight, MAS). **Phase 5 carry:** update `appkit-setup` to build flexscope **if present** at its path and check for PrivateHeaderKit (the `appkit-app-inspector` skill explains how to obtain/build flexscope in the meantime).

**⚠️ Carry into Phase 5:** the corpus integrity tests do **not** compile the `swiftCode`. The audit only spot-checked the 2 corner patterns it touched — a **suite-wide compile/symbol audit of all 69 patterns' `swiftCode`** is warranted (generalize `scripts/wf-appkit-design-audit.js`). Also note: `appkit-api check` resolves protocol-declared members under their **protocol owner** (e.g. `setAccessibilityIdentifier` under `NSAccessibilityProtocol`, not `NSView`) — a not-found on `Type.member` is not automatically a hallucination.

➡️ **For Phases 2–5, read `docs/superpowers/plans/2026-06-09-phases-2-5-handoff.md`** — it has the per-phase plan, the verified skill-status table, and the process rules (writing-skills Iron Law, symbol-grounding with `appkit-api`, adversarial review, Workflow-tool gotchas).

---

## ⬇️ The section below documents Phase 1b's build for reference; it is now DONE.

## Design docs (read first)

| File | Purpose |
|------|---------|
| `docs/superpowers/specs/2026-06-09-macos-appkit-dev-skills-design.md` | Full suite spec — all 13 skills + 2 native tools + architecture |
| `docs/superpowers/plans/2026-06-09-appkit-search-tool.md` | Phase 1b planned architecture |
| `docs/superpowers/plans/2026-06-09-appkit-search-design-output.json` | Engine spec (BM25 params, synonyms, tokenizer, field weights) + 69-pattern taxonomy from the design workflow |

## What's DONE (committed on `feat/appkit-search`)

### Engine — 4 TDD layers, 43 Swift Testing tests pass, 4 CLI verbs work

```
src/tools/appkit-search/
├── Package.swift                           # swift-tools-version 6.0, targets: AppKitSearchCore (lib, resources Data/), appkit-search (exec), AppKitSearchCoreTests
├── Sources/AppKitSearchCore/
│   ├── Tokenizer.swift                     # BM25.Tokenize port: invariant lowercase, [^a-z0-9\s\-] strip, space split, len>1 + stopword filter
│   ├── StopWords.swift                     # ~180 common stopwords + tagOnly set, FilterTagList helper
│   ├── Synonyms.swift                      # 3-mechanism pipeline: Preprocess (phrases + stemming), Expand (Map, compound-suffix guard)
│   ├── BM25.swift                          # Faithful port: k1=1.2, b=0.75, weighted-field tf, idf=log((n-df+0.5)/(df+0.5)+1) with Lucene guard
│   ├── SearchEngine.swift                  # Full pipeline: Preprocess→Tokenize→Expand→Score, name boosts, platform-keyword boost, generic demotion, 70% floor, raw-token coverage gate
│   ├── Pattern.swift                       # Codable struct for all 14 corpus fields
│   ├── Corpus.swift                        # Bundle.module loader, shared singleton
│   ├── Output.swift                        # DTOs: SearchOutput, BatchSearchOutput, PatternOutput, ListOutput, DebugOutput, emitJSON, NormalizeIndent, isBoilerplateStub
│   └── Data/patterns.json                  # PLACEHOLDER: 4 patterns (glass-effect-view-basic, concentric-corner-configuration, tableview-view-based-reuse, splitviewcontroller-sidebar-inspector)
├── Sources/appkit-search/
│   └── AppKitSearch.swift                  # @main CLI: search/get/list/debug subcommands with cross-query dedup, AnyEncodable
└── Tests/AppKitSearchCoreTests/
    ├── TokenizerTests.swift                # 43 tests across all layers
    ├── BM25Tests.swift
    └── CorpusIntegrityTests.swift
```

Key commits (from tip):
```
391126f feat(appkit-search): layer 4 — CLI subcommands + Output DTO public inits
46c04ee feat(appkit-search): layer 3 — corpus integrity tests (TDD)
adb61aa feat(appkit-search): layer 2 — BM25 scoring + flat ranking (TDD)
009e10a feat(appkit-search): layer 1 — tokenizer + synonym pipeline (TDD)
```

### Live verification of the engine (you can run this)

```bash
cd src/tools/appkit-search
swift build                                    # builds cleanly
swift test                                     # 43 tests pass
swift run appkit-search search "concentric corners"  # ranks concentric-corner-configuration first
swift run appkit-search search glass --max 2   # surfaces glass-effect-view-basic
swift run appkit-search get glass-effect-view-basic  # full pattern JSON with HIG reference
swift run appkit-search list                   # grouped by category
swift run appkit-search get nope; echo $?      # exits 1 on not found
```

## What REMAINS (the corpus — the real product)

The engine works perfectly, but `Data/patterns.json` is a **placeholder** (4 patterns). The design taxonomy specifies **69 patterns** (31 high, 34 medium, 4 low) across 16 categories. They need to be authored and verified.

### The taxonomy is in `docs/superpowers/plans/2026-06-09-appkit-search-design-output.json`

```bash
python3 -c "
import json
r=json.load(open('docs/superpowers/plans/2026-06-09-appkit-search-design-output.json'))
synth=r['synth']
print('Engine plan:', synth['enginePlan'][:200])
tax=synth['taxonomy']
print('Taxonomy:', len(tax), 'patterns')
from collections import Counter
print('By priority:', dict(Counter(t['priority'] for t in tax)))
print('By category:', dict(Counter(t['category'] for t in tax)))
"
```

The high-priority taxonomy entries are also in `/tmp/corpus_high.json` (31 patterns).

### How each pattern must be authored

**14 fields** per the `Pattern` Codable struct in `Sources/AppKitSearchCore/Pattern.swift` + the integrity tests in `Tests/AppKitSearchCoreTests/CorpusIntegrityTests.swift`. The schema is:

| Field | Required | Type | Purpose |
|-------|----------|------|---------|
| `id` | yes | String | Unique kebab-case id |
| `title` | yes | String | Human-readable name (BM25 weight 3.0) |
| `summary` | yes | String | 1-2 sentence description (BM25 weight 1.0) |
| `category` | yes | String | Domain label (Liquid Glass, Auto Layout, Lists, etc.) |
| `keySymbols` | yes | [String] | EXACT AppKit API symbols used (BM25 weight 5.0 — highest) |
| `tags` | yes | [String] | Search keywords (BM25 weight 3.0) |
| `minMacOS` | yes (can be "") | String? | Minimum macOS version, e.g. "27.0", or "" for broadly available |
| `swiftCode` | yes | String | Canonical, copy-pasteable Swift 6 code |
| `imports` | yes | [String] | Swift imports needed (at minimum ["AppKit"]) |
| `pitfalls` | no | [String]? | 2-5 specific "don't do X" bullets |
| `related` | no | [String]? | Ids of related patterns |
| `replaces` | no | String? | The legacy/deprecated API this supersedes |
| `whenToUse` | yes | String | HIG-grounded guidance on when/whether to use |
| `higReference` | yes | HIGReference | `{ section: String, url: String }` — real Apple HIG page |

### TWO-AUTHORITY GROUNDING (mandatory per pattern)

**1. Apple HIG:** The author must WebFetch a real `developer.apple.com/design/human-interface-guidelines/` page. `whenToUse` must align with HIG content. `higReference.url` must be the **actual page fetched** — never fabricated.

**2. `appkit-api` symbol verification:** Every `keySymbol` must be machine-verified against the macOS 27 SDK. The `appkit-api` CLI is installed at `~/.local/bin/appkit-api` (built in Phase 1a). Commands:

```bash
# Bare type
appkit-api check NSGlassEffectView

# Member
appkit-api check 'NSGlassEffectView.contentView'

# Enum case
appkit-api enums NSGlassEffectView.Style
appkit-api check 'NSBezelStyle.glass'

# Availability
appkit-api availability NSViewCornerConfiguration

# Cross-module
appkit-api --module Foundation check 'ProcessInfo.disableSuddenTermination()'
```

The tool caches symbol-graph data in `~/Library/Caches/appkit-api/27.0/AppKit/`. First query extracts ~30s; subsequent queries are instant.

### Approach that works: inline authoring with focused subagents

The Workflow tool has been unreliable for this fan-out (3 failures: stringified args, `require('fs')`, markdown-fenced JSON). What DOES work is dispatching focused `Agent` calls per pattern — the 4 I just dispatched for Liquid Glass patterns succeeded (they returned valid JSON). The approach:

1. Dispatch ~4-7 agents in parallel, each authoring ONE pattern. Include the taxonomy entry, the full 14-field schema, the HIG mandate, and the appkit-api verification instructions.
2. Each agent returns raw JSON. Collect them.
3. Verify symbols with `appkit-api` (run the commands yourself — agents sometimes correct symbol names).
4. Assemble into `Data/patterns.json`. Run `swift test` — the integrity tests enforce unique ids, required fields, valid categories, related resolution, etc.
5. Live e2e: `swift run appkit-search search "liquid glass"`, etc.

### Corpus-integrity tests (what they enforce)

From `Tests/AppKitSearchCoreTests/CorpusIntegrityTests.swift`:
- Every `id` is unique and non-empty
- Every `title`, `summary`, `swiftCode` is non-empty
- `imports` is non-empty
- `keySymbols` is non-empty
- All `related` ids resolve to existing patterns
- `category` is non-empty
- Every pattern has a valid `higReference` with non-empty `section` and `url`
- `url` starts with `https://` (basic sanity)

### After the corpus: integration checklist

1. Replace placeholder `patterns.json` with the assembled corpus
2. `cd src/tools/appkit-search && swift test` — all tests (tokenizer + BM25 + integrity) must pass
3. `swift build` — builds clean
4. Live e2e queries on the new corpus: `search` verbs produce sensible results, `get` returns complete patterns with correct HIG refs
5. Extend `scripts/build-tools.sh` to also build/sign/install `appkit-search` (uncomment the line `# appkit-search is added by a later plan`)
6. Commit with `feat(appkit-search): integrate curated corpus`
7. Finish the branch

### Paused workflow (may have cached results)

A workflow was launched with `resumeFromRunId: wf_607c6f3f-363`. Its load agent returned the full 31-item taxonomy (cached). If you resume it, the pipeline picks up from that point. But the inline Agent approach described above is simpler and has been working.

## Branch state

```
Branch: feat/appkit-search
Based on: main (e550394)
Commits ahead: 5 (009e10a through 391126f + 5d704d7/53097a7 spec/docs)
Status: clean working tree (nothing uncommitted)
Tests: 43/43 Swift Testing pass in src/tools/appkit-search
```

## Remaining larger phases (out of scope for this handoff)

Per `docs/superpowers/specs/2026-06-09-macos-appkit-dev-skills-design.md` §11:
- **Phase 2:** `appkit-design` flagship skill (wired to both `appkit-api` and `appkit-search`)
- **Phase 3:** `appkit-private-apis` + `appkit-app-inspector` (flexscope driver) + advisory distribution line
- **Phase 4:** elevate `appkit-packaging` (TestFlight + MAS) + author `appkit-session-report` skill
- **Phase 5:** suite-wide TDD verification pass
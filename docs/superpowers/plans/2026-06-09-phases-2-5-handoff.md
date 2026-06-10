# Handoff — `mac-dev-skills` Phases 2–5

- **Date:** 2026-06-09
- **Repo:** `/Users/orion/Developer/Templates/skills/mac-dev-skills`
- **Current branch:** `main` (Phases 0, 1a, 1b all merged)
- **Authoritative spec:** `docs/superpowers/specs/2026-06-09-macos-appkit-dev-skills-design.md` — read it first; this doc operationalizes its §11 phasing.

---

## 0. Where things stand (verified state, not memory)

### Shipped and merged to `main`

| Phase | What | Verify with |
|------|------|-------------|
| 0 | Plugin scaffold: `.claude-plugin/marketplace.json` (+ `.codex-plugin`), `plugins/appkit/plugin.json`, 9 relocated skills, `appkit-dev` agent | `ls plugins/appkit/skills/` |
| 1a | `appkit-api` — SDK API/availability validator (symbol-graph backed) | `cd src/tools/appkit-api && swift test` (10 pass) |
| 1b | `appkit-search` — BM25 + 69-pattern HIG-grounded corpus | `cd src/tools/appkit-search && swift test` (44 pass) |

Both tools install to `~/.local/bin` via `scripts/build-tools.sh` (also copies into `plugins/appkit/skills/appkit-design/`, which is gitignored). `appkit-api` is the verification workhorse — it answers "does this symbol exist and what macOS version?" Use it constantly when authoring any skill that names AppKit APIs.

### The 13 skills — current status

```
appkit-setup                       ✅ SKILL.md (draft, relocated verbatim — needs polish pass)
appkit-dev-workflow                ✅ SKILL.md (draft + build-and-run.sh + templates/)
appkit-code-review                 ✅ SKILL.md (draft — needs polish pass)
appkit-ui-testing                  ✅ SKILL.md (draft — needs polish pass)
appkit-migration                   ✅ SKILL.md (draft — needs polish pass)
appkit-packaging                   ✅ ELEVATED (Phase 4) — TestFlight + MAS store pipeline + 3 ship scripts (ASC API key)
appkit-launch-continuity           ✅ SKILL.md (WWDC-26 draft — needs polish pass)
appkit-modern-input                ✅ SKILL.md (WWDC-26 draft — needs polish pass)
appkit-liquid-glass-concentricity  ✅ SKILL.md (WWDC-26 draft — has a "TBD interactive-glass API" note appkit-api can now RESOLVE)
appkit-design                      ✅ SHIPPED (Phase 2, merged main 7a3dfd4) — SKILL.md + 9 references, tool-wired, GREEN-verified
appkit-private-apis                ✅ SHIPPED (Phase 3) — SKILL.md + 4 refs; PrivateHeaderKit + declare/call + swizzling
appkit-app-inspector               ✅ SHIPPED (Phase 3) — SKILL.md + 4 refs; drives flexscope's frozen CLI contract
appkit-session-report              ✅ SHIPPED (Phase 4) — SKILL.md wraps analyze-session.py (privacy-gated, user-invoked)
```

**Important:** all 9 existing SKILL.md files were copied **verbatim** from `resources/` in Phase 0 and have **never been quality-edited**. They are drafts. Phase 5 is the polish pass; but if you touch any of them earlier, the writing-skills Iron Law applies (see §"Process rules" below).

---

## Process rules (learned the hard way this session — follow them)

1. **Skills require the writing-skills TDD loop.** A SKILL.md is not prose you just write. Per `superpowers:writing-skills`: RED (run a baseline subagent scenario *without* the skill, capture what it does wrong) → GREEN (write the skill addressing those failures) → REFACTOR (close loopholes). The **Iron Law: no skill content without a failing test first.** This applies to NEW skills *and* edits to existing ones. Invoke `superpowers:writing-skills` before authoring any SKILL.md.

2. **Ground every AppKit symbol with `appkit-api`.** Do not write an API name from memory. `appkit-api check 'NSType.member(_:)'`, `appkit-api availability NSType`, `appkit-api members NSType`, `appkit-api enums NSType.Enum`. In 1b, an adversarial review found a *hallucinated delegate method that compiled in nobody's head* and a wrong `minMacOS` — both invisible to structural tests. Symbol-verify everything that ships.

3. **Adversarial review catches what tests can't.** "Tests pass" ≠ "correct." After building, dispatch a skeptical reviewer (or run the writing-skills pressure scenarios) specifically on the newest/riskiest APIs. In 1b this found real bugs in 5 of 5 reviewed patterns. Budget for a review+fix loop in every phase.

4. **Workflow tool gotchas (cost real time in 1b):**
   - `args` passed to `Workflow` can arrive **as a JSON string**, not parsed — coerce: `const X = Array.isArray(args) ? args : JSON.parse(args)`.
   - Workflow scripts run in a **browser-like JS env**: no `require`, no `fs`, no `Date.now()`/`Math.random()`. To load a file, use a stage-0 `agent()` that `cat`s it, then **strip markdown fences** before `JSON.parse` (agents wrap output in ```json```).
   - Subagent fan-outs can hit the **weekly token limit** mid-run. Prefer smaller batches (5–7 items) with checkpoints over one 200-agent blast. Inline `Agent` calls with verification proved more controllable than a single huge `pipeline()`.
   - These are only relevant if you choose workflow orchestration; straightforward phases can be done inline.

5. **Branch + finish discipline.** One feature branch per phase (`feat/appkit-design`, etc.), `--no-ff` merge to `main` after tests pass on the merged result, delete branch. Use `superpowers:writing-plans` to produce a per-phase plan, then `superpowers:subagent-driven-development` or inline execution, then `superpowers:finishing-a-development-branch`.

6. **Commit with `--no-gpg-sign`** (the environment isn't set up for signing).

---

## Phase 2 — `appkit-design` (the flagship) ✅ SHIPPED

> **Done (merged to `main`, `7a3dfd4`).** `SKILL.md` + 9 `references/`, wired to `appkit-search` + `appkit-api`, authored under the full writing-skills loop (RED → GREEN → adversarial symbol-audit → GREEN-verify, 0 evasions). The audit also fixed the `build-tools.sh` resource-bundle install bug and 2 latent 1b corpus compile bugs (read-only `cornerConfiguration`, dead `/tables` HIG urls); `appkit-dev` agent un-hedged. Reusable audit harness at `scripts/wf-appkit-design-audit.js`. **Phase 5 carry:** corpus integrity tests don't compile `swiftCode` — do a suite-wide compile/symbol audit of all 69 patterns. The plan below is retained for reference.

**Goal:** the suite's marquee skill — given a UI requirement, pick the canonical AppKit control/layout, grounded in the HIG, with correct modern code. This is `win-dev-skills`' `winui-design` analog and the single highest-visibility skill.

**Why it's the flagship:** it's the one skill that ties the two native tools together — `appkit-search` to find the canonical pattern, `appkit-api` to verify symbols/availability. Both binaries are already staged in `plugins/appkit/skills/appkit-design/`.

**What to build:**
- `plugins/appkit/skills/appkit-design/SKILL.md` — lean, following the `xcode-27-skills` house style (lean SKILL.md + `references/` task files). The closest structural template is the sibling `xcode-27-skills/uikit-app-modernization` (read it for the pattern).
- `references/` deep-dive files (mirror `winui-design`'s 8 references, adapted to AppKit): app-type→anchor-control mapping, control selection, layout & spacing (HIG metrics), semantic color, typography, Liquid Glass adoption, window sizing, accessibility baseline, design anti-patterns.
- The SKILL.md must instruct the agent to **use the two tools**: query `appkit-search` for canonical patterns, verify any symbol with `appkit-api` before writing it.

**Grounding:** HIG-first (like the 1b corpus). Each control-choice recommendation cites the relevant macOS HIG page (WebFetch it). The 69-pattern corpus already encodes much of this — `appkit-design` should point at `appkit-search` rather than duplicate it.

**TDD:** RED — give a subagent a UI task ("build a settings window with a sidebar") *without* the skill, see if it reaches for deprecated/wrong controls (cell-based NSTableView, bare NSSplitView, hardcoded colors). GREEN — write the skill so it picks view-based tables, `NSSplitViewController`, semantic colors, queries the tools. REFACTOR — close the rationalizations.

**Done when:** a subagent given a design task *with* the skill produces HIG-correct, symbol-verified, modern AppKit; SKILL.md frontmatter valid; references complete; the agent's default-load reference to `appkit-design` (currently hedged in `appkit-dev.agent.md`) can be un-hedged.

---

## Phase 3 — `appkit-private-apis` + `appkit-app-inspector` (advanced / dual-use) ✅ SHIPPED

> **Done (merged to `main`).** Both skills authored under the full writing-skills loop (RED → GREEN → adversarial audit → GREEN-verify, 0 evasions). Ground truth verified first: PrivateHeaderKit's real commands (`privateheaderkit-dump --platform macos`, static, **no SIP**) and flexscope's frozen CLI contract (13 verbs, 6-check doctor gate, exit-code channel). The §7 advisory is triangulated across `appkit-private-apis` ↔ `appkit-app-inspector` ↔ `appkit-packaging`. Audit fixed 4 flexscope spec-accuracy bugs in `appkit-app-inspector` (material is a node field; fonts/constraints single-object; arm64e/AMFI exit 6; truncated on depth-cut). **Carries:** `notarize.sh` (Phase 4), `appkit-setup` flexscope/PHK hooks (Phase 5). The plan below is retained for reference.

Two NEW skills + the load-bearing **advisory stance** (spec §7). Both are Developer-ID/research-oriented; neither is auto-rejected by the App Store but both *may* be — **inform, never gate.**

### `appkit-private-apis`
- Covers: install PrivateHeaderKit (`swift run -c release privateheaderkit-install`) → dump headers (`privateheaderkit-dump` / `headerdump`) → grep/browse → declare the interface (ObjC category / bridging header / `@objc` protocol / `dlsym` for C) → call it → **swizzle** (`method_exchangeImplementations`, capture & call original, restoration, thread-safety, idempotent install, when appropriate vs. fragile).
- PrivateHeaderKit ships **zero** usage/safety guidance — all of that is original to this skill.
- PrivateHeaderKit repo: `https://github.com/lynnswap/PrivateHeaderKit` (not vendored).

### `appkit-app-inspector`
- Drives **flexscope** (the user's separate greenfield repo at `/Users/orion/Developer/Projects/flexscope` — spec-complete, may not be built yet). Target its **frozen CLI contract**: `doctor/windows/tree/find/node/font/layer/constraints/ax-diff`, JSON-Lines output, documented exit codes.
- Workflow: **`doctor` gate first** (must be all-green; report remediation verbatim on failure) → **filter→drill** loop (`windows` / `find --count-only` → `find --where --fields --limit` → deep-read one survivor with `node`/`font`/`layer`/`constraints`) → translate runtime facts (real `NSView` class, font, constraints, `CALayer.backgroundFilters`) into the developer's own AppKit code.
- **Dev-box reality stated plainly:** requires SIP/AMFI/library-validation disabled; the tool is never shipped; only *knowledge* crosses into the product.
- `appkit-setup` should build flexscope **only if present** at its path; the skill explains how to obtain/build it otherwise.

### The advisory cross-references (do this in Phase 3 or 4, but keep it consistent)
- `appkit-packaging` carries a **distribution advisory** cross-referencing both skills.
- Each of `appkit-private-apis` and `appkit-app-inspector` carries a reciprocal one-line advisory pointing back to packaging.
- Tone: "here's the trade-off and your options (Developer ID is the escape hatch)," not "you may not." Spec §7 is the canonical wording — match it.

**TDD:** these are technique skills — test that a subagent *with* the skill correctly dumps+calls a private API (or drives the flexscope loop) and *surfaces the review caveat unprompted*; *without* it, the baseline either refuses or omits the caveat.

---

## Phase 4 — elevate `appkit-packaging` + author `appkit-session-report` ✅ SHIPPED

> **Done (merged to `main`).** Packaging tooling verified against the **Xcode 27 toolchain** (man pages / `--help`): the load-bearing fix was `method app-store`→`app-store-connect` (deprecated). Added the store-pipeline cert split, App Sandbox, the `altool` `.p8` CI trap, and 3 shellcheck-clean ship scripts (ASC API key, no passwords). `appkit-session-report` wraps `analyze-session.py` (verified running) with mandatory `--output` + unprompted privacy warning + summary-over-raw + a bug-filing guard. Both via the writing-skills loop (GREEN-verify 4/4, 0 evasions; loophole closed + re-verified). Phase-5 carries logged in the top-level `HANDOFF.md`. The plan below is retained for reference.

### Elevate `appkit-packaging` (it's a draft today)
Concentrate the TestFlight + Mac App Store story here (spec §9):
- **Developer ID:** `codesign` → `notarytool submit --wait` → `stapler` → signed `.dmg`/`.pkg` (`create-dmg`).
- **TestFlight + MAS:** App Store Connect **API-key** auth, `ExportOptions.plist` templates, App Sandbox + entitlements, archive → export → upload (`xcrun altool`/`notarytool`/Transporter), internal/external testers, review notes.
- **Ship scripts** under `plugins/appkit/skills/appkit-packaging/scripts/`: `notarize.sh`, a TestFlight upload script, a MAS export/submit script — all ASC API key, **no interactive passwords**.
- Existing `references/ci-and-app-store.md` is a starting point — verify/expand it.
- Add the **private-API distribution advisory** (the packaging end of the §7 cross-reference).

### Author `appkit-session-report`
- `plugins/appkit/skills/appkit-session-report/` already holds `analyze-session.py` (the payload). Write its SKILL.md.
- Wraps the analyzer: privacy notice (transcripts may contain secrets/paths), how to invoke, the report sections it produces.
- `disable-model-invocation: true` (user-invoked only, like `winui-session-report`).

**TDD:** reference/technique skills — test retrieval + correct invocation.

---

## Phase 5 — suite-wide polish ✅ SHIPPED

> **Done (merged to `main`).** Headline: a `swiftc -typecheck` **corpus compile-audit** caught 13 latent won't-compile bugs across the 69 `appkit-search` patterns (the integrity tests never compiled `swiftCode`) — all fixed, 44 tests still pass. All 8 verbatim-draft skills audited (typecheck + symbol-verify) and fixed; `effectIsInteractive` un-hedged; `appkit-setup` now builds the native tools + handles flexscope/PHK; README/CHANGELOG updated. Accepted limitation: the `analyze-session.py` build heuristic (guarded in the session-report skill). **Project complete — all phases merged.** The plan below is retained for reference.

- **Polish the 9 verbatim-draft skills** under the writing-skills loop. Each was relocated unedited; run an application-scenario subagent per skill, fix gaps. Priority targets:
  - `appkit-liquid-glass-concentricity`: it has an explicit **"interactive-glass API name TBD — verify against docs"** hedge. `appkit-api` now resolves it: `NSGlassEffectView.effectIsInteractive` (macOS 27.0). Replace the hedge with the verified symbol. (This was the original motivating example for building `appkit-api`.)
  - The other two WWDC-26 skills (`appkit-launch-continuity`, `appkit-modern-input`) and the inner-loop skills.
- **Un-hedge the agent:** `appkit-dev.agent.md` currently says "load appkit-design *when present*." Once Phase 2 lands, make it a normal default load.
- **Repo docs:** README accuracy (skill count is now real), CONTRIBUTING, CHANGELOG. Microsoft-style provenance CI remains **out of scope** (spec §13).
- **Consistency pass:** house-style headings, `references/` conventions, frontmatter, cross-references between skills.
- Consider an `appkit-setup` update so it builds flexscope-if-present and checks for PrivateHeaderKit.

---

## Out of scope (spec §13 — don't build these)

- SwiftSyntax lint/analyzer (planned, deferred).
- Microsoft-style release CI (version-sync, binary provenance, branch/promotion model).
- Live/online sample scraping for `appkit-search`.
- Vendoring flexscope or PrivateHeaderKit source.
- Shipping prebuilt/notarized tool binaries.

---

## Quick-start for the next session

```bash
cd /Users/orion/Developer/Templates/skills/mac-dev-skills
git status && git log --oneline -5          # confirm on main, Phase 1b merged
cd src/tools/appkit-search && swift test     # 44 pass
cd ../appkit-api && swift test               # 10 pass
appkit-api check NSGlassEffectView.effectIsInteractive   # tool works (→ 27.0)
appkit-search search "sidebar"               # corpus works
```

Then for Phase 2: invoke `superpowers:writing-plans` to plan `appkit-design`, or `superpowers:writing-skills` to go straight into the TDD loop. Read `docs/superpowers/specs/2026-06-09-macos-appkit-dev-skills-design.md` §4 (roster) + the sibling `../xcode-27-skills/uikit-app-modernization/` for the house-style template.

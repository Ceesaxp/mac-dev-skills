# `appkit-search` Tool — Implementation Plan (Phase 1b)

> **For agentic workers:** executed via multi-agent **Workflows** (ultracode). Two independent tracks — engine (TDD) and corpus (fan-out authoring) — then integrate + review. Full design data: `2026-06-09-appkit-search-design-output.json` (this dir).

**Goal:** Build `appkit-search` — a Swift BM25 search CLI over a **curated, embedded corpus of canonical AppKit patterns** (macOS 26/27). The macOS analog of Microsoft's `winui-search`: an agent queries it for "how do I build X in AppKit" and gets ranked patterns + full, correct, HIG-grounded code.

**Architecture:** Two SwiftPM targets mirroring `appkit-api` — a testable `AppKitSearchCore` library (BM25 port, tokenizer, stopwords, synonyms, Codable corpus models, loader, ranking, output DTOs; corpus embedded via SwiftPM resources) + a thin `appkit-search` CLI (`search`/`get`/`list`, ArgumentParser). **No** live fetch / cache / background updater (single embedded corpus). Tests use **Swift Testing**.

**Tech stack:** Swift 6, SwiftPM, swift-argument-parser, Swift Testing. Engine ported 1:1 from `winui-search` (BM25.cs etc., reverse-engineered in the design workflow).

---

## 1. Engine (track A — TDD)

Port `winui-search`'s proven engine to Swift. Full spec in the design-output JSON (`synth.enginePlan` + `engineSpec`). Key points:

- **BM25** (port `BM25.cs` 1:1): `k1=1.2`, `b=0.75`. `Doc { tf: [String:Double]; length: Double }`, `Corpus { df: [String:Int]; n: Int; avgDl: Double }`. **Weighted-field tf** — `buildDoc(fields:[(text,weight)])` accumulates `tf[word] += weight` and `length += weight` per token (NOT integer counts — reproduce verbatim). `idf = log((n - df + 0.5)/(df + 0.5) + 1)` (natural log, Lucene `+1` non-negativity guard). `tfNorm = (tf*(k1+1))/(tf + k1*(1 - b + b*(doc.length/avgDl)))`. Corpus rebuilt per query (flat, ~69 docs — no persistent index).
- **Per-pattern doc field weights:** `keySymbols 5.0` (highest), `tags 3.0`, `title 3.0`, camelCase-split title `2.5`, `summary 1.0`, `id 1.0`.
- **Post-BM25 boosts** (multiplicative, vs `compactQuery` = lowercased `[^a-z0-9]`-stripped): whole-word title ×2.0; longest-compact-compound ×4.0 / non-longest ×1.3; ≥6-char substring-in-compact-title ×2.5; generic-title demotion ×0.85. Plus a platform-keyword reverse map (glass/concentric/sidebar/drag/picker → pattern id) ×1.6. **Relevance floor:** runners-up need ≥70% of top score (top-1 always kept). **Coverage gate:** built from RAW tokens (`tokenize(query).distinct`, NOT preprocessed/expanded); if ≥3 raw tokens, a pattern must hit ≥ceil(N/2) unless name-boosted.
- **Tokenizer** (port `BM25.Tokenize` order): (1) invariant lowercase (use `en_US_POSIX` folding / ASCII handling — avoid Turkish-i); (2) regex `[^a-z0-9\s\-] → ' '` (hyphens preserved); (3) split on ASCII space; (4) keep if `count > 1` and not a stopword. No stemming inside tokenize. Helpers: `compactQuery`, `splitCamelCase` (`NSGlassEffectView → NS Glass Effect View`).
- **Stopwords** (`StopWords.common`, ~180 words ported verbatim) as the hot-path query+index stoplist; `tagOnly` for tag cleaning.
- **Synonyms** (3 mechanisms, 2 stages — port mechanism, **retranslate data to AppKit**): Stage 1 `preprocess(query)` appends — Phrases (`split view → splitviewcontroller`, `glass effect → nsglasseffectview`, `open panel → nsopenpanel`, …), stemming (-s/-ed/-ing variants), StemExceptions. Stage 2 `expand(tokens)` appends synonyms — Map (`modal → [nsalert,sheet,nspopover]`, `table/datagrid → [nstableview,nsoutlineview]`, `sidebar → [nssplitviewcontroller]`, `tray/menulet → [nsstatusitem]`, `blur/vibrancy → [nsvisualeffectview]`, `glass → [nsglasseffectview]`, …) with the **compound-suffix guard**. Pipeline: `raw → preprocess → tokenize → expand → score`; coverage gate uses raw tokenize only.
- **CLI verbs** (JSON via `emitJSON` `[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]`): `search <query…> [--max N=5] [--category C]` → `{query, results:[{id,title,category,summary,minMacOS?,score}]}` (code NOT included; hint to call `get`); batch when multiple quoted args with cross-query dedup. `get <id…>` (≤3) → full pattern(s) `{id,title,summary,minMacOS,imports,keySymbols,swiftCode,pitfalls,related,replaces,whenToUse,higReference}`; exit 1 if any id missing. `list [--category C]` → grouped by category. Optional `debug <query>` (preprocessed/tokens/expanded/top-N-no-floor) as a tuning aid.
- **Swift Testing layers:** (1) tokenization (lowercasing, char-class strip with hyphen preservation, split, stopword filter, compactQuery, splitCamelCase, the preprocess→tokenize→expand order + compound-suffix guard + AppKit synonym retranslation); (2) BM25 scoring/ranking (weighted-tf accumulation, df dedup + avgDl, exact idf/tfNorm against hand-computed values to lock k1/b/+1, name boosts, 70% floor, raw-token coverage gate, end-to-end ranking assertions); (3) corpus integrity (decode embedded `Data/*.json`, unique kebab ids, required fields non-empty, `related[]` ids resolve, categories within known set, `minMacOS` parses).
- **Corpus embedding:** `Codable struct Pattern` mirrors the schema; corpus JSON in `Sources/AppKitSearchCore/Data/patterns.json`, loaded once via `Bundle.module`. The engine track builds against a **small placeholder `patterns.json`** (3–4 real patterns) so the loader + integrity tests pass; the full corpus from track B replaces it at integration.

## 2. Corpus (track B — fan-out authoring, the real product)

Author **69 patterns** (taxonomy in the design-output JSON). Each authored by the pipeline: **author → verify → judge**.

**Corpus schema (14 fields):** the 12 synthesized fields — `id, title, summary, category, keySymbols, tags, minMacOS?, swiftCode, imports, pitfalls, related, replaces?` — **plus the two mandated HIG fields:**
- `whenToUse` (string, required) — HIG-grounded guidance on *when/whether* to use this pattern + the canonical control choice.
- `higReference` (object, required) — `{ section: string, url: string }` citing the macOS HIG page consulted.

**Two-authority grounding (mandatory per pattern):**
1. **Apple HIG → behavior/guidance.** The author MUST WebFetch the relevant `developer.apple.com/design/human-interface-guidelines/…` page, ground `whenToUse` + the control choice in it, and cite it in `higReference`. The judge **rejects** any pattern whose guidance contradicts or ignores the HIG.
2. **`appkit-api` → symbols/availability.** The verify stage runs `appkit-api check <symbol>` / `availability <symbol>` for every `keySymbol` and confirms `minMacOS`. Symbols that don't resolve are corrected or dropped; `minMacOS` is set from the tool's answer.

**Pipeline stages (per pattern, no repo writes — agents return structured data):**
1. **Author** — given `{id,title,category,keySymbols,minMacOS,priority}`: WebFetch the HIG page; write canonical Swift 6 code (`swiftCode`), `imports`, `summary`, `tags`, `pitfalls`, `whenToUse`, `higReference`, `replaces`, candidate `related`. Favor modern non-deprecated APIs.
2. **Verify** — run `appkit-api` on every `keySymbol` + `minMacOS`; return corrected symbols/availability + a verification report.
3. **Judge** — confirm: HIG citation is real + guidance aligns; code compiles-plausibly and matches keySymbols; symbols verified; no deprecated API where a modern one exists. Verdict `accept | revise | reject` + reasons. (Revise → re-author once.)

Approved patterns are assembled into `Sources/AppKitSearchCore/Data/patterns.json` (controller writes the consolidated file; `related[]` cross-refs reconciled).

## 3. Integration + review (track C)

1. Replace the placeholder corpus with the assembled 69-pattern `patterns.json`.
2. Run the corpus-integrity tests + full `swift test`.
3. Live e2e: `appkit-search search "liquid glass"`, `search "drag and drop table"`, `get concentric-corner-configuration`, `list` — confirm sensible ranking + complete `get` output incl. HIG reference.
4. Extend `scripts/build-tools.sh` to build/sign/install `appkit-search` too (uncomment the search line; install into `appkit-design` skill dir).
5. Adversarial final review (BM25 math, pipeline order, Swift 6, corpus correctness, HIG grounding) → fix → finish branch.

## 4. Sequencing

Engine (track A) and corpus (track B) run **concurrently** (independent; corpus authors return data, don't touch the package). Integration (track C) waits for both. Then finish the branch.

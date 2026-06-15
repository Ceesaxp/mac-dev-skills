<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# uitool selectors, predicates, and node ids

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.

## Source: `Specs/models/domain.uitool.selector.md`

---
id: domain.uitool.selector
kind: domain
depends-on: [domain.uitool.node]
---

# Selector & Predicate Grammar

The two server-side query languages for `find` / `--where`. Both are evaluated **inside the injected process** against the live tree, so only matching nodes cross the wire — for a 10k-node window the agent cannot afford to pull the tree and grep locally. Derived from HANDOFF §8.3.

## CSS-like structural selectors

| Form | Meaning |
| --- | --- |
| `NSButton` | by class — **honors the runtime class hierarchy** (`NSControl` matches `NSButton`) |
| `NSScrollView NSTableView` | descendant |
| `NSStackView > NSTextField` | direct child |
| `NSView[title*="Inbox"]` | attribute substring |
| `NSView[frame-w>200]` | geometry predicate |
| `*[hidden=false]` | wildcard + attribute |

Class matching honoring the **runtime hierarchy** (`classHierarchyOfObject:` / `subclassesOfClassWithName:`) is the capability AX fundamentally cannot offer (AX has roles, not classes) — the headline reason the tool exists.

## Predicate expression language (`--where`)

A tiny **total** language — comparisons, `and` / `or` / `not`, `matches`, `intersects`, `~` (class-of). **No recursion, bounded evaluation time**, so a query can't hang the target.

```
class ~ 'NSTextField' and text *= 'Inbox'
frame-w > 200 and hidden = false
```

## Field projection (`--fields`)

A projection **path list** (`class,frame,font.family`), NOT full jq. Full jq is a footgun (non-deterministic ordering, unbounded output) and is deliberately excluded.

## The matching engine

`*=` (substring) and `matches` (regex) — plus `[attr*="…"]` in the structural form — are backed by Swift's **native `Regex`** (Swift 5.7+; the package's macOS 14 floor guarantees it), **not** `NSRegularExpression`. The contract:

- **Case-insensitive, unanchored substring semantics.** A pattern matches if it occurs *anywhere* in the candidate string — the engine uses `firstMatch(in:)`, not a whole-string anchor, and folds case. `text *= 'inbox'` matches `"Inbox Unread"`; `text matches 'in.ox'` matches the same. To anchor, write the anchors into the pattern (`^Inbox$`).
- **An invalid pattern throws at construction.** A `--where` clause or `[attr*=…]` selector whose regex doesn't compile is a *usage* error, surfaced as the `BAD_SELECTOR` failure (code `BAD_SELECTOR`, **exit 2**) — see [[error.uitool.find-bad-selector]]. The pattern is rejected before any node is touched, so a malformed selector never partially-evaluates against the tree.
- **`*=` is the substring sugar over `matches`.** `text *= 'foo'` is `text matches` a literal-escaped `foo`, so `*=` can never itself be a "bad selector" on metacharacters — only an explicit `matches` regex can throw.

`--class` GLOB matching (the `classes` / structural class-token vocabulary) is **separate** and unchanged: it stays shell-style glob (`NS*View`, `_NSToolbar*`), not regex. Glob and regex do not bleed into each other — `[attr*=…]` / `matches` are regex; `--class` is glob.

## Sizing a query before paying for it

`find` (and `classes`) carry a **`--limit` defaulting to 50** matched nodes and a **`--count-only`** flag. The canonical move is `find --count-only` to learn how many nodes a selector matches (cheap — a count, not a tree), then `find --where … --fields … --limit N` to pull the survivors. `--limit N` overrides the default; `--count-only` returns only the count (`_meta.totalMatched`) and no node bodies. The default cap exists so a too-broad selector against a 10k-node window can never blow the agent's context on the first call — broaden deliberately, raise `--limit` deliberately.

## Invariants

- Evaluation is total and bounded — no construct can loop or recurse unboundedly.
- Class predicates resolve through the runtime class hierarchy, not string equality.
- Filtering and projection happen **server-side**; the CLI never pulls the tree to filter locally.
- Regex matching is case-insensitive, unanchored substring (`Regex.firstMatch`), never `NSRegularExpression`; an uncompilable pattern is rejected at construction as `BAD_SELECTOR` (exit 2), never silently treated as a literal or a zero-match.
- A selector that matches 0 nodes yields a valid empty result — **exit 0** with `_meta.totalMatched: 0` per [[domain.uitool.ipc]] — distinct from a usage error (exit 2). A 0-match means broaden the selector, not re-issue.
- A `--fields` path that names no field on [[domain.uitool.node]] is a usage error (code `UNKNOWN_FIELD`, exit 2); a `--where` predicate the grammar can't parse is a usage error (code `BAD_PREDICATE`, exit 2). The two are **distinct codes**, never collapsed into one "bad projection".

## Relationships

- [[domain.uitool.node]] — the fields selectors match against.
- Consumed by `find`, and the `--where` / `--fields` flags on `tree` / `node`.

## Notes

- The canonical loop: **locate few → project narrow → read deep on survivors** — `find --count-only` to size a selector, then `find --where … --fields … --limit N`, then `node` / `font` / `constraints` on the 1–3 survivors. A few KB per step, never a 200k-token tree dump.
- **v1 attribute vocabulary** (addressable in `[attr…]` selectors and `--where`), all sourced from [[domain.uitool.node]]:
    - `class` (string; `~` resolves the runtime hierarchy), `identifier` (string), `axRole` (string)
    - `text` (string — the view's string value where it has one: `NSTextField.stringValue`, `NSButton.title`, `NSText` string), `title` (string — window / control title)
    - `frame-x`, `frame-y`, `frame-w`, `frame-h` (number, from `frame`)
    - `hidden` (bool), `alpha` (number), `isFlipped` (bool), `swiftUIBoundary` (bool), `childCount` (int), `material` (string, where applicable)

    Operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `*=` (substring), `~` (class-of / hierarchy), `matches` (regex). The set is intentionally small and additive within a major — new attributes are added deliberately, not ad-hoc.


## Source: `Specs/models/domain.uitool.node-id.md`

---
id: domain.uitool.node-id
kind: domain
depends-on: []
---

# Domain: Node ID

A stable, collision-safe handle for a live object across many agent turns. Derived
from HANDOFF §7.3 — the determinism keystone.

## Shape

```
nodeId = "<sessionEpoch>:<structuralPath>#<ptrTag>"
example: 7:w0/cv/sv2/tv0/tr3/c1#a3f9
```

| Segment | Type | Notes |
| --- | --- | --- |
| `sessionEpoch` | int | bumped on `attach`; detects stale handles across re-attach |
| `structuralPath` | string | root-relative child indices (`w0` = window 0, `cv` = contentView, `tv0` = 0th `NSTableView` descendant…). Human/agent-legible — legibility *is* a context-budget feature (the id doubles as a breadcrumb; a sibling `tr3`→`tr4` is often guessable without a round-trip) |
| `ptrTag` | hex | short hash of the object pointer, **for collision detection only, never re-lookup** |

## Identity

- The full `nodeId` identifies an object within a session.
- The pointer is a **field** (`--fields pointer`), never a sort key — pointers are
  non-deterministic.

## Invariants

- **Validate before every deref.** On lookup: (1) re-walk the structural path; (2)
  `FLEXPointerIsValidObjcObject(ptr)`; (3) `object_getClass(ptr) == recordedClass`;
  optionally (4) frame still matches.
- On any mismatch return **`STALE_NODE`** (exit 5) — never dereference a recycled
  pointer. No silent fallback (the only safe behavior, and the repo's code-quality
  rule).
- The registry holds objects **unretained** (weak `NSMapTable`) so it never
  extends host object lifetimes or masks leaks.
- The registry is invalidated on `reset`, on `detach`, and when the key window
  changes.

## Lifecycle

- `attach` → epoch bumped, registry empty.
- A node id is minted lazily when an object is first walked.
- Under live mutation (a table inserting a row) sibling indices shift, so held ids
  for later siblings change — for v1, path-id + a `class` echo for staleness
  detection is enough.

## Relationships

- [[domain.uitool.node]] — carries the `node`/`parent` ids.
- [[domain.uitool.ipc]] — `STALE_NODE` is one of its error codes.

## Notes

- **v1 anchors stability on the structural path + a `class` echo only.** Anchoring
  on `accessibilityIdentifier` (where present) is deferred until churn in the
  target apps' inspection sessions demands it (HANDOFF §13); revisit if held ids
  prove too fragile under live mutation.
- The `STALE_NODE` wire code is **canonical**, not a placeholder — it is the
  confirmed string the [[domain.uitool.ipc]] error envelope emits on a failed
  deref (exit 5).


## Source: `Specs/models/domain.uitool.node.md`

---
id: domain.uitool.node
kind: domain
depends-on: [domain.uitool.node-id, domain.runtime.walker]
---

# Domain: View Node

The canonical agent-facing record for one element of a target app's runtime view
tree — what every `uitool` query verb returns. It is the **projection** of a
`RuntimeKit` `ViewSnapshot` / `WindowSnapshot` (see [[domain.runtime.walker]])
into the JSON record the agent reads: the walker reads the live AppKit object on
the main thread and emits a plain `Sendable` snapshot; `UIToolCore` rounds, key-
orders, and stringifies node ids over that snapshot to produce a `node`. Derived
from HANDOFF §8.4; this is the contract `uitool schema` prints.

> **The walker is the source, the node is the shape.** A `ViewSnapshot` carries
> *raw* values (a `CGFloat` is a `Double` with no rounding, the node id is not
> yet stringified — see [[domain.runtime.walker]]'s purity note). The node is that
> snapshot after `UIToolCore` applies deterministic rounding, stable key order,
> and node-id stringification. No field on the node exists that the walker does
> not supply; this model defines *which* of the walker's fields are projected by
> default and which are pulled on demand.

> **Default projection** = the fields marked ✓ below. The rest are pull-on-demand
> via `--include` or a dedicated verb, so the default node stays small enough to
> stream a 10k-node tree under a context budget.

## Shape

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `node` | string | ✓ | stable id — see [[domain.uitool.node-id]] |
| `parent` | string \| null | ✓ | parent node id; null at a window root |
| `class` | string | ✓ | **real** runtime class — the walker's `runtimeClass` (via `object_getClass`): the private subclass (the whole point vs AX) |
| `superclasses` | string[] | — | the walker's `superclasses` chain up to `NSView`/`NSObject` (`--include`) |
| `frame` | {x,y,w,h} | ✓ | raw `NSView` coords (bottom-left origin), 1 dp |
| `frameTopLeft` | {x,y,w,h} | ✓ | normalized top-left, window-relative |
| `isFlipped` | bool | ✓ | the view's `isFlipped` (the #1 silent-correctness trap) |
| `hidden` | bool | ✓ | `isHidden` |
| `alpha` | number | ✓ | `alphaValue`, 1 dp |
| `identifier` | string \| null | ✓ | `NSUserInterfaceItemIdentifier` if set |
| `text` | string \| null | ✓ | the view's text content where it carries one (label/field/title), null otherwise |
| `axRole` | string \| null | ✓ | cross-reference to the AX dump (`ax-diff`) |
| `font` | Font \| null | ✓ | the walker's composed `FontSnapshot`; null where there's no font carrier |
| `material` | string \| null | ✓ | `NSVisualEffectView.material` where applicable |
| `blendingMode` | string \| null | — | `NSVisualEffectView.blendingMode` (`--include`) |
| `layer` | Layer \| null | — | the walker's `LayerSnapshot` where `wantsLayer`; null otherwise (`--include layer` / `layer` verb) |
| `constraintsCount` | int | ✓ | count only in the node; the full `ConstraintNode` list via `--include constraints` or the `constraints` verb |
| `swiftUIBoundary` | bool | ✓ | true at an `NSHostingView` (the walker sets it when any class in the runtime superclass chain contains `NSHostingView`); below it, class names are SwiftUI internals |
| `childCount` | int | ✓ | number of subviews |
| `children` | ViewNode[] | ✓* | present only within `--depth`; past it, omitted with `truncated: true` + `childCount` |

### Default field set, stated plainly

The default projection — emitted by `windows`, `tree`, `find`, and `node` with
no `--include` — is exactly: **`class`** (via the walker's `runtimeClass`),
**`frame`**, **`frameTopLeft`**, **`isFlipped`**, **`hidden`**, **`alpha`**,
**`identifier`**, **`text`**, **`axRole`**, **`font`** (the composed
`FontSnapshot`, or null), **`material`** (or null), **`swiftUIBoundary`**,
**`childCount`**, and **`constraintsCount`** — alongside the identity fields
**`node`**/**`parent`** and, within `--depth`, **`children`**. Everything else is
`--include`-only:

- **`superclasses`** — the full runtime class chain (`--include superclasses`).
- **`blendingMode`** — `NSVisualEffectView.blendingMode` (`--include`).
- **`layer`** — the full recursive `LayerSnapshot` (`--include layer`, or the
  `layer` verb). The node's default already commits to `material` because a
  visual-effect material is a single cheap scalar a layout reviewer reads
  constantly; the layer subtree is the expensive structure and stays opt-in.
- **the full constraint list** — the node carries only `constraintsCount` by
  default; the walker's `ConstraintNode` (every touching `NSLayoutConstraint`
  plus the intrinsic-sizing facts) inlines only under `--include constraints` or
  the `constraints` verb.

### Font (sub-shape)

The walker's `FontSnapshot`, carried through verbatim (see
[[domain.runtime.walker]]): `family` (string), `size` (number, 1 dp),
`weightTrait` (raw CoreText `NSFontWeightTrait`, −1.0…1.0), `weightName` (nearest
named weight), `postScriptName` (string, e.g. `.SFNS-Regular`), `traits`
(string[] symbolic traits).

> **Never** emit a lossy `NSFontManager` weight (1–14) ↔ `NSFontWeightTrait`
> conversion — they're nonlinear and non-interchangeable. Emit both the raw trait
> and the nearest name (HANDOFF §5.2). The walker already enforces this; the node
> projects both fields unchanged.

### Layer (sub-shape)

The walker's `LayerSnapshot`: `present`, `cornerRadius`, `masksToBounds`,
`backgroundColor`, `borderWidth`, `borderColor`, `shadowOpacity`, `shadowRadius`,
`shadowOffset` ({w,h}), `shadowColor`, `sublayerTransform`, `mask`,
`backgroundFilters`, and `sublayers` (the recursive child layers, bounded at
depth 64 by the walker). The full recursive serialization follows the walker's
`LayerSnapshot` shape ([[domain.runtime.walker]]); a dedicated `layer` verb is
deferred to the expensive-verb pass. The CALayer subtree is a **parallel**
structure cross-linked by node id, never merged into the view tree
(`layer.sublayers ≠ view.subviews`).

## Identity

- `node` (the stable id) identifies an instance within a session — see
  [[domain.uitool.node-id]].
- `class` + `frame` are the human/agent-legible secondary identifiers.

## Invariants

- `class` is the **observed** runtime class, never canonical — it is the walker's
  `runtimeClass` (the runtime ISA via `object_getClass`), and it can shift between
  OS builds; output records the OS build (see [[domain.uitool.injection]]).
- `frame`, `frameTopLeft`, and `isFlipped` are always emitted together; a
  consumer must never infer top-left origin from `frame` alone. The walker
  computes `frameTopLeft` by reconciling AppKit's bottom-left origin to a
  window-relative top-left rect; with no window it falls back to the raw frame.
- `layer` is independent of the view: a null `layer` is normal (`NSView.layer` is
  nil unless `wantsLayer`, and the walker emits `layer == nil` for an unbacked
  view, not a `present:false` stand-in). Never assume view↔layer 1:1.
- Below a `swiftUIBoundary: true` node, fonts/frames/fills are reported
  confidently but class names are **not** asserted to be hand-written AppKit
  controls.
- Default-projection output is deterministic: stable key order, z-order children,
  fixed precision, no addresses/timestamps. The walker carries raw values; the
  determinism (`stableRounded`, key order) is `UIToolCore`'s projection step over
  the snapshot, not the walker's.

## Relationships

- [[domain.runtime.walker]] — the `RuntimeKit` layer this node projects: a node
  *is* a `ViewSnapshot` after `UIToolCore` rounding, key-ordering, and node-id
  stringification.
- [[domain.uitool.node-id]] — the `node`/`parent` id scheme.
- [[domain.uitool.ipc]] — how a node is requested and streamed.
- Consumed by the `windows`, `tree`, `node`, `find`, `font`, `layer`,
  `constraints` commands.

## Notes

- Rendered snapshots are out of scope (HANDOFF §6.3 / ARCHITECTURE → "Out of
  scope").
- `backgroundColor` (and any resolved color) is reported as **both** the resolved
  sRGB hex `#RRGGBBAA` **and** the catalog/dynamic color name where one is
  available (e.g. `controlAccentColor`), plus the appearance context it was
  resolved under (e.g. `NSAppearanceNameDarkAqua`). The hex is the unambiguous
  snapshot; the catalog name is what a native reimplementation actually uses.
  Colors are resolved via the window's `effectiveAppearance` + `usingColorSpace:`
  before components are read. This is exactly the walker's `ColorSnapshot`
  contract (see [[domain.runtime.walker]]); the node carries it unchanged.


## Source: `Features/uitool/0005-find/commands/uitool.find.md`

---
id: command.uitool.find
kind: command
depends-on: [domain.uitool.selector, domain.uitool.node-id, domain.uitool.node, domain.uitool.ipc]
status: draft
---

# `uitool find` — locate few

<!--
  The cheap "locate few" entry point of the canonical loop. Resolves a class
  selector and/or a --where predicate server-side, optionally counts, caps, and
  projects, then emits only the matched nodes. Pure-core decision logic the CLI
  wraps; testable without injection by feeding it captured match data.
-->

## Synopsis

```
uitool find <app> [--class GLOB] [--where EXPR] [--fields PATHS] [--limit N] [--count-only]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target — pid or bundle id (e.g. `com.apple.mail`) |
| `--class` | string (glob) | no | a bare **class glob** per [[domain.uitool.selector]]; class matching honors the runtime class hierarchy. `--class` accepts a class glob only — the richer structural combinators (descendant, child, attribute) live in `--where`, not here. The two flags compose: `--class` narrows by class, `--where` adds predicate constraints over the survivors. |
| `--where` | string (predicate) | no | a predicate expression per [[domain.uitool.selector]] (total, bounded; `and`/`or`/`not`, `matches`, `intersects`, `~`). A `matches`/`~` operand is a **Swift-native `Regex`** — case-insensitive, unanchored substring (`firstMatch`); an invalid pattern throws at construction and surfaces as a usage error (exit 2, see [[error.uitool.find-bad-selector]]), never a hang or a silent zero-match. |
| `--fields` | string | no | projection path list per [[domain.uitool.selector]] (`node,class,frame,font`); ignored when `--count-only`. When omitted, `find` emits the **full default node projection** from [[domain.uitool.node]] (the default field set: `node`, `class`, `frame`/`frameTopLeft`/`isFlipped`, and the other default fields that model defines) — not a `find`-specific minimal default. The HANDOFF examples pass `--fields` explicitly because narrow projection is the cheaper habit, but the default is the full node projection, so an agent that omits the flag still gets a complete, well-defined record. |
| `--limit` | int | no | cap on returned node records; does not affect the reported total matched count. **Default: 50.** Override with `--limit N` to widen or tighten the cap. Pair with `--count-only` first to size a query before paying for the records. |
| `--count-only` | flag | no | report only the total matched count; return no node records. The cheapest sizing call — "size it before you pay." |

At least one of `--class` / `--where` is required. `find <app>` with neither is a **usage error** (exit 2, see [[error.uitool.find-bad-selector]]): an unconstrained full enumeration is exactly the expensive tree-download the cost-tiering exists to discourage, so the surface refuses it rather than silently matching every node. To enumerate broadly on purpose, pass an explicit broad selector (e.g. `--class '*'`) and size it with `--count-only` first.

## Behavior

1. Resolve `<app>` to the attached session; if no session is attached, fail (exit 4 per [[domain.uitool.ipc]]).
2. Require at least one of `--class` / `--where`; neither present is a usage error (exit 2, see [[error.uitool.find-bad-selector]]).
3. Parse `--class` and/or `--where` into the selector / predicate per [[domain.uitool.selector]]; a parse failure — an unknown combinator, an unbalanced bracket, or an **invalid `Regex` pattern in a `matches`/`~` operand** — is a usage error (exit 2, see [[error.uitool.find-bad-selector]]).
4. Issue the matching op (`find`) to the injected server, which evaluates the selector / predicate **server-side** against the live tree on the target's main thread (per [[domain.uitool.ipc]]); only matching nodes cross the wire.
5. If `--count-only`: emit the total matched count in `_meta.totalMatched`; return no records.
6. Otherwise: project each matched node to `--fields` per [[domain.uitool.node]] (or the full default projection when `--fields` is omitted), cap to `--limit` (default 50), emit the records, then emit the result-summary `_meta` marker (per [[domain.uitool.ipc]]'s envelope).

## Output

Responses conform to [[domain.uitool.ipc]]'s envelope. Every payload — every JSON-Lines object, including each node-record line — carries `schemaVersion` (a semver **string**, e.g. `"1.0.0"`, per [[domain.uitool.ipc]]). Unless `--no-meta` is passed, the response also carries a top-level `sessionId` (string) and, on the streamed result, a `_meta: {returned, truncated, totalMatched}` summary; `--no-meta` strips both `sessionId` and `_meta` (never `schemaVersion`).

`sessionId` appears **once per response, on the summary line** — the single `--count-only` object, or the trailing `_meta` line of the multi-record stream — not repeated on every node-record line. A node-record line carries its `schemaVersion` and projected fields only; the session is identified once for the whole stream.

`--count-only` — a single JSON object carrying the match count in `_meta.totalMatched`, with no node records:

```jsonc
{"schemaVersion":"1.0.0","sessionId":"a1b2c3","_meta":{"returned":0,"truncated":false,"totalMatched":3}}
```

Otherwise — JSON-Lines: one matched node per line (projected to `--fields`, fields from [[domain.uitool.node]]), then a final `_meta` line carrying the per-stream `sessionId`:

```jsonc
{"schemaVersion":"1.0.0","node":"7:w0/cv/sv0/tv0/tr0/c0#b2c4","class":"NSTextField","frame":{"x":34,"y":8,"w":160,"h":16},"font":{"family":"SF Pro Text","size":13,"weightName":"regular"}}
{"schemaVersion":"1.0.0","sessionId":"a1b2c3","_meta":{"returned":1,"truncated":false,"totalMatched":1}}
```

- One node per line so the agent consumes incrementally and a truncated read still yields N valid records (per [[domain.uitool.ipc]] / HANDOFF §8.1).
- `_meta.returned` = records emitted; `_meta.truncated` = true when `totalMatched > returned` because of `--limit` (the single canonical "more exist" flag per [[domain.uitool.ipc]] — never a second `limitHit`); `_meta.totalMatched` = the full server-side match count regardless of `--limit`.
- Deterministic: stable key order, children/records in z-order (never address order), frames to 1 dp, no addresses/timestamps in the default projection. `pointer` is a pull-on-demand field, never a sort key (see [[domain.uitool.node-id]]).
- `--no-meta` strips the summary line's `sessionId` and the `_meta` summary for byte-identical diffs across sessions, but never `schemaVersion` (which is in every payload per [[domain.uitool.ipc]]).

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (≥1 match, or any `--count-only`) | 0 | payload on stdout |
| valid query, 0 matches | 0 | empty result on stdout, `_meta.totalMatched: 0` (a 0-match query is **not** an error per [[domain.uitool.ipc]]) |
| malformed selector / predicate, or neither `--class` nor `--where` given | 2 | structured error on stderr (see [[error.uitool.find-bad-selector]]) |
| not attached | 4 | structured error on stderr (see [[error.uitool.find-not-attached]]) |
| socket / main-thread timeout | 7 | structured error on stderr (see [[error.uitool.find-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (defined by [[domain.uitool.ipc]]'s exit-code table; not a find-specific error) |

## Invariants

- Read-only and side-effect-free; idempotent — re-running with the same target state yields byte-identical output (modulo the suppressible `sessionId`).
- Filtering and projection happen **server-side**; the CLI never pulls the tree to filter or project locally (per [[domain.uitool.selector]]).
- Never exits 0 on failure. A valid 0-match result is distinct from a usage error (exit 2) — re-issuing the same query is the wrong recovery for a 0-match.
- `--count-only` reports `totalMatched` unaffected by `--limit`; with records, `_meta.totalMatched` likewise reflects all matches, not just the returned slice.
- Class predicates resolve through the runtime class hierarchy, not string equality (per [[domain.uitool.selector]]).
- Predicate `matches`/`~` operands evaluate as Swift-native `Regex` (case-insensitive, unanchored substring); an invalid pattern is rejected at parse time (exit 2), never deferred to a partial result.
- Evaluation is total and bounded — no selector or predicate can hang the target (per [[domain.uitool.selector]]); exceeding the main-thread budget yields exit 7, not a hang.

## Notes

- **Cost tier: cheap / bounded.** `find --count-only` is the cheapest sizing call; `find --where … --limit N --fields …` is bounded by `--limit` (default 50) and the projection. This is the first verb the Skill steers toward — locate few → project narrow → read deep on the survivors. The expensive deep-read verbs (`node`, `font`, `layer`, `constraints`) then operate on the 1–3 survivors `find` returns.
- Batching: large inputs are stdin JSON-Lines elsewhere in the surface (per HANDOFF §8.5). `find` itself is single-query per spawn — one `--class`/`--where` per process — in this build; stdin batching of selectors/predicates is reserved for the node-resolution verbs, where a batch of stable handles is the natural unit.


## Source: `Features/uitool/0004-tree/commands/uitool.tree.md`

---
id: command.uitool.tree
kind: command
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.selector, domain.uitool.ipc]
---

# `uitool tree` — depth-bounded hierarchy walk

The structural-exploration verb. Walks the view hierarchy from a chosen root
down a finite depth, projects a chosen set of fields per node, and emits an
explicit truncated marker at every branch cut off by the depth limit. It never
walks the whole tree — `--depth` is always finite and small by default. The
coding agent is the consumer; output is machine-first.

## Synopsis

```
uitool tree <app> [--at NODE] [--depth N] [--fields a,b,c] [--where EXPR] [--limit N] [--count-only] [--jsonl]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | target selector — pid or bundle id of an attached app |
| `--at` | string | no | node id ([[domain.uitool.node-id]]) to root the walk at. Default: when `--at` is omitted, the walk roots at the target's **key window** — the same root the IPC `hierarchy` op selects for `window:"auto"`. A target with no key window (no front window, fully backgrounded) yields an empty walk (exit 0, `_meta.totalMatched: 0`), not an error. To walk a specific non-key window, pass its window-root node id (from a prior `windows` call) as `--at`. |
| `--depth` | int | no | levels to descend below the root, inclusive of the root level. Default: **2**. This is the Skill-steered structural-skim depth (`tree --depth 2`); deeper walks are an explicit, costed choice. `--depth` is always finite — there is no "walk everything" value. |
| `--fields` | string | no | comma-separated projection paths (e.g. `node,class,frame`), as defined by [[domain.uitool.node]]'s dotted field projection. Default: the default projection from [[domain.uitool.node]] |
| `--where` | string | no | server-side filter expression ([[domain.uitool.selector]]) applied to nodes within the depth window. The predicate selects which nodes are **emitted**; it does not prune the walk. A node that fails `--where` is omitted from the result, but the walk still descends into its in-window descendants and emits any of them that match — a deep match is never hidden behind a shallow non-match. Parent linkage in emitted records refers to the nearest *emitted* ancestor; when an intermediate ancestor was filtered out, its `parent` is the nearest surviving ancestor within the depth window (and is absent for the walk root). A `--where` expression that does not parse is a `BAD_PREDICATE` error (exit 2) before any walking begins — see [[error.uitool.tree-bad-projection]]. |
| `--limit` | int | no | maximum number of node records to emit; the walk stops once reached. Default: **50**. The default exists so an unexpectedly wide level can never flood the agent's context; raise it deliberately with `--limit N` when a known-wide level must be read whole. A walk stopped by `--limit` sets `_meta.truncated: true`. To size a query before paying for it, use `--count-only`. |
| `--count-only` | flag | no | size the query without transferring node bodies: run the walk + `--where` filter server-side and return only the envelope (`schemaVersion`, `sessionId`, `_meta`) with `_meta.totalMatched` set to the number of nodes the walk matched within the depth window. No node records cross the wire. Use it to decide whether to widen `--limit`, tighten `--where`, or descend a different branch before paying for the bodies. |
| `--jsonl` | flag | no | explicit opt-in to the JSON-Lines stream output shape. **JSON-Lines is already the default for `tree`** (it is a list/stream verb), so `--jsonl` is a no-op kept for symmetry with the other stream verbs and for callers that want to state the shape explicitly. `tree` never emits a single nested object; the wire shape is always one node record per line followed by the trailing envelope line. |

## Behavior

1. Resolve `<app>` to the attached target's socket; if there is no live session
   (never attached, or the session has gone away), this is exit 4 — not a
   precondition failure (preconditions are attach-time only, see States & exit
   codes).
2. Resolve `--at` to a live object: re-walk the structural path and validate per
   [[domain.uitool.node-id]]'s deref rules. On any mismatch, return `STALE_NODE` —
   never dereference a recycled pointer. When `--at` is omitted, the root is the
   target's key window (`window:"auto"`), resolved the same way.
3. Issue the [[domain.uitool.ipc]] `hierarchy` op with `maxDepth` from `--depth`, the
   resolved root, and `include` derived from `--fields`. Filtering and projection
   happen **server-side, in the injected agent** — only the projected, in-window,
   matching nodes cross the wire.
4. The server walks each node down to `maxDepth`. At a node that has children but
   sits at the depth limit, it emits `truncated: true` and `childCount` and omits
   `children` — the depth-cut marker contract defined by [[domain.uitool.node]] (its
   `children` field is present only within `--depth`; past it, omitted with
   `truncated: true` + `childCount`).
5. Apply `--where` to select which walked nodes are emitted; a non-matching node
   is dropped from the result but its in-window descendants are still walked and
   emitted on their own merits.
6. Project each emitted node to the requested `--fields`; `node` is always
   present so the agent can drill in later.
7. Emit the result, stopping at `--limit`. A capped result sets
   `_meta.truncated: true` ([[domain.uitool.ipc]]'s single canonical "more exist" flag).
   Under `--count-only`, steps 6–7 are skipped: no node bodies are emitted, only
   the envelope with `_meta.totalMatched`.

## Output

Each node follows [[domain.uitool.node]] — same field semantics, same precision, same
truncated-marker shape. The agent uses each node's `node` handle to issue
follow-up `node` calls on survivors.

`tree` emits a **JSON-Lines stream**: one node record per line, in walk order,
followed by a single trailing envelope line. The agent consumes incrementally,
and an interrupted read still yields N whole, valid node records up to the cut.
This is the contracted wire shape (`--jsonl` is the explicit, no-op opt-in to
it); `tree` never emits a single nested object.

```jsonc
{"node":"7:w0/cv/sv2","parent":"7:w0/cv","class":"NSScrollView","frame":{"x":0,"y":0,"w":280,"h":600},"childCount":1}
{"node":"7:w0/cv/sv2/sub0","parent":"7:w0/cv/sv2","class":"NSClipView","childCount":1,"truncated":true}
{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":2,"truncated":true,"totalMatched":2}}
```

The trailing envelope line conforms to [[domain.uitool.ipc]]'s envelope — a top-level
`schemaVersion` (semver string, in *every* payload and never stripped), a
top-level `sessionId` (string), and, on this list/stream verb, `_meta:
{returned, truncated, totalMatched}`; `--no-meta` strips `sessionId` and `_meta`
but not `schemaVersion`:

- A node cut off by `--depth` carries `truncated: true` + `childCount` and omits
  `children`. A node whose whole subtree is within `--depth` is never marked
  truncated.
- `_meta.returned` is the node count emitted; `_meta.totalMatched` is the count
  of nodes the walk matched within the depth window (0 for an empty walk). Under
  `--count-only`, `_meta.returned` is 0 and `_meta.totalMatched` carries the full
  matched count.
- `_meta.truncated` — the single canonical "more exist past the limit/depth"
  flag — is true if any branch was depth-cut or if `--limit` stopped the walk.
- Output is deterministic per [[domain.uitool.node]]'s determinism invariant: stable key
  order, children in subview / z-order, frames to 1 dp, no addresses/timestamps in
  the default projection (modulo the suppressible top-level `sessionId`).

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table. `tree` is a **post-attach query
verb**, so it carries neither exit 3 (app not running) nor exit 6 (precondition)
— both are attach-time only, emitted while `doctor` / `list-apps` / `attach`
resolve and inject. An unreachable session surfaces here as exit 4 (not
attached) or exit 7 (timeout), never 3 or 6.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (including a fully-contained tree, a depth-truncated tree, a `--count-only` sizing, and a walk that contains zero nodes) | 0 | the payload on stdout |
| usage / unknown `--fields` path (`UNKNOWN_FIELD`) / malformed `--where` predicate (`BAD_PREDICATE`) | 2 | structured error on stderr — see [[error.uitool.tree-bad-projection]] |
| not attached / injection failed (or a session that has gone away post-attach) | 4 | structured error on stderr |
| `--at` handle is stale | 5 | structured error on stderr — see [[error.uitool.tree-stale-root]] |
| main-thread snapshot timed out | 7 | structured error on stderr |
| schema-version mismatch | 8 | structured error on stderr |

A valid walk that matches/contains zero nodes (an empty subtree, a target with
no key window, or a `--where` that excludes everything) is **exit 0**, not an
error — the response carries an empty stream and `_meta.totalMatched: 0`. The
agent distinguishes empty from error by reading `_meta`, never by the exit code;
a 0-match result means *broaden the selector*, not re-issue. See
[[domain.uitool.ipc]].

## Invariants

- Read-only and side-effect-free; idempotent. Same target state → byte-identical
  output (modulo the suppressible `sessionId`).
- `--depth` is always finite; the command never walks the whole tree regardless
  of input.
- Every emitted node carries its `node` handle even under the narrowest `--fields`.
- A depth-cut node is always distinguishable from a leaf: `truncated: true` +
  `childCount > 0` vs `childCount: 0` (a leaf is never marked truncated).
- Never exits 0 on failure; a stale `--at` is exit 5, never a silent empty tree.
- A truncated read (process killed mid-stream) still yields whole, valid node
  records up to the cut — a property of the JSON-Lines wire shape.
- `--count-only` transfers no node bodies; it returns only the envelope and is a
  strict subset of a full walk's work (same matched count, no projection cost).

## Notes

- **Cost tier: cheap / bounded.** This is one of the read verbs the Skill steers
  toward (`tree --depth 2`); the per-node deep reads (the `node` verb's expensive
  facets — ivars, props) are the costed follow-ups on a single chosen survivor.
  The whole point is tree *search*, not tree *download*.
- Cost scales with `--depth` and subtree fan-out; pair with `--fields` to keep a
  structural skim tiny, `--limit` to cap an unexpectedly wide level, and
  `--count-only` to size a query before paying for the bodies.
- **No stdin batching.** `tree` walks a single root per spawn; batching multiple
  roots through stdin is reserved for the per-node `node` verb (its `--stdin`
  mode). A multi-branch exploration issues one `tree` per branch, each rooted by
  `--at` on a handle from the prior walk — which is exactly the bounded,
  one-branch-at-a-time access pattern this feature exists to make cheap.


## Source: `Features/uitool/0006-node/commands/uitool.node.md`

---
id: command.uitool.node
kind: command
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.ipc]
---

# `uitool node` — deep-read one located node

The drill step of the canonical loop (locate few → project narrow → **read deep on the survivors**). Reads a single node the agent has already located and pulls the on-demand facets the default tree/find projection omits. It does not walk a subtree and does not search.

## Synopsis

```
uitool node <app> --at NODE [--include class,frame,constraints,layer]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | target selector (pid or bundle id) — the attached session to query |
| `--at` | node id | yes | the [[domain.uitool.node-id]] of the single node to read |
| `--include` | comma list | no | facets to pull beyond the default projection; subset of `class,frame,constraints,layer` in the cheap-read MVP (`ivars`/`props` are deferred — see below). Default: none (default projection only) |

The `--include` tokens map to fields of [[domain.uitool.node]]:

| Token | Adds to the record |
| --- | --- |
| `class` | `superclasses` (the runtime hierarchy; the real `class` is already in the default projection) |
| `frame` | **No-op kept for symmetry.** `frame`, `frameTopLeft`, and `isFlipped` are already default-projection fields of [[domain.uitool.node]] (it never omits frames), so `--include frame` requests nothing new — it is accepted (not rejected as a bad token) and changes nothing in the record. The token exists only so an agent can name `frame` uniformly across verbs without special-casing `node`. |
| `constraints` | **Inlines the full constraint list.** The default projection carries only `constraintsCount`; `--include constraints` inlines the walker's `ConstraintNode` (every touching `NSLayoutConstraint` plus the intrinsic-sizing facts — the same shape the dedicated `constraints` verb returns) into the node record, alongside the still-present `constraintsCount`. |
| `layer` | `layer` (the recursive `LayerSnapshot` where `wantsLayer`; `null` otherwise) |

### Deferred facets (`ivars`, `props`) — not available in this build

`--include ivars` and `--include props` are **value-fetching** facets: they invoke live getters / read instance state **inside the target process**, so they belong to the deferred injection / expensive-verb half (see [[domain.uitool.ipc]] → "Default mode: structural, no-invoke" and HANDOFF §8.2 / §11). They are **not part of the cheap-read MVP** and are **not available in this build**:

- The cheap-read `node` build accepts only the structural tokens (`class`, `frame`, `constraints`, `layer`). Passing `ivars` or `props` is reported as a **not-yet-available facet** — an explicit, structured usage error (exit 2) naming the facet and that it requires the injection half — never a silently-dropped token. The agent learns the facet exists but is not yet served, rather than getting a quietly thinner record than it asked for.
- When the injection half lands, `ivars`/`props` join the `--include` vocabulary as value-fetching facets. They run on the target's main thread under [[domain.uitool.ipc]]'s bounded timeout; on timeout the op returns `TIMEOUT` (see [[error.uitool.node-value-timeout]]). Their inlined shape (a map of name → boxed value) and any `--match REGEX` narrowing are specified with that pass, not here.

The `material`, `blendingMode`, and `font` pull-on-demand handling of [[domain.uitool.node]] is unchanged: `material` and `font` are already default-projection fields; `blendingMode` and the visual-effect specifics are reached through their dedicated verbs, not inlined here, and have no `--include` token on `node`.

## Behavior

1. Resolve `<app>` to the attached session's socket (per [[domain.uitool.ipc]] transport).
2. Validate `--at` is a well-formed node id; reject malformed ids as a usage error (exit 2) before issuing any op.
3. Validate the `--include` tokens. An unknown token, or a deferred value-fetching token (`ivars`/`props`) in this build, is a usage error (exit 2) — the deferred ones name the facet and that it requires the injection half.
4. Issue one [[domain.uitool.ipc]] op to read the single node rooted at `--at`, carrying the requested structural `include` facets. The single-node read is the **`hierarchy` op pinned to `maxDepth: 0`** — `node` binds to the tree/hierarchy op at depth 0 rather than a distinct op (per [[domain.uitool.ipc]]'s operations table), so it reads exactly one node and never its descendants.
5. The injected server resolves and validates the node id before any deref (re-walk path, pointer validity, recorded-class match per [[domain.uitool.node-id]]); on mismatch it returns `STALE_NODE`.
6. (Injection half, deferred) Value-fetching facets (`ivars`/`props`, and any facet that invokes live getters) run on the target's main thread under the bounded timeout from [[domain.uitool.ipc]]; on timeout the op returns `TIMEOUT`. The cheap-read structural facets never invoke getters and never hit this path.
7. Project the one node to [[domain.uitool.node]]'s default fields plus exactly the requested facets, and emit it.

## Output

A single JSON object (scalar query, not JSON-Lines) describing one node, per [[domain.uitool.node]]. Default-projection fields always present; only the requested `--include` facets are added. Deterministic per [[domain.uitool.ipc]]: stable key order, fixed precision, no addresses/timestamps in the default projection.

```jsonc
// uitool node com.apple.mail --at 7:w0/cv/sv2/sub0 --include constraints,layer
{
    "schemaVersion": "1.0.0",
    "sessionId": "7",
    "node": "7:w0/cv/sv2/sub0",
    "parent": "7:w0/cv/sv2",
    "class": "NSVisualEffectView",
    "frame": { "x": 0, "y": 40, "w": 280, "h": 600 },
    "frameTopLeft": { "x": 0, "y": 0, "w": 280, "h": 600 },
    "isFlipped": false,
    "hidden": false,
    "alpha": 1.0,
    "identifier": "MailMessageListSidebar",
    "text": null,
    "axRole": "AXGroup",
    "font": null,
    "material": "sidebar",
    "constraintsCount": 4,
    "swiftUIBoundary": false,
    "childCount": 7,
    "constraints": [
        { "firstItem": "7:w0/cv/sv2/sub0", "firstAttribute": "width", "relation": "==", "constant": 280, "priority": 1000 }
    ],
    "layer": { "present": true, "cornerRadius": 6, "masksToBounds": true, "backgroundColor": "#00000000" }
}
```

Requested facets that do not apply to the node are emitted as `null` (e.g. `layer: null` on an unbacked view, or `font: null` on a node with no font carrier), never omitted — so the agent distinguishes "asked, absent" from "not asked". (`--include frame` is the one exception: a no-op that adds nothing, since the frame fields are already default.)

Per [[domain.uitool.ipc]]'s envelope, the record carries a top-level `sessionId` (string) — the wire form of [[domain.uitool.node-id]]'s `sessionEpoch`, so the agent can detect a re-attach. `node` is a scalar query, not a list/stream verb, so it does **not** carry `_meta` (that envelope key is for list/stream verbs only). `--no-meta` strips `sessionId`, making the output byte-identical across sessions.

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | the node object on stdout |
| malformed `--at` / unknown or deferred `--include` token | 2 | structured error on stderr |
| not attached / injection failed (`NOT_ATTACHED`) | 4 | structured error on stderr |
| node id no longer resolves (`STALE_NODE`) | 5 | structured error on stderr (see [[error.uitool.node-stale]]) |
| main-thread / socket timeout on a value-fetching read (`TIMEOUT`) | 7 | structured error on stderr (see [[error.uitool.node-value-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr |

`node` is a post-attach query verb: per [[domain.uitool.ipc]], exit 3 (app not running) and exit 6 (precondition failed) are attach-time only and never surface here. An unreachable session is exit 4 (`NOT_ATTACHED`) or exit 7 (`TIMEOUT`).

## Invariants

- Read-only and side-effect-free for the default projection and the structural facets; idempotent — same target state and same flags yield byte-identical output (modulo the top-level `sessionId` from [[domain.uitool.ipc]]'s envelope, which `--no-meta` strips for byte-identical output across sessions).
- Reads exactly one node — the `hierarchy` op at `maxDepth: 0`. Never emits child node records and never walks a subtree.
- Never exits 0 on failure. A `STALE_NODE` is exit 5, distinct from any success.
- Requested-but-inapplicable facets are `null`, not omitted; unrequested facets are absent, not `null`. `--include frame` is a no-op (the frame fields are already default).
- Value-fetching facets (`ivars`/`props`) are not served in this build and are rejected as a usage error (exit 2), never silently dropped. When served (injection half), they never block the host indefinitely — they are bounded by [[domain.uitool.ipc]]'s main-thread timeout.

## Notes

Cost tier: **cheap/bounded** for the default projection (which already carries `constraintsCount`, `material`, and `font`) and the structural `--include` facets (`class`/superclasses, `frame` no-op, `constraints`, `layer`) — one node, bounded, no-invoke work. **Expensive** for `--include ivars`/`props` (and any facet that invokes live getters): they run code inside the target, are timeout-bounded, and are off by default and deferred to the injection half per HANDOFF §8.2 / §11.

Batching: large id lists go over stdin as JSON-Lines (`uitool node --stdin < ids.jsonl`) so the agent resolves many nodes in one process spawn. With `--stdin` the output is **one JSON object per line (JSON-Lines), one per input id, in input order**, each line carrying that node's record (or a per-line error object for a stale/failed id). A `STALE_NODE` (or other per-id failure) on one id emits a per-line structured error and **continues** the batch rather than aborting it; the process exits **0** when every line was emitted (success or per-line error) and reserves a non-zero exit for a batch-level failure (not attached, schema mismatch, malformed stream). The per-line error object carries the same `code`/`message`/`recover` shape as the single-node stderr error, keyed to its input id, so the agent reconciles results to ids without losing the rest of the batch.


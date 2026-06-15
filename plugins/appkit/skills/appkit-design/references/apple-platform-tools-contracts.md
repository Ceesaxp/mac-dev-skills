<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# sdk-api and sdk-search contracts

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.

## Source: `Specs/models/agent-cli.md`

---
id: domain.agent-cli
kind: domain
---

# Domain: the AgentCLI contract

The machine contract every tool in this repo obeys, realized as the `AgentCLI` library so honoring it is a dependency, not a memory. This is the through-line that lets one agent drive a symbol-graph query engine and a live process inspector the same way. See `ARCHITECTURE.md` → "The unifying contract".

`AgentCLI` is **pure** (Foundation only — no ArgumentParser, no I/O beyond the explicit stdout/stderr edges). Its projection functions return strings and are unit-tested on any Mac; the printing/exiting functions are the effectful edge.

## Output projection

- **Scalar result → `Output.json(_:)`** — a pretty-printed JSON string with **sorted keys** and **forward slashes unescaped** (`[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`).
- **Stream → `Output.line(_:)`** — one **compact, single-line** JSON object (sorted keys, slashes unescaped) per record; the stream is newline-delimited (JSON-Lines).
- **`Output.emit(_:)` / `Output.emitLines(_:)`** print the above to **stdout** — the machine payload, and nothing else, lands on stdout.

### Determinism invariants

1. **Sorted keys.** Object members are emitted in sorted key order, always.
2. **No slash escaping.** `/` is never written as `\/`.
3. **Byte-identical for equal input.** The same `Encodable` value encodes to the same bytes across runs and processes.
4. **Stable floats.** Floating-point fields are rounded to a fixed number of decimal places (`stableRounded(_:places:)`, default 3) before encoding, so accumulated FP error never changes the bytes.
5. **No volatile fields in the default projection.** No addresses, timestamps, or PIDs unless a verb explicitly asks for them.
6. **JSON-Lines records carry no embedded newline.** Each record is exactly one line.

A consequence: `diff` over two runs is trustworthy, and an agent may cache results by input.

## Exit-code taxonomy

Exit codes are the control channel; a tool never exits `0` on failure, and a zero-result query (no matches) is **success**, distinct from a failure.

- `ExitStatus.success` = **0**
- `ExitStatus.usage` = **2** (a usage/validation error; matches ArgumentParser's validation exit)

Tools extend the space **above 2** with their own meanings via the `AgentError` protocol (e.g. uitool's `stale-node` = 5, `precondition` = 6, `timeout` = 7). `AgentError` carries:

- `exitCode: Int32` — the code to exit with.
- `message: String` — a human-readable diagnostic, written to **stderr**.

## stdout / stderr discipline

- **stdout** carries the JSON payload alone. No prompts, spinners, progress, color, or pagers — ever.
- **stderr** carries diagnostics: `Diagnostics.warn(_:)` for a non-fatal note, `Diagnostics.fail(_:)` to write an `AgentError`'s message and exit with its code.
- **Color** is off by default and never emitted; `NO_COLOR` is therefore satisfied by construction.

## Acceptance

- `[scenario.agent-cli.sorted-keys]` Object keys encode in sorted order.
- `[scenario.agent-cli.no-escape]` Forward slashes are not escaped.
- `[scenario.agent-cli.deterministic]` Equal input encodes byte-identically.
- `[scenario.agent-cli.jsonlines]` A stream record is one compact object per line, with no embedded newline.
- `[scenario.agent-cli.stable-float]` Float rounding is stable to the requested places.
- `[scenario.agent-cli.exit-taxonomy]` `success` is 0 and `usage` is 2.


## Source: `Features/sdk-api/0001-symbol-queries/commands/sdk-api.check.md`

---
id: command.sdk-api.check
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api check` — does a symbol exist?

## Synopsis

```
sdk-api check <symbol> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<symbol>` | string | yes | Qualified name: `Type` or `Type.member`. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Look up `<symbol>` by exact qualified name. When several declarations share
   the name (overloads, cross-extension redeclarations), the **first** match is
   reported — this is an existence check, not an enumeration.
3. Project the matched symbol (if any) to the `SymbolOut` shape and emit.

## Output

When found:

```jsonc
{
  "query": "<symbol>",
  "exists": true,
  "symbol": {
    "name": "...",
    "qualified": "...",
    "kind": "...",
    "declaration": "...",
    "availability": { "introduced": "...", "deprecated": "...", "obsoleted": "...", "message": "..." }
  }
}
```

`availability` is present only when the symbol carries macOS availability; each
of its fields (`introduced`, `deprecated`, `obsoleted`, `message`) is optional.

When not found:

```jsonc
{ "query": "<symbol>", "exists": false }
```

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| found | 0 | `{query, exists: true, symbol}` on stdout |
| not found | 1 | `{query, exists: false}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- The not-found result is a successful query of a real index, distinguished from
  a load failure by its exit code: `1` (negative answer) vs `64` (could not
  answer). An empty / negative answer is never exit 0 for this verb.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).

## Notes

`check` is the only `sdk-api` verb that exits non-zero on a negative answer, so
an agent can gate code generation on `sdk-api check … && …`. The sibling
list-style verbs (`members`, `availability`, `search`, `enums`) treat an empty
result as success.


## Source: `Features/sdk-api/0001-symbol-queries/commands/sdk-api.availability.md`

---
id: command.sdk-api.availability
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api availability` — a symbol's OS availability

## Synopsis

```
sdk-api availability <symbol> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<symbol>` | string | yes | Symbol name (title or qualified). |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Find every symbol whose qualified name matches exactly, or — failing an exact
   match — whose qualified name or title matches case-insensitively. All matches
   are returned (a symbol can have several declarations).
3. Project each match to `SymbolOut` and emit. The macOS availability lives in
   each match's `availability` field.

## Output

```jsonc
{
  "symbol": "<symbol>",
  "matches": [
    {
      "name": "...",
      "qualified": "...",
      "kind": "...",
      "declaration": "...",
      "availability": { "introduced": "...", "deprecated": "...", "obsoleted": "...", "message": "..." }
    }
  ]
}
```

`availability` is present on a match only when that symbol carries macOS
availability; each of its fields is optional.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no matches) | 0 | `{symbol, matches}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `matches` array is a successful query, exit 0 — distinct from a load
  failure (exit 64).
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).


## Source: `Features/sdk-api/0001-symbol-queries/commands/sdk-api.members.md`

---
id: command.sdk-api.members
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api members` — list a type's members

## Synopsis

```
sdk-api members <type> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<type>` | string | yes | Type name, e.g. `NSGlassEffectView`. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Resolve `<type>` to its container symbol and collect every symbol related to
   it by `memberOf`, sorted by member title.
3. Project each member to `SymbolOut` and emit. An unknown type yields an empty
   `members` array, not an error.

## Output

```jsonc
{
  "type": "<type>",
  "members": [
    { "name": "...", "qualified": "...", "kind": "...", "declaration": "...", "availability": { ... } }
  ]
}
```

Each member follows the `SymbolOut` shape (`name`, `qualified`, `kind`,
`declaration`, optional `availability`).

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. empty members) | 0 | `{type, members}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `members` array (unknown or member-less type) is a successful query,
  exit 0 — distinct from a load failure (exit 64).
- Members are returned in a stable, title-sorted order.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).


## Source: `Features/sdk-api/0001-symbol-queries/commands/sdk-api.enums.md`

---
id: command.sdk-api.enums
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api enums` — list an enum type's cases

## Synopsis

```
sdk-api enums <type> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<type>` | string | yes | Enum type name. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Collect the members of `<type>` and keep only those whose kind is an enum
   case (`swift.enum.case`).
3. Project each case to `SymbolOut` and emit. A type with no enum cases yields
   an empty `cases` array, not an error.

## Output

```jsonc
{
  "type": "<type>",
  "cases": [
    { "name": "...", "qualified": "...", "kind": "...", "declaration": "...", "availability": { ... } }
  ]
}
```

Each case follows the `SymbolOut` shape.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no cases) | 0 | `{type, cases}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `cases` array (non-enum type, or enum with no cases) is a successful
  query, exit 0 — distinct from a load failure (exit 64).
- Cases inherit the title-sorted order of `members`.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).


## Source: `Features/sdk-api/0001-symbol-queries/commands/sdk-api.search.md`

---
id: command.sdk-api.search
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api search` — fuzzy symbol search by name

## Synopsis

```
sdk-api search <query> [--module M] [--limit N]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<query>` | string | yes | Name fragment to search for. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |
| `--limit` | int | no | Max results. Default `20`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Rank symbols against the lowercased query by a fixed precedence — exact title
   > title prefix > qualified-name prefix > title contains > qualified-name
   contains — breaking ties by title, and take the first `--limit`.
3. Project each result to `SymbolOut` and emit.

## Output

```jsonc
{
  "query": "<query>",
  "results": [
    { "name": "...", "qualified": "...", "kind": "...", "declaration": "...", "availability": { ... } }
  ]
}
```

Each result follows the `SymbolOut` shape.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no results) | 0 | `{query, results}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `results` array is a successful query, exit 0 — distinct from a load
  failure (exit 64).
- Ranking and tie-breaking are deterministic; equal input yields byte-identical
  output via the AgentCLI contract (`domain.agent-cli`).

## Notes

This is a name-shaped lookup over the symbol graph, not the HIG/pattern search
that `sdk-search` provides. Use it to discover the exact spelling of a symbol;
use `sdk-search` to discover how to accomplish a task.


## Source: `Features/sdk-search/0001-pattern-search/commands/sdk-search.search.md`

---
id: command.sdk-search.search
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search search` — ranked pattern search

## Synopsis

```
sdk-search search <query...> [--max N] [--category C]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<query...>` | string(s) | yes | One query, or multiple quoted queries for batch mode. |
| `--max` | int | no | Max results per query. Default `5`. |
| `--category` | string | no | Restrict results to one category (case-insensitive). |

## Behavior

1. Load the embedded corpus and build the BM25 search engine.
2. Reject an empty query (no positional args) with a `ValidationError`.
3. **Single-query mode** (exactly one positional arg, including a single quoted
   multi-word string): run the search and emit a `SearchOutput`.
4. **Batch mode** (two or more positional args, each a distinct query): run each
   query in order and emit a `BatchSearchOutput` with one block per query.
   Cross-query dedup applies — a pattern already shown in an earlier query is
   omitted from a later one **unless** its score is ≥ 1.3× the best score it
   earned in an earlier query.
5. Scores are rounded to 3 decimal places for stable output.

## Output

Single query → `SearchOutput`:

```jsonc
{
  "query": "<query>",
  "results": [
    { "id": "...", "title": "...", "category": "...", "summary": "...", "minMacOS": "...", "score": 0.0 }
  ],
  "hint": "Call `sdk-search get <id>` for full code, key APIs, imports, and pitfalls."
}
```

Batch (multiple queries) → `BatchSearchOutput`:

```jsonc
{
  "queries": [
    { "query": "<q1>", "results": [ /* SearchHit… */ ] },
    { "query": "<q2>", "results": [ /* SearchHit…, post-dedup */ ] }
  ],
  "hint": "Call `sdk-search get <id>` for full code, key APIs, imports, and pitfalls."
}
```

`minMacOS` is omitted when the pattern is broadly available. The result body
carries no code — the agent calls `get` for the full pattern.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no results) | 0 | `SearchOutput` / `BatchSearchOutput` on stdout |
| empty query | 64 | `ValidationError` ("Provide at least one query.") on stderr |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline (the corpus is compiled in).
- An empty `results` array is a successful query, exit 0 — distinct from the
  usage error of an empty query (exit 64).
- Ranking is deterministic (score desc, id asc tie-break); scores are stable to
  3 decimal places. Output obeys the AgentCLI contract (`domain.agent-cli`).

## Notes

Batch mode is the way to amortize several related task queries in one call; the
cross-query dedup keeps a strongly-shared pattern from repeating across blocks
unless a later query ranks it substantially higher.


## Source: `Features/sdk-search/0001-pattern-search/commands/sdk-search.get.md`

---
id: command.sdk-search.get
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search get` — full pattern(s) by id

## Synopsis

```
sdk-search get <ids...>
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<ids...>` | string(s) | yes | One or more pattern ids (skill convention: ≤ 3). |

## Behavior

1. Load the embedded corpus.
2. For each id in order, look it up. Found patterns are projected to
   `PatternOutput`; unknown ids are collected as missing.
3. Emit the found patterns: a **single object** when exactly one id was found,
   otherwise a **JSON array** of pattern objects.
4. If any id was missing, write a notice to stderr and exit 1 — the found
   patterns are still printed to stdout first.

## Output

The full pattern shape (`PatternOutput`):

```jsonc
{
  "id": "...",
  "title": "...",
  "summary": "...",
  "category": "...",
  "minMacOS": "...",
  "imports": ["..."],
  "keySymbols": ["..."],
  "swiftCode": "...",
  "pitfalls": ["..."],
  "related": ["..."],
  "replaces": "...",
  "whenToUse": "...",
  "higReference": { "section": "...", "url": "..." }
}
```

One found id → a single object. Two or more found ids → an array of these
objects, in argument order. `minMacOS` and `replaces` are omitted when absent;
`swiftCode` is re-indented to a canonical scale.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| all ids found | 0 | the pattern object / array on stdout |
| some ids missing | 1 | found patterns on stdout; `Pattern(s) not found: <ids>` on stderr |
| all ids missing | 1 | nothing on stdout; `Pattern(s) not found: <ids>` on stderr |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline.
- A partial result (some found, some missing) still emits the found patterns to
  stdout and exits 1 — the missing ids drive the non-zero exit, not the
  successful ones.
- Single-vs-array shape is decided by the count of **found** ids, not the count
  of requested ids.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).


## Source: `Features/sdk-search/0001-pattern-search/commands/sdk-search.list.md`

---
id: command.sdk-search.list
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search list` — enumerate the corpus by category

## Synopsis

```
sdk-search list [--category C]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `--category` | string | no | Restrict to one category (case-insensitive). |

## Behavior

1. Load the embedded corpus.
2. Walk the patterns in corpus order, grouping by `category`. With `--category`,
   keep only patterns whose category matches case-insensitively.
3. Emit groups in the order each category first appears in the corpus; within a
   group, patterns keep corpus order.

## Output

```jsonc
{
  "categories": [
    {
      "category": "...",
      "patterns": [
        { "id": "...", "title": "...", "minMacOS": "..." }
      ]
    }
  ]
}
```

`minMacOS` is omitted when the pattern is broadly available. Each item carries
no code or pitfalls — `list` is the index; `get` is the detail.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no matching category) | 0 | `ListOutput` on stdout |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline.
- Category groups and within-group patterns preserve corpus order (not sorted) —
  a stable, deterministic projection.
- An unknown `--category` yields an empty `categories` array, exit 0.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).


## Source: `Features/sdk-search/0001-pattern-search/commands/sdk-search.debug.md`

---
id: command.sdk-search.debug
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search debug` — expose the ranking pipeline

## Synopsis

```
sdk-search debug <query...>
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<query...>` | string(s) | yes | Query words, joined into one query. |

## Behavior

A tuning aid that exposes the search pipeline rather than ranked patterns.

1. Load the embedded corpus and build the search engine.
2. Join the positional words into one query string.
3. Run the query through each pipeline stage and capture the intermediate state:
   `preprocess` (synonym substitution) → `tokenize` → `expand` (synonym
   expansion). Also capture the distinct raw tokens (the coverage-gate input).
4. Run the search with a high `max` (20) so the relevance floor does not trim,
   exposing the **unfloored** top-20 scores.

## Output

```jsonc
{
  "query": "<joined query>",
  "preprocessed": "...",
  "tokens": ["..."],
  "expanded": ["..."],
  "rawTokens": ["..."],
  "top": [
    { "id": "...", "title": "...", "score": 0.0, "hasNameBoost": false }
  ]
}
```

`tokens` are the post-preprocess tokens; `expanded` adds synonym expansions;
`rawTokens` are the distinct un-preprocessed tokens, sorted; `top` is the
unfloored top-20 by score, each entry noting whether a name boost applied.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | `DebugOutput` on stdout |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline.
- Output is diagnostic, not a recommendation — the `top` scores are unfloored and
  unfiltered, so they differ from `search` output by design.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).

## Notes

This verb exists to tune the BM25 weights, boosts, floor, and coverage gate by
making the preprocess→tokenize→expand pipeline and the raw scores observable. It
is not part of the agent's normal search-then-get loop.


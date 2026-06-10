# Filter→Drill Loop & Selector Grammar

Locate few → project narrow → read deep on the survivors. Never full-dump a tree; filter and project server-side.

## The core discipline

flexscope evaluates selectors **inside the injected target process** — only matching, projected nodes cross the wire. A full tree on Mail is ~10k nodes (≈200k tokens); pulling it to grep locally is the one thing the tool exists to avoid. Size first, then drill.

| ❌ Don't | ✅ Do |
| --- | --- |
| `tree com.apple.mail` (no `--at`/`--depth`/`--fields`) | `find com.apple.mail --where '…' --count-only` first to size |
| Pull the tree and filter/grep it locally | Filter with `--where` server-side; the CLI never filters locally |
| Read deep (`node`/`font`/`layer`/`constraints`) on dozens of nodes | Narrow to 1–3 survivors, then deep-read only those |
| Re-issue an identical query after `totalMatched: 0` | Broaden the selector (0-match is exit **0**, not an error) |

## 1. The canonical loop

| Step | Verb | Purpose |
| --- | --- | --- |
| 1. Orient | `windows <app>` | window roots / ids to anchor `--at` |
| 2. Size | `find <app> --where 'EXPR' --count-only` | match count in `_meta.totalMatched`; cheapest call |
| 3. Locate few | `find <app> --where 'EXPR' --fields PATHS --limit N` | projected matched nodes only |
| 4. Skim structure | `tree <app> --at NODE --depth N --fields PATHS` | depth-bounded walk around one survivor |
| 5. Read deep | `node` / `font` / `layer` / `constraints` on 1–3 survivors | full per-node facts |

- A 0-match `find --count-only` returns `{… "_meta":{"returned":0,"truncated":false,"totalMatched":0}}` at **exit 0** — broaden, don't re-run.
- `_meta.truncated: true` is the single canonical "more exist" flag (never a second `limitHit`) and fires two ways: a **`--limit` cap** on `find` (`totalMatched > returned` → raise `--limit` or tighten the predicate), **or** a **`tree --depth` cut** on a branch (`totalMatched == returned`, branch carries `truncated:true`+`childCount`, omits `children` → re-root `--at` on that branch and/or raise `--depth`).
- `--depth` is always finite; `tree` never walks the whole tree regardless of input.

## 2. Selectors (`--class`) and predicates (`--where`)

CSS-like **structural selectors** — class matching honors the **runtime class hierarchy** (`classHierarchyOfObject:`), so `NSControl` matches an `NSButton`. AX cannot do this (AX has roles, not classes); it is the headline reason flexscope exists.

| Selector form | Meaning |
| --- | --- |
| `NSButton` | by class — honors the runtime subclass hierarchy |
| `NSScrollView NSTableView` | descendant |
| `NSStackView > NSTextField` | direct child |
| `NSView[title*="Inbox"]` | attribute substring |
| `NSView[frame-w>200]` | geometry predicate |
| `*[hidden=false]` | wildcard + attribute |

> `--class` accepts a CSS-like selector per the selector spec; whether `--class` takes a bare class glob only vs. the full combinator grammar (with the rest reserved for `--where`) is **unspecified — see `--help` / schema.**

The `--where` **predicate language** is tiny, *total*, and bounded — no recursion, bounded evaluation time, so a query can't hang the target. Operators:

| Op | Meaning | Op | Meaning |
| --- | --- | --- | --- |
| `=` | equals | `*=` | substring |
| `!=` | not equals | `~` | class-of (runtime hierarchy) |
| `>` `<` `>=` `<=` | numeric compare | `matches` | regex |
| `and` `or` `not` | boolean combinators | `intersects` | (geometry overlap) |

```
class ~ 'NSTextField' and text *= 'Inbox'
frame-w > 200 and hidden = false
```

## 3. The closed v1 attribute vocabulary

Addressable in both `[attr…]` selectors and `--where`. The set is intentionally small and **additive within a major** — no other attribute names are valid.

| Attribute | Type | Source field |
| --- | --- | --- |
| `class` | string (`~` resolves runtime hierarchy) | `class` |
| `identifier` | string | `identifier` |
| `axRole` | string | `axRole` |
| `text` | string (`stringValue` / `title` / `NSText` string) | — |
| `title` | string (window / control title) | — |
| `frame-x` `frame-y` `frame-w` `frame-h` | number | `frame` |
| `hidden` | bool | `hidden` (`isHidden`) |
| `alpha` | number | `alpha` |
| `isFlipped` | bool | `isFlipped` |
| `swiftUIBoundary` | bool | `swiftUIBoundary` |
| `childCount` | int | `childCount` |
| `material` | string (where applicable) | `material` |

`--fields` is a **projection path list**, NOT jq: `node,class,frame,font.family`. Dotted paths reach sub-shapes (`font.family`, `frame.w`). Full jq is deliberately excluded (non-deterministic ordering, unbounded output). `node` is always present even under the narrowest `--fields` so you can drill in later.

> find's default `--fields` projection (when omitted), find's default `--limit`, whether `find` with neither `--class` nor `--where` is legal, and the IPC op-name `find` issues are all **unspecified / [NEEDS CLARIFICATION] — see `--help` / schema.** Likewise `tree`'s `--at` / `--depth` / `--limit` / `--jsonl` defaults and its container shape.

## 4. Worked example: filter→drill, not full-dump

✅ The disciplined loop — size, locate few, project narrow, then deep-read the survivor.

```bash
# 1. Size the selector before pulling anything (cheapest call)
flexscope find com.apple.mail \
  --where "class ~ 'NSTextField' and text *= 'Inbox' and hidden = false" \
  --count-only
# -> {"schemaVersion":"1.0.0","sessionId":"a1b2c3",
#     "_meta":{"returned":0,"truncated":false,"totalMatched":3}}   (exit 0)

# 2. Locate the few, projecting only the fields you need
flexscope find com.apple.mail \
  --where "class ~ 'NSTextField' and text *= 'Inbox' and hidden = false" \
  --fields node,class,frame,font.family,font.size \
  --limit 5
# -> one JSON-Lines node per line, then a trailing _meta line carrying sessionId

# 3. Skim structure around one survivor (finite depth, narrow fields)
flexscope tree com.apple.mail --at "7:w0/cv/sv0/tv0" --depth 2 \
  --fields node,class,frame,childCount

# 4. Read deep on the single chosen survivor
flexscope font com.apple.mail --at "7:w0/cv/sv0/tv0/tr0/c0#b2c4"
```

❌ The foil — a full dump that burns ~200k tokens and forces client-side filtering:

```bash
flexscope tree com.apple.mail        # no --at, no --depth, no --fields:
                                     # walks ~10k nodes, pulls the whole tree,
                                     # then you grep locally. Exactly what the
                                     # server-side filter exists to prevent.
```

## Recovery: reading `_meta`, not the exit code

| Symptom | Meaning | Fix |
| --- | --- | --- |
| `totalMatched: 0`, exit 0 | valid query, no matches | **broaden** the selector; never re-issue identical |
| `truncated: true` | more exist past the cut: `find --limit` cap (`totalMatched > returned`) **or** a `tree --depth` cut on a branch (`totalMatched == returned`) | `find`: raise `--limit` / tighten predicate · `tree`: re-root `--at` on the branch or raise `--depth` |
| exit 2 | malformed selector / unknown `--fields` path | fix syntax; not a 0-match |
| exit 4 | not attached / session gone away | re-attach |
| exit 5 | `--at` handle is stale | re-resolve the node id |
| exit 7 | main-thread snapshot timed out | narrow `--depth` / predicate; not a hang |

Distinguish empty from error by reading `_meta`, never by exit code. flexscope never exits 0 on failure, and a valid 0-match is never an error.

# Filter→Drill Loop & Selector Grammar

Locate few → project narrow → read deep on the survivors. Never full-dump a tree; filter and project server-side.

## The core discipline

uitool evaluates selectors **inside the injected target process** — only matching, projected nodes cross the wire. A full tree on Mail is ~10k nodes (≈200k tokens); pulling it to grep locally is the one thing the tool exists to avoid. Size first, then drill.

| ❌ Don't | ✅ Do |
| --- | --- |
| `tree <app>` with no `--at` | (`tree` requires `--at`; root it at a window node from `windows`) |
| Pull the tree and filter/grep it locally | Filter with a selector / `--where` server-side; the CLI never filters locally |
| Deep-read (`node`/`inspect`) on dozens of nodes | Narrow to 1–3 survivors, then deep-read only those |
| Re-issue an identical query after `totalMatched: 0` | Broaden the selector (0-match is exit **0**, not an error) |

## 1. The canonical loop

| Step | Verb | Purpose |
| --- | --- | --- |
| 1. Orient | `windows <app>` | window roots / ids to anchor `--at` |
| 2. Size | `find <app> <selector> --where 'EXPR' --count-only` | match count in `_meta.totalMatched`; cheapest call |
| 3. Locate few | `find <app> <selector> --where 'EXPR' --fields PATHS --limit N` | projected matched nodes only |
| 4. Skim structure | `tree <app> --at NODE --depth N --fields PATHS` | depth-bounded walk around one survivor |
| 5. Read deep | `node <app> --at NODE --include layer,constraints` / `inspect <app> --at NODE` | full per-node facts / object internals on 1–3 survivors |

- A 0-match `find --count-only` returns `{… "_meta":{"returned":0,"truncated":false,"totalMatched":0}}` at **exit 0** — broaden, don't re-run.
- `_meta.truncated: true` is the single canonical "more exist" flag and fires two ways: a **`--limit` cap** on `find` (`totalMatched > returned` → raise `--limit` or tighten the predicate), **or** a **`tree --depth` cut** on a branch (the branch carries `truncated:true` + `childCount`, omits `children` → re-root `--at` on that branch and/or raise `--depth`).
- `--depth` is always finite (default 2); `tree` never walks the whole tree regardless of input.

## 2. Selectors (positional) and predicates (`--where`)

`find` takes an optional **positional structural selector** plus an optional `--where` predicate. CSS-like class matching honors the **runtime class hierarchy** (`classHierarchyOfObject:`), so `NSControl` matches an `NSButton`. AX cannot do this (AX has roles, not classes); it is the headline reason uitool exists.

| Selector form | Meaning |
| --- | --- |
| `NSButton` | by class — honors the runtime subclass hierarchy |
| `NSScrollView NSTableView` | descendant |
| `NSStackView > NSTextField` | direct child |
| `NSView[title*="Inbox"]` | attribute substring |
| `NSView[frame-w>200]` | geometry predicate |
| `*[hidden=false]` | wildcard + attribute |

The `--where` **predicate language** is tiny, *total*, and bounded — no recursion, bounded evaluation time, so a query can't hang the target. Operators:

| Op | Meaning | Op | Meaning |
| --- | --- | --- | --- |
| `=` | equals | `*=` | substring |
| `!=` | not equals | `~` | class-of (runtime hierarchy) |
| `>` `<` `>=` `<=` | numeric compare | `matches` | regex |
| `and` `or` `not` | boolean combinators | `intersects` | geometry overlap |

```
class ~ 'NSTextField' and text *= 'Inbox'
frame-w > 200 and hidden = false
```

**Regex semantics (`*=` / `matches` / `[attr*="…"]`).** Backed by Swift's native `Regex`, **not** `NSRegularExpression`: **case-insensitive, unanchored substring** (`firstMatch`, not whole-string). `text *= 'inbox'` matches `"Inbox Unread"`; anchor explicitly with `^…$`. `*=` is literal-escaped substring sugar over `matches`, so only an explicit `matches` regex can be malformed. An uncompilable pattern is rejected **before any node is touched** as `BAD_SELECTOR` (exit 2) — never silently treated as a literal or a 0-match.

> Note `--class` is **not** a `find` flag — it belongs to the `classes` verb (`classes <app> --class <name>` reflects one class; `classes <app> --match <regex>` lists names). `classes` glob/regex matching is separate from the `find` selector grammar.

## 3. The v1 attribute vocabulary

Addressable in both `[attr…]` selectors and `--where`, all sourced from the node record. The set is intentionally small and **additive within a major** — no other attribute names are valid.

| Attribute | Type | Notes |
| --- | --- | --- |
| `class` | string | `~` resolves the runtime hierarchy |
| `identifier` | string | `NSUserInterfaceItemIdentifier` |
| `axRole` | string | accessibility role |
| `text` | string | `NSTextField.stringValue` / `NSButton.title` / `NSText` string |
| `title` | string | window / control title |
| `frame-x` `frame-y` `frame-w` `frame-h` | number | from `frame` |
| `hidden` | bool | `isHidden` |
| `alpha` | number | `alphaValue` |
| `isFlipped` | bool | the silent-correctness trap |
| `swiftUIBoundary` | bool | true at an `NSHostingView` |
| `childCount` | int | number of subviews |
| `material` | string | `NSVisualEffectView.material`, where applicable |

`--fields` is a **projection path list**, NOT jq: `node,class,frame,font.family`. Dotted paths reach sub-shapes (`font.family`, `frame.w`). A `--fields` path that names no node field is a usage error (`UNKNOWN_FIELD`, exit 2); a `--where` the grammar can't parse is `BAD_PREDICATE` (exit 2) — distinct codes, never collapsed. `node` is always present even under the narrowest `--fields` so you can drill later.

## 4. Worked example: filter→drill, not full-dump

✅ The disciplined loop — size, locate few, project narrow, then deep-read the survivor.

```bash
# 1. Size the selector before pulling anything (cheapest call)
uitool find com.example.MailClone \
  --where "class ~ 'NSTextField' and text *= 'Inbox' and hidden = false" \
  --count-only
# -> {"schemaVersion":"1.0.0","sessionId":"a1b2c3",
#     "_meta":{"returned":0,"truncated":false,"totalMatched":3}}   (exit 0)

# 2. Locate the few, projecting only the fields you need
uitool find com.example.MailClone \
  --where "class ~ 'NSTextField' and text *= 'Inbox' and hidden = false" \
  --fields node,class,frame,font.family,font.size \
  --limit 5
# -> one JSON-Lines node per line, then a trailing summary line carrying sessionId + _meta

# 3. Skim structure around one survivor (finite depth, narrow fields)
uitool tree com.example.MailClone --at "7:w0/cv/sv0/tv0" --depth 2 \
  --fields node,class,frame,childCount

# 4. Read deep on the single chosen survivor
uitool node com.example.MailClone --at "7:w0/cv/sv0/tv0/tr0/c0" --include layer,constraints
uitool inspect com.example.MailClone --at "7:w0/cv/sv0/tv0/tr0/c0" --match '(font|color)'
```

❌ The foil — a full dump that burns ~200k tokens and forces client-side filtering:

```bash
uitool tree com.example.MailClone --at 7:w0 --depth 99   # ❌ unbounded walk; pulls the whole tree,
                                                          # then you grep locally — exactly what
                                                          # server-side filtering exists to prevent.
```

(The cooperative example targets a `get-task-allow` app you build — `com.example.MailClone` — not a system app. System apps like Mail are the unrestricted posture; see `doctor-and-dev-box.md`.)

## Recovery: reading `_meta`, not the exit code

| Symptom | Meaning | Fix |
| --- | --- | --- |
| `totalMatched: 0`, exit 0 | valid query, no matches | **broaden** the selector; never re-issue identical |
| `truncated: true` | more exist past the cut: `find --limit` cap (`totalMatched > returned`) **or** a `tree --depth` cut on a branch | `find`: raise `--limit` / tighten predicate · `tree`: re-root `--at` on the branch or raise `--depth` |
| exit 2 | `BAD_SELECTOR` / `UNKNOWN_FIELD` (bad `--fields` path) / `BAD_PREDICATE` | fix syntax; not a 0-match |
| exit 4 | not attached / session gone | re-attach |
| exit 5 | `--at` handle is stale (`STALE_NODE`) | re-walk with `find`/`tree` for a fresh id |
| exit 7 | main-thread snapshot timed out | narrow `--depth` / predicate, retry once when the target is idle |

Distinguish empty from error by reading `_meta`, never by exit code. uitool never exits 0 on failure, and a valid 0-match is never an error.

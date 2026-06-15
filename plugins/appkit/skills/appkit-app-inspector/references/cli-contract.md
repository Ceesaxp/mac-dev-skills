# uitool CLI Contract

The per-verb wire contract: invocation, the JSON envelope, the node/window/inspect records, and per-verb flags. `uitool schema` prints the authoritative record fields + exit codes as JSON — when in doubt, read it rather than this file.

## 1. Invocation + envelope

Invoke as `uitool <verb> <app> [flags]`. `<app>` is the attached target by **pid or bundle id** for the read verbs; `launch` / `attach` / `signing` also accept a `.app` path or an executable path. JSON on **stdout**; one-line structured diagnostics on **stderr**. The agent branches on the **exit code**, never on parsed prose.

| Exit | Meaning |
| --- | --- |
| 0 | ok (a 0-match query is exit 0, with `_meta.totalMatched: 0`) |
| 2 | usage / `BAD_SELECTOR` / `UNKNOWN_FIELD` / `BAD_PREDICATE` |
| 3 | `APP_NOT_RUNNING` / `APP_NOT_FOUND` |
| 4 | `NOT_ATTACHED` / injection failed |
| 5 | `STALE_NODE` (verbs taking `--at`) |
| 6 | precondition failed (`doctor` gate) |
| 7 | `TIMEOUT` (≈500 ms main-thread hop, or socket) |
| 8 | schema-version mismatch |

❌ Don't treat a 0-match result as an error or re-issue the same query — 0 means *broaden the selector*.
✅ Do read `_meta.totalMatched` to tell "asked, found nothing" from a real failure.

**Envelope.** Post-attach payloads carry `schemaVersion` (a semver **string**, e.g. `"1.0.0"`). Unless `--no-meta` is passed, responses also carry a top-level `sessionId` (string; a changed value means a re-attach happened, so held node ids are stale), and the streaming list verbs carry `_meta: {returned, truncated, totalMatched}`.

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | string | on post-attach payloads; not stripped by `--no-meta` |
| `sessionId` | string | top-level; **stripped by `--no-meta`** |
| `_meta.returned` | int | records emitted |
| `_meta.truncated` | bool | the single canonical "more exist past limit/depth" flag |
| `_meta.totalMatched` | int | full server-side match count, ignoring `--limit` |

- **Stream verbs** (`windows`, `tree`, `find`) emit **JSON-Lines**: one record per line, then a trailing summary line carrying `schemaVersion` + `sessionId` + `_meta`. `sessionId`/`_meta` appear **once**, on the summary line. (`--count-only` is the exception — a single object with `_meta.totalMatched`.)
- **Scalar verbs** (`node`, `inspect`, `classes`, `signing`, `attach`, `detach`) emit a **single JSON object** carrying `schemaVersion` + (unless `--no-meta`) `sessionId`.
- `doctor`, `list-apps`, `schema`, and `signing` answer **before any IPC socket exists** (or without one), so they are not bound by the post-attach envelope — `doctor`/`schema`/`signing` are plain objects; `list-apps` is JSON-Lines of app records.
- `attach`/`detach` result flags (`reused`, `wasAttached`) are command-result fields, not `_meta`, and are never stripped.

## 2. Per-verb table

| Verb | Purpose | Key flags / args | Output |
| --- | --- | --- | --- |
| `doctor` | machine posture (local) | *(none shipped)* | two ModeReports — see `doctor-and-dev-box.md` |
| `signing` | a target's signature + `cooperativeInjectable` (local) | `<target>` (pid/bundleid/.app/exe), `--pretty` | scalar object |
| `list-apps` | attachable GUI apps (local) | *(none)* | JSON-Lines of `{pid,name,bundleId,arch,hardened}` |
| `launch` | spawn-inject, fresh state | `<app>`, `--replace`, `[-- <app-args>…]`, `--pretty`, `--no-meta` | scalar; `ok/target/path/channel/replaced/sessionId` |
| `attach` | attach-to-running, preserve state | `<app>`, `--pretty`, `--no-meta` | scalar; `ok/target/path/channel/reused/sessionId` |
| `detach` | end session | `<app>`, `--pretty`, `--no-meta` | scalar; `ok/target/channel/wasAttached/sessionId` |
| `windows` | top-level windows | `[<app>]`, `--snapshot`, `--no-meta` | JSON-Lines; window records |
| `tree` | depth-bounded walk | `[<app>]`, `--at` (req), `--depth` (=2), `--where`, `--fields`, `--include`, `--limit` (=50), `--count-only`, `--snapshot`, `--no-meta` | JSON-Lines; node records |
| `find` | locate few, server-side | `[<app>]`, `[<selector>]`, `--where`, `--fields`, `--include`, `--limit` (=50), `--count-only`, `--snapshot`, `--no-meta` | JSON-Lines (or single obj when `--count-only`) |
| `node` | deep-read one node | `[<app>]`, `--at` (req), `--include`, `--snapshot`, `--no-meta` | scalar node |
| `inspect` | a live object's internals | `<app>`, `--at` (req), `--invoke`, `--match <regex>`, `--pretty`, `--no-meta` | scalar inspect record |
| `classes` | loaded classes | `<app>`, `--match <regex>` (list) \| `--class <name>` (reflect one), `--limit` (=200), `--pretty`, `--no-meta` | scalar; names list or one class shape |
| `schema` | the output contract | `--pretty` | scalar; `{exitCodes, records, schemaVersion}` |

`--snapshot <path>` reads a captured Capture JSON instead of attaching (offline; on `windows`/`tree`/`find`/`node`) — omit `<app>` when using it. `--fields` is a comma-separated projection-path list (e.g. `node,class,frame`), not jq. `--include` pulls extra facets (below). There is **no** `font` / `layer` / `constraints` / `fonts` / `ax-diff` verb.

## 3. The node record (`windows` / `tree` / `find` / `node`)

Default-projection fields are always present; the rest are pulled via `--include`. From `uitool schema`:

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `node` | string | ✓ | stable id, e.g. `7:w0/cv/vev0` |
| `parent` | string \| null | ✓ | null at a window root |
| `class` | string | ✓ | **real** runtime class (`object_getClass`) — the whole point vs AX |
| `frame` | {x,y,w,h} | ✓ | raw NSView coords (bottom-left origin), 1 dp |
| `frameTopLeft` | {x,y,w,h} | ✓ | normalized top-left, window-relative |
| `isFlipped` | bool | ✓ | the #1 silent-correctness trap |
| `hidden` | bool | ✓ | `isHidden` |
| `alpha` | number | ✓ | `alphaValue`, 1 dp |
| `identifier` | string \| null | ✓ | `NSUserInterfaceItemIdentifier` |
| `text` | string \| null | ✓ | the view's text content |
| `axRole` | string \| null | ✓ | accessibility role |
| `font` | Font \| null | ✓ | decomposed `NSFont` snapshot (null where no carrier) |
| `material` | string \| null | ✓ | `NSVisualEffectView.material` |
| `swiftUIBoundary` | bool | ✓ | true at an `NSHostingView` |
| `childCount` | int | ✓ | number of subviews |
| `constraintsCount` | int | ✓ | count only; full list via `--include constraints` |
| `children` | Node[] | ✓ | present only within `--depth` |
| `truncated` | bool | ✓ | true when children were omitted at the depth bound |
| `superclasses` | string[] | `--include class` | runtime class chain |
| `blendingMode` | string \| null | `--include blendingMode` | visual-effect blending mode |
| `layer` | Layer \| null | `--include layer` | `CALayer` snapshot (null when unbacked) |
| `constraints` | Constraint | `--include constraints` | the touching `NSLayoutConstraint`s, both directions |

Note `font` and `material` are **default** fields (no `--include` needed). The `--include` vocabulary is `class`, `blendingMode`, `layer`, `constraints` (the `--help` lists `class,frame,constraints,layer`). For the exact `Font` / `Layer` / `Constraint` sub-shapes, read a live record or `uitool schema`.

❌ Don't infer top-left origin from `frame` alone — `frame`/`frameTopLeft`/`isFlipped` are always emitted together.
❌ Don't assert class names below a `swiftUIBoundary:true` node are hand-written AppKit controls.

**window record** (`windows`): `node` (`w<n>`), `parent` (always null), `class`, `title`, `key`, `main`, `frame` (**screen** coords, 1 dp). At most one `key` and one `main`; both may be zero (backgrounded / panels-only) — never synthesized.

**inspect record** (`inspect`): `node`, `class`, `ivars` (`[{name,type,value}]`, safe memory reads), `properties` (`[{name,type,readonly,value?}]` — `value` only with `--invoke`), `protocols` (`string[]`), `methods` (`string[]`). `--match <regex>` narrows ivars/properties by name.

## 4. Selectors and predicates

`find` takes an optional positional **structural class selector** (e.g. `'NSScrollView NSTableView'` — descendant; honors the runtime class hierarchy, which AX can't) and/or a `--where` predicate over attributes. `tree` takes `--where` to filter which walked nodes are emitted. Grammar and the attribute vocabulary: `references/filter-drill-and-selectors.md`.

# flexscope CLI Contract

The frozen per-verb wire contract: invocation, the JSON-Lines envelope, the node shape, per-verb flags/fields, and the deep-read facets. Author against this exactly; never invent a value marked unspecified.

## 1. Invocation + envelope

Invoke as `flexscope <verb> <app=pid|bundleid> [flags]`. JSON on **stdout**; one-line structured diagnostics on **stderr**. The agent branches on the **exit code**, never on parsed prose.

| Exit | Meaning | Channel |
| --- | --- | --- |
| 0 | ok (a 0-match query is exit 0, with `_meta.totalMatched: 0`) | — |
| 2 | usage / bad selector | any verb |
| 3 | app not running | **attach-time only** (`attach`) |
| 4 | not attached / injection failed | post-attach verbs |
| 5 | stale node (`STALE_NODE`) | verbs taking `--at` |
| 6 | SIP/AMFI/LV/arch precondition failed | **attach-time only** (`doctor`, `attach`) |
| 7 | socket / main-thread timeout | post-attach verbs |
| 8 | schema-version mismatch | post-attach verbs |

❌ Don't treat a 0-match result as an error or re-issue the same query — 0 means *broaden the selector*.
✅ Do read `_meta.totalMatched` to tell "asked, found nothing" from a real failure.
❌ Don't branch on exit 3/6 in a post-attach verb — an unreachable session is exit 4 or 7.

**Envelope.** Every payload carries `schemaVersion` (a semver **string**, e.g. `"1.0.0"` — distinct from the int wire `v`). Unless `--no-meta` is passed, responses also carry top-level `sessionId` (string; the wire form of node-id's `sessionEpoch`, for re-attach detection) and list/stream responses carry `_meta: {returned, truncated, totalMatched}`.

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | string | on **every** payload; never stripped by `--no-meta` |
| `sessionId` | string | top-level; **stripped by `--no-meta`** |
| `_meta.returned` | int | records emitted |
| `_meta.truncated` | bool | the **single** canonical "more exist past limit/depth" flag — never a second `limitHit` |
| `_meta.totalMatched` | int | full server-side match count, ignoring `--limit` |

- **Per-line stream verbs** (`windows`, `tree`, `find`) emit **JSON-Lines**: one record per line, then a trailing summary line carrying `sessionId` + `_meta`. `sessionId` appears **once**, on the summary line, never per record. (`find --count-only` is the exception — a single object with `_meta.totalMatched`.)
- **List-wrapper verbs** (`fonts`, `constraints`) emit a **single JSON object** that carries top-level `sessionId` + **inline** `_meta` over an array (`fonts[]` / `constraints[]`). Not per-line; not `_meta`-free. `--no-meta` strips `sessionId`/`_meta`.
- **Scalar verbs** (`node`, `font`, `layer`, `ax-diff`, `attach`, `detach`) emit a **single JSON object**, carry `sessionId`, and carry **no** `_meta`.
- Error responses (`ok:false`) carry `schemaVersion` + the `error` object, **not** `sessionId`/`_meta`.
- `doctor` and `list-apps` answer **before any IPC socket exists**, so their result objects are **not** bound by this envelope (no `schemaVersion`/`sessionId`/`_meta`).
- `--no-meta` strips `sessionId`/`_meta` for byte-identical diffs across sessions. `attach`/`detach` result flags (`reused`, `wasAttached`) are command-result fields, **not** `_meta`, and are never stripped.

## 2. Per-verb table

| Verb | Purpose | Key flags | Output shape |
| --- | --- | --- | --- |
| `doctor` | verify injection preconditions (local) | `--fix` (opt-in sudo remediation) | scalar; verdict + 6 checks |
| `list-apps` | enumerate attachable processes (local) | `--match <substring>` | scalar; `apps[]` |
| `attach` | make a target inspectable (mutating) | `--relaunch`, `--pretty`, `--no-meta` | scalar; `ok/target/path/channel/reused/sessionId` |
| `detach` | end a session (mutating) | `--pretty`, `--no-meta` | scalar; `ok/target/channel/wasAttached/sessionId` |
| `windows` | list top-level windows | `--pretty`, `--no-meta` | JSON-Lines; window records |
| `tree` | depth-bounded hierarchy walk | `--at`, `--depth`, `--fields`, `--where`, `--limit`, `--jsonl` | JSON-Lines (container shape unspecified — see schema) |
| `find` | locate few server-side | `--class`, `--where`, `--fields`, `--limit`, `--count-only` | JSON-Lines (or single obj when `--count-only`) |
| `node` | deep-read one located node | `--at` (req), `--include` | scalar node |
| `font` | resolve the font on one node | `--at` (req) | scalar; `font` or `font:null` |
| `fonts` | de-duped font inventory for a subtree | `--at` (optional) | JSON-Lines wrapper; `fonts[]` |
| `layer` | CALayer subtree for a node | `--at` (req) | scalar; recursive `layer` |
| `constraints` | Auto Layout for a node, both directions | `--at` (req) | scalar; list + intrinsic facts |
| `ax-diff` | what AX sees vs what FLEX sees | `--at` (req), `--out` | scalar; `ax`/`flex`/`diff` |

**Default flag values** (`tree --depth`, `tree --limit`, `find --limit`, `find --fields`, whether `find` requires `--class`/`--where`, the `--at`-omitted default root for `tree`/`fonts`): **unspecified — see `--help` / schema.** Do not invent them.

**doctor checks** — frozen, byte-stable, **always in this order**. `detail` is a fixed token, never prose; `remedy` (one line) appears only on a failing check. `ok` is true only when all six pass; any failure is exit **6**.

| `check` | `detail` pass | `detail` fail |
| --- | --- | --- |
| `sip` | `disabled` | `enabled` |
| `amfi` | `disabled` | `enforcing` |
| `libval` | `disabled` | `enabled` |
| `arm64e-abi` | `present` | `absent` |
| `arch` | `arm64e` | `arm64` \| `x86_64` |
| `flexmac-built` | `present` | `absent` |

Top-level `osBuild` is machine-specific and normalized out of snapshots (like `sessionId`).

**list-apps**: each app is `{pid, name, bundleId, hardened, arch}`. `arch` ∈ `arm64e`/`arm64`/`x86_64` (never `universal`). Sorted by `bundleId` ascending (no-bundle-id last, by `name`), `name` then `pid` as tiebreakers. Zero matches → `{"apps": []}`, exit 0.

**windows**: each record projects exactly the base node fields `node`, `parent` (always `null` at a root), `class`, `frame` (**screen coords**, bottom-left, 1 dp) plus three **window-only** fields `title`, `key`, `main`. `frameTopLeft`/`isFlipped`/`hidden`/`alpha`/`childCount` do **not** apply to a window root. At most one `key` and at most one `main`; both may be **zero** (backgrounded / panels-only) — the verb never synthesizes one. Order is `NSApp.windows` array order (`w0`=`[0]`), never z-order.

### Node shape (FROZEN — what query verbs return)

Default-projection fields (✓) are always present; the rest are pull-on-demand via `--include` or a dedicated verb.

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `node` | string | ✓ | stable id `<epoch>:<path>#<ptrTag>` |
| `parent` | string \| null | ✓ | null at a window root |
| `class` | string | ✓ | **real** runtime class (`object_getClass`) — the whole point vs AX |
| `superclasses` | string[] | — | via `--include class` |
| `frame` | {x,y,w,h} | ✓ | raw NSView coords (bottom-left), 1 dp |
| `frameTopLeft` | {x,y,w,h} | ✓ | normalized top-left, window-relative |
| `isFlipped` | bool | ✓ | the #1 silent-correctness trap |
| `hidden` | bool | ✓ | `isHidden` |
| `alpha` | number | ✓ | `alphaValue`, 1 dp |
| `identifier` | string \| null | ✓ | `NSUserInterfaceItemIdentifier` |
| `axRole` | string \| null | ✓ | cross-ref to `ax-diff` |
| `material` | string \| null | — | `NSVisualEffectView.material` (node field, **not** a layer fact) |
| `blendingMode` | string \| null | — | `NSVisualEffectView.blendingMode` |
| `font` | Font \| null | — | via `--include font` / `font` verb |
| `layer` | Layer \| null | — | via `--include layer` / `layer` verb |
| `constraintsCount` | int | ✓ | count only; full list via `constraints` |
| `swiftUIBoundary` | bool | ✓ | true at an `NSHostingView` |
| `childCount` | int | ✓ | number of subviews |
| `children` | ViewNode[] | ✓* | present only within `--depth`; past it omitted with `truncated:true` + `childCount` |

❌ Don't infer top-left origin from `frame` alone — `frame`/`frameTopLeft`/`isFlipped` are always emitted together.
✅ Do treat `layer.present:false` as normal; never assume view↔layer 1:1.
❌ Don't assert class names below a `swiftUIBoundary:true` node are hand-written AppKit controls.

### Selector / `--where` attribute vocabulary (FROZEN)

Addressable in `[attr…]` selectors and `--where`: `class` (`~` resolves the runtime hierarchy), `identifier`, `axRole`, `text`, `title`, `frame-x`, `frame-y`, `frame-w`, `frame-h`, `hidden`, `alpha`, `isFlipped`, `swiftUIBoundary`, `childCount`, `material`. Operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `*=` (substring), `~` (class-of / hierarchy), `matches` (regex). `--fields` is a projection path list (`class,frame,font.family`), **not** jq.

## 3. Deep-read facets

**`node --include`** tokens map to node fields: `class` → `superclasses`; `font` → `font` (null where no carrier); `layer` → `layer` (null when unbacked); `frame`, `constraints`, `ivars` → shape **unspecified — see schema** (`ivars` is timeout-bounded and runs code in the target). Requested-but-inapplicable facets are emitted as `null`, never omitted — so "asked, absent" differs from "not asked". `material`/`blendingMode` have **no** `--include` token here.

**`layer`** emits the recursive `Layer` sub-shape (CALayer-native only; **no** `material`/`blendingMode`): `present`, `cornerRadius`, `masksToBounds`, `backgroundColor`, `borderWidth`, `borderColor`, `shadowOpacity`, `shadowRadius`, `shadowOffset` ({w,h}), `shadowColor`, `sublayerTransform`, `mask`, `backgroundFilters`, `sublayers[]` (recursive, in CALayer z-order). Unbacked node → `{"layer": {"present": false}}`, exit 0 (a success). Colors follow the dual contract: `{hex:"#RRGGBBAA", catalogName, appearance}`. The serialization of `backgroundFilters` and a non-identity `sublayerTransform` is **unspecified — see schema**.

**`constraints`** emits, over the constraints list, node-level facts in **both** directions plus sizing: `translatesAutoresizingMaskIntoConstraints`, `hugging:{horizontal,vertical}`, `compressionResistance:{horizontal,vertical}`, `intrinsicContentSize:{w,h}`, and `constraints[]` where each is `{first:{node,attr}, relation, second:{node,attr}, multiplier, constant, priority, active, identifier}`. A constant constraint reports `second.node:null`, `second.attr:"notAnAttribute"`. Empty list → `constraints:[]`, `_meta.totalMatched:0`, exit 0. The array sort key, the `priority`/`relation`/`attr` encodings, and the `NSViewNoIntrinsicMetric` (-1) representation are **unspecified — see schema**.

### One complete example — the canonical loop ending on a deep read

```swift
import Foundation

/// locate few → project narrow → read deep on the 1–3 survivors.
func sidebarLayer(app: String) throws -> Data {
    // 1. find: cheap, server-side, capped. Locate the survivor.
    let find = try run("flexscope", "find", app,
        "--where", "class ~ 'NSVisualEffectView' and identifier *= 'Sidebar'",
        "--fields", "node,class", "--limit", "3")
    guard find.exit == 0 else { throw FlexError(exit: find.exit) } // 4=not attached, 7=timeout
    // JSON-Lines: parse node records, skip the trailing _meta summary line.
    let node = find.stdout.split(separator: "\n")
        .compactMap { try? JSONDecoder().decode(NodeLine.self, from: Data($0.utf8)) }
        .first { $0.node != nil }!.node!

    // 2. read deep on the one survivor. layer is a scalar verb (no _meta).
    let layer = try run("flexscope", "layer", app, "--at", node)
    guard layer.exit == 0 else { throw FlexError(exit: layer.exit) } // 5=STALE_NODE
    return Data(layer.stdout.utf8) // {present, cornerRadius, backgroundColor:{hex,catalogName,appearance}, …}
}
struct NodeLine: Decodable { let node: String? } // _meta line decodes with node == nil
```

```swift
// BAD — dumps the whole tree and greps client-side: blows the context budget and
// re-implements server-side filtering the CLI deliberately keeps off the wire.
let tree = try run("flexscope", "tree", app, "--depth", "99")        // ❌ unbounded walk
let hit = tree.stdout.contains("NSVisualEffectView")                  // ❌ string-match, not class hierarchy
// Also wrong: branching on prose / exit 3 in a post-attach verb, and re-issuing on a 0-match.
```

# Exit Codes & Failure Signatures

Branch on `flexscope`'s exit code; recognize each characteristic failure signature and report its one-line remedy instead of retrying a call that cannot succeed.

`flexscope <verb> <app=pid|bundleid> [flags]` — JSON on stdout, diagnostic JSON on stderr. The agent branches on the exit code **without parsing prose**, then reads the envelope (`_meta`, `error.recover`) to refine.

## Exit-code table (the control channel)

The exit channel is FROZEN. **Exit 1 is unused.** **Exits 3 and 6 are attach-time only.**

| Exit | Meaning | Agent branch |
| --- | --- | --- |
| 0 | ok | Read result. **0 matches is still exit 0** — read `_meta.totalMatched`, do not treat as failure. |
| 2 | usage / bad selector | Fix the selector or flag (malformed node id, bad `[attr]`, unknown verb). Distinct from a 0-match. |
| 3 | app not running | **Attach-time only.** Launch the target, then retry. |
| 4 | not attached / injection failed | You called a query verb with no live session, or injection failed for a **non-precondition** reason (socket never opened, mach-port failure, target died). Re-`attach`; do not re-issue the query verb. (Precondition failures — arch/AMFI/LV/SIP — are exit **6**, not 4.) |
| 5 | stale node | The held node id no longer resolves. **Re-walk** with `find`/`tree` for a fresh id — never re-deref the same id. |
| 6 | SIP/AMFI/LV/arch precondition failed | **Attach-time only.** Run `doctor`; report the failing check + its `remedy`. Do not change SIP/AMFI autonomously. |
| 7 | socket / main-thread timeout | `MAIN_THREAD_TIMEOUT` (≈500 ms hop) or socket error. Ensure session is live (re-`attach` if needed) and retry once. |
| 8 | schema-version mismatch | CLI and dylib desynced (`schemaVersion` semver mismatch / `v` mismatch). Rebuild so CLI and FLEX-mac match. |

Post-attach query verbs never emit 3 or 6: an unreachable session surfaces as **exit 4** (not attached) or **exit 7** (timeout). Exit 3 is emitted only by `attach` resolving a named target; exit 6 only by `doctor` / `attach` at the precondition gate. `list-apps` emits 0/2 only.

## Envelope fields the agent reads after exit 0

FROZEN envelope, present unless `--no-meta`:

| Field | Type | Use |
| --- | --- | --- |
| `schemaVersion` | string (semver) | In every payload; mismatch is exit 8, not a field check. |
| `sessionId` | string | Wire form of node-id `sessionEpoch`; a changed value means a re-attach happened (held ids are stale). |
| `_meta` | object | List/stream only: `{returned, truncated, totalMatched}`. `truncated` is the **only** "more exist" flag. |

Read **empty-vs-error from `_meta.totalMatched`, never from the exit code.** Error responses (`ok:false`) carry `v`/`id`/`schemaVersion` + `error` but **not** `sessionId`/`_meta`.

## Failure-signature table

| Signature | Exit | Cause | Remedy |
| --- | --- | --- | --- |
| Precondition unmet | 6 | A link in the injection stack failed (`doctor` check `sip`/`amfi`/`libval`/`arm64e-abi`/`arch`/`flexmac-built` fails). Any one failing → "dylib didn't load". | Report the failing check id + its `remedy` string. Do not touch SIP/AMFI yourself. |
| arm64e mismatch | 6 | Dylib built plain-arm64, not arm64e → **dyld fails silently** ("missing compatible architecture"). Surfaced by `doctor` `arch` = `arm64` (a precondition check). | "Rebuild FLEX-mac arm64e." Do not retry attach until arch is shown to match. |
| AMFI / LV still on | 6 | `doctor` `amfi`/`libval` check fails — AMFI enforcing or library validation on (code-directory-hash rejection, distinct from arch). | Confirm AMFI disabled (`amfi_get_out_of_my_way=0x1`, the real gate) and library validation off; the dylib is signed. |
| Zero frames | 0 | Geometry read returns `{0,0,0,0}` — target not frontmost / off-screen, not an error. | Bring the target on-screen and retry; do not re-issue the identical query unchanged. |
| Stale node | 5 | `STALE_NODE`: structural path recycled, pointer invalid, or recorded class no longer matches. Distinct from an occluded target. | Re-walk with `find`/`tree` for a fresh id. Never re-deref the recycled id. |
| Zero matches | 0 | Valid selector matched nothing (`_meta.totalMatched: 0`). Not a tool failure, distinct from exit-2 bad selector. | Broaden the predicate (or drill a SwiftUI boundary). Do not re-issue the same selector. |
| Not running | 3 | Named target not launched (attach-time). | Launch the target, then retry. |
| Handshake / schema | 7 / 8 | 7 = socket/`MAIN_THREAD_TIMEOUT`; 8 = `schemaVersion`/`v` desync between separately-built CLI and dylib. | 7: confirm session live, retry once. 8: rebuild CLI + dylib to one schema. |
| SwiftUI boundary | 0 | Node has `swiftUIBoundary: true` (`NSHostingView`); class names below it are SwiftUI internals. | Trust `font`/`frame`/`fill` below it; **do not assert hand-written AppKit classes** below the boundary. |

The arm64e-mismatch failure mode is **silent**: a plain-arm64 dylib produces no loud error, only an attach that didn't take. Treat any exit 4 with "missing compatible architecture" as arch, not AMFI/LV.

## ❌ Don't / ✅ Do

❌ Re-dereference a stale node id (exit 5) by re-issuing the read against the same id.
✅ Re-walk the path with `find`/`tree` to mint a fresh id; the breadcrumb (`tr3`→`tr4`) is often guessable, but validate before deref.

❌ Treat exit 0 + `totalMatched: 0` as a tool failure and re-issue the identical selector.
✅ Read the empty result from `_meta`, recognize it as valid, and **broaden** the selector (or drill a SwiftUI boundary).

❌ Conflate exit 2 (malformed selector) with exit 0 zero-match — they need opposite fixes.
✅ Branch on the exit code first: 2 → fix syntax; 0 → read `_meta` and broaden.

❌ Retry an exit-4 attach blindly, or change SIP/AMFI on an exit 6, autonomously.
✅ Split exit 4 by `error` (arch vs LV) and rebuild/fix; on exit 6 surface the `doctor` check + remedy and stop.

## One worked branch (shell + agent logic)

```bash
flexscope find com.apple.mail --where "class ~ 'NSTableView'" --count-only
code=$?
case $code in
  0) # success — but a match-count verb still needs _meta, not the code
     total=$(jq '._meta.totalMatched' out.json)   # 0 here means BROADEN, not fail
     if [ "$total" -eq 0 ]; then echo "0 matches: broaden the selector"; fi ;;
  2) echo "usage/bad selector: fix the predicate syntax" ;;
  3) echo "not running: launch Mail, then retry" ;;            # attach-time only
  4) echo "not attached: inspect error.code — arch mismatch vs AMFI/LV — re-attach" ;;
  5) echo "stale node: re-walk with find/tree for a fresh id" ;;
  6) echo "precondition: run flexscope doctor; report failing check + remedy" ;; # attach-time only
  7) echo "timeout/socket: confirm session live, retry once" ;;
  8) echo "schema mismatch: rebuild CLI and FLEX-mac to one schemaVersion" ;;
esac
```

BAD foil — branching on stdout text instead of the frozen exit code:

```bash
# ❌ brittle: prose is not the contract; a 0-match here is exit 0, not "no results" error
flexscope find com.apple.mail --where "…" | grep -q "no results" && retry_same_selector
```

Exit-code defaults and IPC op-name strings (e.g. the single-node read op behind `ax-diff`) are **unspecified / [NEEDS CLARIFICATION]** in the frozen spec — do not invent them; see `--help` / the schema verb.

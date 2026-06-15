# Exit Codes & Failure Signatures

Branch on `uitool`'s exit code; recognize each characteristic failure signature and report its one-line remedy instead of retrying a call that cannot succeed.

`uitool <verb> <app> [flags]` — JSON on stdout, diagnostic JSON on stderr. The agent branches on the exit code **without parsing prose**, then reads the envelope (`_meta`, `error.recover`) to refine. The authoritative table is `uitool schema`.

## Exit-code table (the control channel)

| Exit | Meaning | Agent branch |
| --- | --- | --- |
| 0 | ok | Read result. **0 matches is still exit 0** — read `_meta.totalMatched`, do not treat as failure. |
| 2 | usage / `BAD_SELECTOR` / `UNKNOWN_FIELD` / `BAD_PREDICATE` | Fix the selector, `--fields` path, or predicate. Distinct from a 0-match. |
| 3 | `APP_NOT_RUNNING` / `APP_NOT_FOUND` | The named target isn't running (or can't be resolved). Launch it / fix the id, then retry. |
| 4 | `NOT_ATTACHED` / injection failed | A query verb with no live session, or injection failed (socket never opened, mach-port failure, target died). Re-`attach`/`launch`; don't re-issue the query verb. |
| 5 | `STALE_NODE` | The held node id no longer resolves. **Re-walk** with `find`/`tree` for a fresh id — never re-deref the same id. |
| 6 | precondition failed | The posture you need isn't usable. Run `doctor`; report the failing check + its `remedy`. Don't change SIP/AMFI autonomously. |
| 7 | `TIMEOUT` | The ≈500 ms main-thread hop (or a socket) timed out. Confirm the session is live and the target idle; retry once. |
| 8 | schema-version mismatch | CLI and the injected dylib desynced (`schemaVersion`). Rebuild so both agree (`mise run uitool-sign`). |

In practice `doctor` is the verb that emits 6 (the precondition gate) and `attach`/`launch` resolve 3; a query verb against an unreachable session surfaces as **4** (not attached) or **7** (timeout), not 3/6. Read empty-vs-error from `_meta.totalMatched`, never from the exit code.

## Envelope fields the agent reads after exit 0

Present unless `--no-meta`:

| Field | Type | Use |
| --- | --- | --- |
| `schemaVersion` | string (semver) | On post-attach payloads; a mismatch is exit 8, not a field check. |
| `sessionId` | string | A changed value means a re-attach happened — any held node ids are stale. |
| `_meta` | object | Stream verbs only: `{returned, truncated, totalMatched}`. `truncated` is the only "more exist" flag. |

Error responses (`ok:false`) carry `schemaVersion` + the `error` object, but **not** `sessionId`/`_meta`.

## Failure-signature table

| Signature | Exit | Cause | Remedy |
| --- | --- | --- | --- |
| Precondition unmet | 6 | The posture you need isn't usable. Cooperative needs `arch` + `injectable-arm64`; unrestricted additionally needs `sip`/`amfi`/`libval`/`arm64e-abi`/`injectable-arm64e`. | Run `doctor`; report the failing check id + its `remedy`. Don't touch SIP/AMFI yourself. |
| Not cooperatively injectable | 4/6 | Target has no `get-task-allow` (you didn't sign it). Cooperative can't reach it. | `uitool signing <target>` — if `cooperativeInjectable:false`, it's an unrestricted-posture target, not a bug. |
| Injection failed | 4 | Session never opened (socket, mach-port, target died), or `attach` without the debugger entitlement. | Re-sign (`mise run uitool-sign`), confirm the target is alive + `get-task-allow`, retry. Read `error` for the specific cause. |
| arm64/arm64e mismatch | 4/6 | Cooperative wants an **arm64** injectable to match a normal Xcode arm64 app; the unrestricted posture wants **arm64e** to match the system dyld cache. A mismatched dylib fails dyld **silently**. | Build the injectable for the posture's arch; `doctor` shows which `injectable-*` is present. |
| Stale node | 5 | `STALE_NODE`: structural path recycled, pointer invalid, or recorded class no longer matches. | Re-walk with `find`/`tree` for a fresh id. Never re-deref the recycled id. |
| Zero matches | 0 | Valid selector matched nothing (`_meta.totalMatched: 0`). Not a tool failure; distinct from exit-2 bad selector. | Broaden the predicate (or drill a SwiftUI boundary). Don't re-issue the same selector. |
| Zero frames | 0 | Geometry reads `{0,0,0,0}` — target not frontmost / off-screen, not an error. | Bring the target on-screen and retry. |
| Not running / not found | 3 | Named target not launched, or the id can't be resolved. | Launch the target / fix the id, then retry. |
| Timeout | 7 | `TIMEOUT`: the main-thread hop (≈500 ms) or socket timed out — often a busy or modal target. | Confirm the session is live and the target idle (dismiss modals); retry once. |
| Schema desync | 8 | `schemaVersion` mismatch between CLI and the injected dylib. | Rebuild both to one schema (`mise run uitool-sign`). |
| SwiftUI boundary | 0 | Node has `swiftUIBoundary: true` (`NSHostingView`); class names below it are SwiftUI internals. | Trust `font`/`frame`/`fill` below it; **do not assert hand-written AppKit classes** below the boundary. |

## ❌ Don't / ✅ Do

❌ Re-dereference a stale node id (exit 5) by re-issuing the read against the same id.
✅ Re-walk the path with `find`/`tree` to mint a fresh id; validate before deref.

❌ Treat exit 0 + `totalMatched: 0` as a tool failure and re-issue the identical selector.
✅ Read the empty result from `_meta`, recognize it as valid, and **broaden** the selector.

❌ Conflate exit 2 (malformed selector) with exit 0 zero-match — they need opposite fixes.
✅ Branch on the exit code first: 2 → fix syntax; 0 → read `_meta` and broaden.

❌ Change SIP/AMFI on an exit 6, or blindly retry an exit-4, autonomously.
✅ On 6, surface the `doctor` check + remedy and stop for that posture; on 4, read `error` (entitlement vs target-died) and re-attach.

## One worked branch (shell + agent logic)

```bash
uitool find com.example.MailClone --where "class ~ 'NSTableView'" --count-only
code=$?
case $code in
  0) total=$(jq '._meta.totalMatched' out.json)              # 0 here means BROADEN, not fail
     [ "$total" -eq 0 ] && echo "0 matches: broaden the selector" ;;
  2) echo "usage/bad selector: fix the predicate or --fields path" ;;
  3) echo "not running/found: launch the target, then retry" ;;
  4) echo "not attached / injection failed: re-attach; read error for entitlement vs target-died" ;;
  5) echo "stale node: re-walk with find/tree for a fresh id" ;;
  6) echo "precondition: run uitool doctor; report failing check + remedy, stop" ;;
  7) echo "timeout: confirm session live + target idle, retry once" ;;
  8) echo "schema mismatch: rebuild CLI + dylib to one schema (mise run uitool-sign)" ;;
esac
```

❌ Brittle foil — branching on stdout text instead of the exit code:

```bash
uitool find com.example.MailClone --where "…" | grep -q "no results" && retry_same_selector
# prose is not the contract; a 0-match here is exit 0, not a "no results" error
```

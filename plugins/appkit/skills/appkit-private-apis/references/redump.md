# redump — find a symbol / import / string in a dead binary

Where `headerdump` recovers an Objective-C *header*, `redump` answers "what's actually *in* this Mach-O?" — symbols, imports, exports, strings, segments. Both are **static** (they read the binary, no injection), so neither needs SIP/AMFI changes. `redump` is the tool a private-API researcher reaches for to confirm a C entry point exists, find which dylib provides an import, or surface a telling string before declaring an interface.

It ships in the `apple-platform-tools` monorepo and installs with the other static tools (`mise run install` → `~/.local/bin`). Unlike `headerdump`, it is a modern `ArgumentParser` CLI over the AgentCLI machine contract: deterministic JSON on stdout, diagnostics on stderr, exit code as the control channel. Every verb takes a `<binary>` path (thin or universal) and reads it natively — **no disassembler** is involved in any of these reads.

## Verbs

| Verb | Purpose | Key flags |
|------|---------|-----------|
| `info` | file type + architectures | — |
| `segments` | segment name + virtual-address range | — |
| `symbols` | symbol-table entries | `--filter <regex>` (NSRegularExpression, kept against each name) · `--type function\|data\|all` (default `all`) |
| `imports` | undefined imports + their source dylibs | `--library <substr>` (keep imports from a library whose path contains this) |
| `exports` | export-trie symbols | — |
| `strings` | C strings from `__TEXT,__cstring` | `--min-length <n>` (default 4) · `--filter <regex>` |
| `backends` | which disassembler backends (IDA Pro / Hopper) are configured | — |

```bash
# Does this framework export the symbol I found in a header dump?
redump exports /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit | grep -i titlebar

# What C functions matching a pattern does it define?
redump symbols ./MyApp.app/Contents/MacOS/MyApp --type function --filter '(?i)private'

# Which dylib provides an import?
redump imports ./MyApp.app/Contents/MacOS/MyApp --library CoreUI

# Telling strings (URLs, defaults keys, selector fragments)
redump strings ./MyApp.app/Contents/MacOS/MyApp --min-length 6 --filter 'experimental|FeatureFlag'
```

## Disassembly is gated / not shipped

`redump backends` reports whether an IDA Pro / Hopper backend is configured, but the **disassembly itself is a deferred, gated slice** — there is no shipped `disassemble` verb. Don't promise function decompilation; `redump` today is native Mach-O *reads* (symbols/imports/exports/strings/segments/info). For control-flow analysis the agent still needs a real disassembler outside this tool.

## Exit semantics

Standard AgentCLI contract: `0` ok, `2` usage error (bad flag / unreadable path), and a **zero-match filter is still `0`** (an empty result array, not a failure) — read the result, don't treat "no matches" as an error or re-run the identical query. Branch on the exit code, never on parsed prose.

## redump vs headerdump

| Question | Tool |
|----------|------|
| "Recover the ObjC `@interface` (class/method/property/ivar)" | `headerdump` |
| "Does this binary export / import / contain symbol X?" | `redump symbols` / `imports` / `exports` |
| "What strings / defaults keys does it embed?" | `redump strings` |
| "What segments / architectures does it have?" | `redump segments` / `info` |

Both are static, need no SIP, and pair with the runtime inspector (`appkit-app-inspector` / `uitool`) only when a *running* app's live state is the question.

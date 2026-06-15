<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# redump contract

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


## Source: `Features/redump/0001-binary-info/commands/redump.info.md`

---
id: command.redump.info
kind: command
depends-on: [domain.macho-image]
---

# `redump info <binary>`

Native binary metadata read straight from the Mach-O via MachOKit — no disassembler.

## Invocation

```
redump info <binary>
```

`<binary>` is a path to a thin or universal Mach-O.

## Output

A single JSON object on stdout (deterministic, sorted keys, via `AgentCLI`):

```json
{
  "path": "<binary>",
  "archs": ["arm64", "x86_64"],
  "fileType": "dylib",
  "bitness": 64
}
```

- `archs` — every Mach-O slice's architecture name (`arm64`, `arm64_32`, `arm`, `x86_64`, `i386`, `ppc`, `ppc64`, else the raw case), in file order. One entry for a thin binary; several for a universal one.
- `fileType` — the Mach-O filetype of the first slice: `object`, `execute`, `dylib`, `bundle`, `dylinker`, `dylib-stub`, `dsym`, `kext`, `core`, `preload`, `fileset`, `fvmlib`, else the raw case.
- `bitness` — `64` for `arm64`/`x86_64`/`ppc64`, else `32`, from the first slice.

## Exit codes

- `0` — info emitted.
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `info` also returns `entry`, `minAddress`, and `maxAddress`, which it derives from IDA/Hopper analysis. Those require the disassembler backend and are **not** part of the native reader. `redump info` deliberately departs from the per-tool `AgentError` exit-code map for now: a failure surfaces as ArgumentParser's generic non-zero exit, which is sufficient for a single-error command. [NEEDS CLARIFICATION: adopt `AgentError` exit codes once redump grows commands with distinct failure modes?]


## Source: `Features/redump/0001-binary-info/commands/redump.segments.md`

---
id: command.redump.segments
kind: command
depends-on: [domain.macho-image]
---

# `redump segments <binary>`

The Mach-O's segments, read straight from their load commands via MachOKit — no disassembler.

## Invocation

```
redump segments <binary>
```

`<binary>` is a path to a thin or universal Mach-O. Segments are read from the **first slice** (the primary one); a universal binary reports the first architecture's segments.

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one entry per segment in **load order**:

```json
[
  { "name": "__TEXT", "start": "0x100000000", "end": "0x100004000" },
  { "name": "__DATA", "start": "0x100004000", "end": "0x100008000" }
]
```

- `name` — the segment name (`__TEXT`, `__DATA`, `__LINKEDIT`, `__PAGEZERO`, …).
- `start` — the segment's unslid virtual address (`vmaddr`), hex-encoded with a `0x` prefix.
- `end` — `vmaddr + vmsize`, hex-encoded with a `0x` prefix.

## Exit codes

- `0` — segments emitted (the array may be empty for a segment-less object file).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `segments` carries an optional `type` field (a segment classification derived from IDA/Hopper analysis). The native reader has no clean source for it, so `type` is **omitted** rather than guessed. Like `redump info`, a failure surfaces as ArgumentParser's generic non-zero exit rather than a per-tool `AgentError` code. [NEEDS CLARIFICATION: surface `type` once the disassembler backend lands, and adopt `AgentError` exit codes once redump grows commands with distinct failure modes?]


## Source: `Features/redump/0001-binary-info/commands/redump.symbols.md`

---
id: command.redump.symbols
kind: command
depends-on: [domain.macho-image]
---

# `redump symbols <binary>`

Symbol-table entries read straight from the Mach-O via MachOKit — no disassembler.

## Invocation

```
redump symbols <binary> [--filter <regex>] [--type function|data|all]
```

- `<binary>` is a path to a thin or universal Mach-O. Symbols come from the **primary (first) slice**.
- `--filter <regex>` keeps only symbols whose `name` matches the regular expression (`NSRegularExpression`, matched anywhere in the name).
- `--type` narrows by classification: `function`, `data`, or `all` (the default).

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per symbol in symbol-table order:

```json
[
  { "address": "0x3f1c", "name": "_$s5Probe0aB0V4pingyyF", "type": "function" },
  { "address": "0x8000", "name": "_$s5Probe0aB0VN", "type": "data" },
  { "address": "0x0", "name": "_objc_msgSend" }
]
```

- `address` — the symbol's value (`n_value`), hex-encoded with a `0x` prefix.
- `name` — the raw symbol name from the string table (mangled; not demangled).
- `type` — best-effort classification: `function` when the symbol is defined in a code section, `data` when defined in some other section. **Omitted** when the symbol has no defining section (undefined / absolute symbols), which the native reader cannot classify.

## Classification

`type` is derived from the symbol's defining section, not from disassembly:

- A symbol whose `nlist` type is `N_SECT` and whose section carries instruction attributes (`S_ATTR_PURE_INSTRUCTIONS` / `S_ATTR_SOME_INSTRUCTIONS`), or is `__TEXT,__text`, is a **function**.
- A symbol defined in any other section is **data**.
- A symbol with no defining section (`N_UNDF`, `N_ABS`) has **no `type`**.

`--type all` (the default) never depends on this classification, so it always works. `--type function` and `--type data` partition the section-defined symbols; undefined/absolute symbols (no `type`) fall under `data`.

## Exit codes

- `0` — symbols emitted.
- non-zero — the path is not a readable Mach-O, or `--filter`/`--type` is invalid; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `symbols` derives `function`/`data` from IDA/Hopper analysis. The native reader classifies from the symbol's Mach-O section instead — exact for section-defined symbols, but it cannot label undefined/absolute symbols, so those omit `type`. Names are emitted raw (mangled); demangling is out of scope for the native reader.


## Source: `Features/redump/0001-binary-info/commands/redump.imports.md`

---
id: command.redump.imports
kind: command
depends-on: [domain.macho-image]
---

# `redump imports <binary> [--library <name>]`

Imported (undefined) symbols and the dynamic libraries a Mach-O links, read straight from the Mach-O symbol table and load commands via MachOKit — no disassembler.

## Invocation

```
redump imports <binary> [--library <name>]
```

`<binary>` is a path to a thin or universal Mach-O. Imports are read from the **primary slice** (the first slice in file order).

`--library <name>` keeps only imports whose resolved source dylib path **contains** `<name>` as a substring; imports with no resolved library are dropped from a filtered run.

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per imported symbol, in symbol-table order:

```json
[
  { "library": "/usr/lib/libobjc.A.dylib", "name": "_objc_msgSend" },
  { "library": "/usr/lib/swift/libswiftCore.dylib", "name": "_swift_retain" },
  { "name": "_flat_namespace_symbol" }
]
```

- `name` — the imported symbol name exactly as the symbol table records it (leading underscore included). An imported symbol is one whose nlist type is `N_UNDF` (undefined — defined in no section of this image).
- `library` — the path of the dependent dylib the symbol is expected to come from, resolved from the symbol's two-level-namespace library ordinal against the image's `LC_LOAD_DYLIB` (and friends) list. **Omitted** when the ordinal does not name a specific dependency: `SELF_LIBRARY_ORDINAL`, `EXECUTABLE_ORDINAL`, `DYNAMIC_LOOKUP_ORDINAL` (flat-namespace / `-undefined dynamic_lookup`), or an out-of-range ordinal.

## Exit codes

- `0` — imports emitted (an empty array if the binary imports nothing, or if `--library` matched nothing).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli derives imports from disassembler analysis. `redump imports` reads the Mach-O symbol table and dependent-dylib load commands directly, so it ships in the native half with no licensed tooling.

Per-symbol library resolution depends on the two-level-namespace library ordinal carried in each undefined symbol's nlist description. For ordinary two-level-namespace binaries (the common case on Apple platforms) this resolves each import to a specific dependent dylib. For flat-namespace symbols, self / executable references, and out-of-range ordinals, the source dylib is not determinable from the symbol table alone, so `library` is omitted and only the symbol `name` is reported. The dependent dylibs themselves are always available via the load commands; a future `redump dylibs` slice could surface that list independently.


## Source: `Features/redump/0001-binary-info/commands/redump.exports.md`

---
id: command.redump.exports
kind: command
depends-on: [domain.macho-image]
---

# `redump exports <binary>`

Exported symbols read straight from the Mach-O export trie via MachOKit — no disassembler.

## Invocation

```
redump exports <binary>
```

`<binary>` is a path to a thin or universal Mach-O. Exports are read from the **primary slice** (the first slice in file order).

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per exported symbol, in export-trie order:

```json
[
  { "address": "0x3f40", "name": "_$s5Probe05probeA15ExportedFunctionyyF" },
  { "name": "_$s5ProbeAAVMn" }
]
```

- `name` — the exported symbol name exactly as the trie records it (leading underscore included).
- `address` — the symbol's offset from the start of the file, as a `0x`-prefixed hex string. **Omitted** when the trie carries no offset for the symbol (re-exports, absolute symbols).

## Exit codes

- `0` — exports emitted (an empty array if the binary exports nothing).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli derives exports from disassembler analysis. `redump exports` reads the Mach-O export trie directly, so it ships in the native half with no licensed tooling. It reports the symbol's file **offset** as `address`; the trie does not carry a runtime VM address, so no IDA/Hopper-style absolute address is synthesized.


## Source: `Features/redump/0001-binary-info/commands/redump.strings.md`

---
id: command.redump.strings
kind: command
depends-on: [domain.macho-image]
---

# `redump strings <binary>`

C strings read straight from the Mach-O's `__TEXT,__cstring` section via MachOKit — no disassembler.

## Invocation

```
redump strings <binary> [--min-length <n>] [--filter <regex>]
```

`<binary>` is a path to a thin or universal Mach-O. Strings are read from the **primary slice** (the first slice in file order).

- `--min-length <n>` — drop strings shorter than `n` characters. Default `4`.
- `--filter <regex>` — keep only strings whose value matches the regular expression.

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per C string, in section order:

```json
[
  { "address": "0x100003f40", "value": "REDUMP_MARKER_STRING" },
  { "address": "0x100003f55", "value": "%s: %d\n" }
]
```

- `value` — the NUL-terminated C string, decoded as UTF-8. MachOKit walks the section and splits it on NUL; each entry carries its offset within the section.
- `address` — the string's unslid virtual address: the `__TEXT,__cstring` section's `vmaddr` plus the string's offset within the section, as a `0x`-prefixed hex string.

A slice with no `__TEXT,__cstring` section yields an empty array.

## Exit codes

- `0` — strings emitted (an empty array if the binary has no `__TEXT,__cstring` section, or none survive the filters).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `strings` enumerates strings discovered across the binary by disassembler analysis. `redump strings` reads the `__TEXT,__cstring` section directly, so it ships in the native half with no licensed tooling. `address` is the string's **virtual address** (section `vmaddr` + in-section offset), not a disassembler-resolved cross-reference. Only `__TEXT,__cstring` is read — UTF-16 (`__ustring`) and strings embedded in other sections are out of scope for the native reader.


## Source: `Features/redump/0002-disassembler/commands/redump.backends.md`

---
id: command.redump.backends
kind: command
---

# `redump backends`

Report which disassembler backends (IDA Pro / Hopper) are configured for redump's analysis commands. Native — needs no disassembler to run.

## Invocation

```
redump backends
```

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one entry per backend:

```json
[
  { "backend": "ida",    "configured": false, "path": null },
  { "backend": "hopper", "configured": true,  "path": "/Applications/Hopper.app/Contents/MacOS/hopper" }
]
```

- `backend` — `ida` or `hopper`.
- `configured` — whether the tool was located.
- `path` — the resolved tool path, or `null`.

## Resolution order

For each backend, redump checks (mirroring re-cli):

1. An environment override — `RE_IDAT64` (IDA's `idat64`) or `RE_HOPPER` (Hopper's executable).
2. Known install locations — `/Applications/IDA Pro/idabin/idat64`; the `Hopper Disassembler[ v4/v5].app` / `Hopper.app` bundles.

(re-cli additionally globs `/Applications` for versioned IDA installs and falls back to `which`; those effectful steps are out of scope for the pure resolver.)

## Exit codes

- `0` — statuses emitted.

## Relationship to the analysis commands

`functions`, `disasm`, `decompile`, and `xrefs` consume this detection: each resolves a backend and, when none is `configured`, fails with an actionable message. Their implementation (driving IDA/Hopper) is tools-gated and tracked separately — see `narrative.redump.disassembler`.


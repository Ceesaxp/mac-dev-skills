<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# headerdump contract

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.

## Source: `Features/headerdump/0001-dump-framework/commands/headerdump.dump.md`

---
id: command.headerdump.dump
kind: command
depends-on: []
---

# `headerdump` — dump a framework's private headers

<!--
  headerdump has a single, default behavior (there is no sub-verb): given an
  image, recover its ObjC and Swift declarations and write them as header FILES.
  Its output contract is deliberately *not* the AgentCLI JSON projection the
  other tools share — see "Output" below — so it does not depend on
  `domain.agent-cli`.
-->

## Synopsis

```
headerdump [options] <filename|framework>
headerdump [options] -r <sourcePath>
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<filename\|framework>` | path | yes (unless `-r`) | A Mach-O file, or a `.framework`/`.app`/`.bundle`/`.xpc`/`.appex` bundle resolved to its executable. |
| `<sourcePath>` (with `-r`) | path | yes (with `-r`) | A directory tree to walk; each bundle is resolved to its executable and dumped. |
| `-o <dir>` | path | no | Output directory. Default: the current working directory. |
| `-r` | flag | no | Recursive search: walk `<sourcePath>` and dump every supported image. |
| `-b` | flag | no | Rebuild the image's original directory tree under the output dir. |
| `-h` | flag | no | Add a `Headers/` folder under each bundle's rebuilt directory (only meaningful with `-b`). |
| `-s` | flag | no | Skip files that already exist in the output dir (don't overwrite). |
| `-j <name>` | string | no | Dump only the single class/protocol of that name (also matches a category by class or category name). |
| `-c` | flag | no | Resolve images from the dyld shared cache. Recommended for simulator runtimes and modern system frameworks. |
| `-D` | flag | no | Verbose diagnostics (to stderr). |
| `-R` | flag | no | Prefer Objective-C runtime metadata over static parsing. Auto-enabled inside a simulator runtime. |
| `--help` | flag | no | Print usage and exit 0. |

Unknown flags (anything starting with `-` that isn't listed above) are
**ignored** for forward/backward compatibility, not rejected. A leading
positional argument is the input path; if more than one positional is given, the
last one wins.

### Environment overrides

These tune the static-vs-runtime metadata strategy without new flags. Each is
also honored under a `SIMCTL_CHILD_` prefix so it survives `simctl spawn` into a
simulator. Truthy = `1` or `true`.

| Variable | Effect |
| --- | --- |
| `PH_RUNTIME_ONLY` | Skip all static ObjC parsing (classes, protocols, categories) and use the live runtime; implies runtime fallback. |
| `PH_SKIP_STATIC_CLASSES` | Skip the static class parse; use the runtime for classes. |
| `PH_SKIP_STATIC_PROTOCOLS` | Skip the static protocol parse. |
| `PH_SKIP_STATIC_CATEGORIES` | Skip the static category parse. |
| `PH_STATIC_TIMEOUT` | Wall-clock budget (seconds) for the static class parse before auto-falling back to the runtime. `<= 0` disables the watchdog. Default `10`. |
| `PH_RUNTIME_ROOT` / `DYLD_ROOT_PATH` | Rebase absolute image paths and shared-cache lookup onto a simulator runtime root. |

## Behavior

1. Parse arguments. A missing input path, or a missing value for `-o`/`-j`, is a
   usage error (see exit codes). `--help` prints usage and exits 0.
2. If not already forced by `-R`, enable runtime fallback automatically when a
   runtime root is present (i.e. running inside a simulator). Apply the
   `PH_*` env overrides.
3. Resolve the input: a bundle is resolved to its executable image; a plain file
   is used directly. With `-r`, walk the tree, skipping the descendants of each
   bundle once its executable is dumped.
4. Load the Mach-O image. With `-c`, prefer the dyld shared cache (trying
   versioned `Versions/{Current,A,B,C}` path variants and runtime-root–relative
   paths); otherwise load from the file and fall back to the cache on failure.
   Only `arm64`/`x86_64` slices are supported; a fat binary picks the first
   supported slice.
5. Recover Objective-C metadata: statically parse `__objc_*` classes, protocols,
   and categories (unless skipped), and — when runtime fallback is on, or the
   static class parse times out — merge in classes from the live Objective-C
   runtime. On a static-parse timeout, partial static class results are dropped
   and the runtime is treated as authoritative.
6. Recover Swift metadata: build a `<Module>.swiftinterface` from `__swift5_*`
   descriptors via the SwiftInterface builder.
7. Write the recovered declarations to the output directory (see Output).

## Output

**This tool's output is header _files_, not agent-JSON on stdout** — a
deliberate departure from the other tools' AgentCLI contract. It writes:

- one `.h` per Objective-C **class**, **protocol**, and **category** (a category
  filename is `<Class>+<Category>.h`), and
- one `<Module>.swiftinterface` per Swift module (an empty/whitespace-only
  interface is not written).

Files land directly in the output directory by default; with `-b` they are
placed under a rebuilt copy of the image's original directory tree, and `-h`
adds a `Headers/` folder for bundles. `-s` skips files that already exist.
stdout/stderr carry only diagnostics (more with `-D`), never the recovered API
itself.

> An agent-JSON query mode (e.g. emit one symbol's declaration as JSON on
> stdout, under the `AgentCLI` contract) is a possible future addition. It is
> out of scope here; today the deliverable is files on disk.

### Filename determinism

Header filenames are derived deterministically. Entries are sorted (by symbol
kind, then base name, then declaration text) before naming. A name longer than
255 UTF-8 bytes is truncated and given a stable FNV-1a hash suffix. A
case-insensitive filename collision (e.g. `Foo.h` vs `foo.h` on a
case-insensitive volume) is resolved by appending a stable hash suffix derived
from the entry's kind and base name — so the same image always produces the same
set of filenames.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | `0` | header files written to the output dir; diagnostics only on stdout/stderr |
| `--help` | `0` (`EXIT_SUCCESS`) | usage text |
| usage / parse error (no input path, or missing `-o`/`-j` value) | `EXIT_FAILURE` | usage text |
| dump error (e.g. recursive root directory not found) | `EXIT_FAILURE` | `headerdump: error: <error>` on stderr |

<!--
  EXIT_FAILURE is the platform's non-zero failure code (1 on Darwin). headerdump
  does not use the granular AgentCLI exit-code map (it predates and sits outside
  that contract), so only success/failure are distinguished today.
-->

## Invariants

- Writes only under the output directory; reads images from disk or the shared
  cache. It does not mutate the source images.
- Never exits 0 on a usage or dump error.
- Deterministic filenames: the same image and options produce the same set of
  output filenames (sorted entries; stable hash suffixes for truncation and
  case-insensitive collisions).
- An image that yields no recoverable metadata is not an error — it simply
  produces no (or fewer) files and still exits 0.

## Notes

- Cost is **expensive and unbounded** relative to the JSON tools: it parses
  whole Mach-O images and writes many files. The static class parse is
  watchdogged (`PH_STATIC_TIMEOUT`, default 10s) because it can be pathologically
  slow on large frameworks in modern dyld shared caches; the runtime path is a
  complete substitute for class metadata.
- For simulator runtimes, combine `-c` (read from the simulator's shared cache)
  with a `PH_RUNTIME_ROOT`/`DYLD_ROOT_PATH` pointing at the runtime root; `-R`
  is auto-enabled there.


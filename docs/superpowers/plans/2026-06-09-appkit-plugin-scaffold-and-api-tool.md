# AppKit Plugin Scaffold + `appkit-api` Tool — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `mac-dev-skills` Claude Code plugin (manifests, the 9 existing skills relocated into the plugin tree, an `appkit-dev` agent) and build the flagship `appkit-api` Swift CLI — an SDK API + availability validator that answers "does this symbol exist, and what macOS version does it need?" from `swift symbolgraph-extract` data.

**Architecture:** Two independent, individually-shippable increments. (A) Phase 0 is mechanical scaffolding: JSON manifests + verbatim copies of existing skill files from `resources/` (gitignored reference inputs) into `plugins/appkit/`. No skill *content* is edited, so the writing-skills Iron Law is not engaged. (B) Phase 1a is a SwiftPM package built TDD-first with **Swift Testing**: Codable models for the symbol graph → an in-memory index (symbols + `memberOf` relationships) → query functions (`check`/`members`/`availability`/`search`/`enums`) → an ArgumentParser CLI that extracts+caches symbol graphs on demand. Query logic is unit-tested against a small checked-in JSON fixture; live extraction is verified by one end-to-end manual step.

**Tech Stack:** Claude Code plugin manifests (JSON), Swift 6 + SwiftPM, swift-argument-parser, Swift Testing, `swift symbolgraph-extract`, `xcrun`.

---

## File Structure

**Phase 0 — created/modified:**
- `.claude-plugin/marketplace.json` — Claude Code marketplace manifest (lists the `appkit` plugin)
- `.codex-plugin/marketplace.json` — Codex variant of the same
- `plugins/appkit/plugin.json` — plugin manifest (name, version, skills/agents dirs, keywords)
- `plugins/appkit/.claude-plugin/plugin.json` — Claude-variant plugin manifest
- `plugins/appkit/agents/appkit-dev.agent.md` — orchestrator agent (new content)
- `plugins/appkit/skills/<9 skills>/SKILL.md` — verbatim copies from `resources/`
- `plugins/appkit/skills/appkit-dev-workflow/build-and-run.sh` — renamed copy of `builkd-and-run.sh`
- `plugins/appkit/skills/appkit-dev-workflow/templates/Project.swift` — copy of the Tuist template
- `plugins/appkit/skills/appkit-packaging/references/ci-and-app-store.md` — copy
- `plugins/appkit/skills/appkit-session-report/analyze-session.py` — copy (SKILL.md authored later)
- `README.md`, `CHANGELOG.md`, `LICENSE` — repo top-level

**Phase 1a — created:**
- `src/tools/appkit-api/Package.swift`
- `src/tools/appkit-api/Sources/AppKitAPICore/SymbolGraph.swift` — Codable models
- `src/tools/appkit-api/Sources/AppKitAPICore/SymbolIndex.swift` — index + queries
- `src/tools/appkit-api/Sources/AppKitAPICore/Extractor.swift` — SDK resolve + extract + cache
- `src/tools/appkit-api/Sources/AppKitAPICore/Output.swift` — Encodable output DTOs
- `src/tools/appkit-api/Sources/appkit-api/AppKitAPI.swift` — ArgumentParser CLI (`@main`)
- `src/tools/appkit-api/Tests/AppKitAPICoreTests/Fixtures.swift` — embedded JSON fixture
- `src/tools/appkit-api/Tests/AppKitAPICoreTests/ModelTests.swift`
- `src/tools/appkit-api/Tests/AppKitAPICoreTests/IndexTests.swift`
- `src/tools/appkit-api/Tests/AppKitAPICoreTests/ExtractorTests.swift`
- `src/tools/appkit-api/README.md`
- `scripts/build-tools.sh` — build + ad-hoc-sign + install the tool

**Out of scope for this plan (later phases):** `appkit-search`, the four NEW skills, `appkit-setup` wiring to build the tools (a skill content edit → its own TDD), polishing any existing skill content.

---

# PHASE 0 — Plugin scaffold

### Task 1: Plugin manifests

**Files:**
- Create: `plugins/appkit/plugin.json`
- Create: `plugins/appkit/.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.codex-plugin/marketplace.json`

- [ ] **Step 1: Write `plugins/appkit/plugin.json`**

```json
{
  "name": "appkit",
  "version": "0.1.0",
  "description": "Agents and skills for modern (macOS 26/27) native AppKit app development — build/run, design with Liquid Glass, code review, XCUITest, migration, modernization, packaging for TestFlight & the Mac App Store, plus grounded API/availability tooling.",
  "author": { "name": "Mark", "email": "mark@malstrom.me" },
  "agents": "agents/",
  "skills": ["skills/"],
  "category": "macos-development",
  "keywords": [
    "macos", "appkit", "cocoa", "swift", "swift6", "xcode", "tuist",
    "liquid-glass", "nsglasseffectview", "concentricity", "hig",
    "xcuitest", "swift-testing", "notarization", "testflight",
    "mac-app-store", "developer-id", "codesign", "notarytool",
    "nsview", "nsviewcontroller", "nswindow", "nstableview", "nstoolbar",
    "migration", "catalyst", "objective-c", "accessibility"
  ]
}
```

- [ ] **Step 2: Write `plugins/appkit/.claude-plugin/plugin.json`**

Identical content to Step 1 (Claude Code reads the `.claude-plugin/plugin.json` variant). Copy the same JSON verbatim.

- [ ] **Step 3: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "mac-dev-skills",
  "owner": { "name": "Mark", "url": "https://github.com/malstrom/mac-dev-skills" },
  "version": "0.1.0",
  "plugins": [
    {
      "name": "appkit",
      "version": "0.1.0",
      "description": "Build, design, test, modernize, and ship native macOS AppKit apps (macOS 26/27).",
      "source": "./plugins/appkit",
      "category": "macos-development",
      "tags": ["macos", "appkit", "swift", "liquid-glass", "testflight", "mac-app-store"]
    }
  ]
}
```

- [ ] **Step 4: Write `.codex-plugin/marketplace.json`**

Same JSON as Step 3 (Codex parity). Copy verbatim.

- [ ] **Step 5: Validate JSON**

Run: `for f in plugins/appkit/plugin.json plugins/appkit/.claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/marketplace.json; do echo "$f:"; python3 -m json.tool "$f" >/dev/null && echo "  OK"; done`
Expected: four lines each ending `OK` (no JSON errors).

- [ ] **Step 6: Commit**

```bash
git add plugins/appkit/plugin.json plugins/appkit/.claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/marketplace.json
git commit -m "feat(plugin): add appkit plugin + marketplace manifests"
```

---

### Task 2: Relocate the 9 existing skills (verbatim copies)

**Files (create by copying — sources are under `resources/`, which is gitignored reference input):**
- Create: `plugins/appkit/skills/appkit-code-review/SKILL.md`
- Create: `plugins/appkit/skills/appkit-ui-testing/SKILL.md`
- Create: `plugins/appkit/skills/appkit-dev-workflow/SKILL.md`
- Create: `plugins/appkit/skills/appkit-setup/SKILL.md`
- Create: `plugins/appkit/skills/appkit-migration/SKILL.md`
- Create: `plugins/appkit/skills/appkit-launch-continuity/SKILL.md`
- Create: `plugins/appkit/skills/appkit-modern-input/SKILL.md`
- Create: `plugins/appkit/skills/appkit-liquid-glass-concentricity/SKILL.md`
- Create: `plugins/appkit/skills/appkit-packaging/SKILL.md`

- [ ] **Step 1: Copy the 5 claude-brainstorm skills**

```bash
SRC="resources/claude-brainstorm/mnt/user-data/outputs/appkit-dev-skills/plugins/appkit/skills"
DST="plugins/appkit/skills"
for s in appkit-code-review appkit-ui-testing appkit-dev-workflow appkit-setup appkit-migration; do
  mkdir -p "$DST/$s"
  cp "$SRC/$s/SKILL.md" "$DST/$s/SKILL.md"
done
```

- [ ] **Step 2: Copy the 3 modernize-appkit skills**

```bash
for s in appkit-launch-continuity appkit-modern-input appkit-liquid-glass-concentricity; do
  mkdir -p "plugins/appkit/skills/$s"
  cp "resources/modernize-appkit/$s/SKILL.md" "plugins/appkit/skills/$s/SKILL.md"
done
```

- [ ] **Step 3: Copy the packaging skill (currently the root SKILL.md of claude-brainstorm)**

```bash
mkdir -p plugins/appkit/skills/appkit-packaging
cp resources/claude-brainstorm/SKILL.md plugins/appkit/skills/appkit-packaging/SKILL.md
```

- [ ] **Step 4: Verify every SKILL.md has valid frontmatter (name + description)**

Run:
```bash
for f in plugins/appkit/skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' && grep -q '^name:' "$f" && grep -q '^description:' "$f" \
    && echo "OK  $f" || echo "BAD $f"
done
```
Expected: 9 lines, all starting `OK`. If any are `BAD`, open that file and confirm its YAML frontmatter block (`---` / `name:` / `description:` / `---`); do not edit prose, only fix a malformed frontmatter delimiter if present.

- [ ] **Step 5: Commit**

```bash
git add plugins/appkit/skills
git commit -m "feat(skills): relocate 9 existing AppKit skills into the plugin"
```

---

### Task 3: Relocate supporting assets (script rename, templates, references, session-report payload)

**Files:**
- Create: `plugins/appkit/skills/appkit-dev-workflow/build-and-run.sh` (renamed from `builkd-and-run.sh`)
- Create: `plugins/appkit/skills/appkit-dev-workflow/templates/Project.swift`
- Create: `plugins/appkit/skills/appkit-packaging/references/ci-and-app-store.md`
- Create: `plugins/appkit/skills/appkit-session-report/analyze-session.py`

- [ ] **Step 1: Copy + rename the build script (fixing the `builkd` typo) and the Tuist template**

```bash
cp resources/claude-brainstorm/builkd-and-run.sh plugins/appkit/skills/appkit-dev-workflow/build-and-run.sh
chmod +x plugins/appkit/skills/appkit-dev-workflow/build-and-run.sh
mkdir -p plugins/appkit/skills/appkit-dev-workflow/templates
cp resources/claude-brainstorm/Project.swift plugins/appkit/skills/appkit-dev-workflow/templates/Project.swift
```

- [ ] **Step 2: Copy the CI/App-Store reference into the packaging skill**

```bash
mkdir -p plugins/appkit/skills/appkit-packaging/references
cp resources/claude-brainstorm/ci-and-app-store.md plugins/appkit/skills/appkit-packaging/references/ci-and-app-store.md
```

- [ ] **Step 3: Copy the session-report analyzer payload**

```bash
mkdir -p plugins/appkit/skills/appkit-session-report
cp resources/claude-brainstorm/analyze-session.py plugins/appkit/skills/appkit-session-report/analyze-session.py
```

- [ ] **Step 4: Sanity-check the renamed script parses as shell**

Run: `bash -n plugins/appkit/skills/appkit-dev-workflow/build-and-run.sh && echo "shell OK"`
Expected: `shell OK` (syntax check only; does not execute it).

- [ ] **Step 5: Sanity-check the Python analyzer parses**

Run: `python3 -m py_compile plugins/appkit/skills/appkit-session-report/analyze-session.py && echo "py OK"`
Expected: `py OK`.

- [ ] **Step 6: Commit**

```bash
git add plugins/appkit/skills/appkit-dev-workflow plugins/appkit/skills/appkit-packaging plugins/appkit/skills/appkit-session-report
git commit -m "feat(skills): relocate build script, Tuist template, CI ref, session analyzer"
```

---

### Task 4: Author the `appkit-dev` agent

**Files:**
- Create: `plugins/appkit/agents/appkit-dev.agent.md`

- [ ] **Step 1: Write the agent file**

```markdown
---
name: appkit-dev
description: "Builds native macOS AppKit apps with Swift 6, Tuist, and the macOS 26/27 SDK. Use for creating new apps, adding features, designing UI with Liquid Glass, migrating from UIKit/Catalyst/Electron/Objective-C, fixing bugs, or any AppKit / Cocoa / Swift macOS-app task."
user-invocable: true
---

You build and ship native macOS AppKit applications end-to-end. You own the loop: requirements → design → scaffold → implement → build & run → test.

## Default skills
Before starting work, load **appkit-dev-workflow** (build/run inner loop) and **appkit-design** (UI/HIG/Liquid Glass correctness). Load other appkit skills as the task demands (migration, packaging, ui-testing, code-review, the modernization skills).

## Grounded tools — never guess
- Before using any API, verify it exists and its macOS availability with **`appkit-api`** (`appkit-api check NSGlassEffectView.effectIsInteractive`). Do not guess symbol names or `@available` versions.
- For canonical patterns ("how do I build X in AppKit"), query **`appkit-search`** before writing from scratch.
- If a tool binary is missing, build it: `scripts/build-tools.sh` (or tell the user to run it).

## Non-negotiables
- **Swift 6** language mode, strict concurrency. Respect `@MainActor` isolation; AppKit UI is main-actor.
- **Accessibility:** set an accessibility identifier on every interactive control. Not optional.
- **No hardcoded colors/fonts:** use semantic `NSColor`/`NSFont` and Dynamic System fonts; support light/dark/high-contrast.
- **Gate new APIs** behind `@available` / `if #available` when the deployment target is below the API's introduction (use `appkit-api availability <symbol>` to find it).

## Distribution awareness
Know the fork: **Mac App Store / TestFlight** require public APIs + App Sandbox; **Developer ID** (web/Sparkle) is the escape hatch. Private APIs, swizzling, and flexscope-derived techniques *may* fail App Store review (case-by-case) — inform the user of the trade-off and the Developer-ID alternative; never refuse to implement them.

## Efficiency
Batch file creates/edits in one pass. Don't re-read files you just wrote. Chain dependent shell commands with `&&`. Build and run before claiming done; report what actually passed.
```

- [ ] **Step 2: Validate frontmatter**

Run: `head -1 plugins/appkit/agents/appkit-dev.agent.md | grep -q '^---$' && grep -q '^name: appkit-dev$' plugins/appkit/agents/appkit-dev.agent.md && echo "agent OK"`
Expected: `agent OK`.

- [ ] **Step 3: Commit**

```bash
git add plugins/appkit/agents/appkit-dev.agent.md
git commit -m "feat(agent): add appkit-dev orchestrator agent"
```

---

### Task 5: Repo top-level docs (lean)

**Files:**
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `LICENSE`

- [ ] **Step 1: Write `README.md`**

```markdown
# mac-dev-skills

A Claude Code plugin for modern **macOS 26/27 AppKit** development — the macOS counterpart to Microsoft's `win-dev-skills`. Skills, an orchestrator agent, and grounded native Swift tooling that stops the agent guessing.

## Install
Add this marketplace, then install the `appkit` plugin:
- `/plugin marketplace add malstrom/mac-dev-skills`
- `/plugin install appkit`

## What's inside
- **13 skills** under `plugins/appkit/skills/` — setup, dev-workflow, design, code-review, ui-testing, packaging (TestFlight + Mac App Store), migration, three macOS-26/27 modernization skills, private-APIs, app-inspector, session-report.
- **`appkit-dev` agent** — builds AppKit apps end-to-end.
- **Native tools** in `src/tools/` — `appkit-api` (SDK API + availability validator) and `appkit-search` (AppKit/HIG pattern search). Build them with `scripts/build-tools.sh`.

## Building the tools
```bash
scripts/build-tools.sh
```
Requires Xcode 26 or 27 (the macOS SDK), Swift 6.

## Status
Active development. See `docs/superpowers/specs/` for the design and `docs/superpowers/plans/` for implementation plans.
```

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

## [Unreleased]
### Added
- `appkit` plugin scaffold: marketplace + plugin manifests.
- 9 relocated AppKit skills + `appkit-dev` agent.
- `appkit-api` tool: SDK API + availability validator (symbol-graph backed).
```

- [ ] **Step 3: Write `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Mark

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md LICENSE
git commit -m "docs: add README, CHANGELOG, LICENSE"
```

---

# PHASE 1a — `appkit-api` tool (TDD with Swift Testing)

### Task 6: SwiftPM package scaffold

**Files:**
- Create: `src/tools/appkit-api/Package.swift`
- Create: `src/tools/appkit-api/Sources/AppKitAPICore/Placeholder.swift`
- Create: `src/tools/appkit-api/Sources/appkit-api/AppKitAPI.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "appkit-api",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(name: "AppKitAPICore"),
        .executableTarget(
            name: "appkit-api",
            dependencies: [
                "AppKitAPICore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "AppKitAPICoreTests", dependencies: ["AppKitAPICore"])
    ]
)
```

- [ ] **Step 2: Write a temporary placeholder so the library target compiles**

`src/tools/appkit-api/Sources/AppKitAPICore/Placeholder.swift`:
```swift
// Temporary placeholder; replaced by real sources in later tasks.
enum AppKitAPICore {}
```

- [ ] **Step 3: Write a minimal CLI entry point so the executable compiles**

`src/tools/appkit-api/Sources/appkit-api/AppKitAPI.swift`:
```swift
import ArgumentParser

@main
struct AppKitAPI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appkit-api",
        abstract: "Query macOS SDK API existence and availability."
    )
    func run() throws {
        print("appkit-api: no subcommand. Try --help.")
    }
}
```

- [ ] **Step 4: Build to verify the package resolves**

Run: `cd src/tools/appkit-api && swift build 2>&1 | tail -5`
Expected: `Build complete!` (swift-argument-parser is fetched on first build).

- [ ] **Step 5: Commit**

```bash
git add src/tools/appkit-api/Package.swift src/tools/appkit-api/Sources
git commit -m "feat(appkit-api): SwiftPM package scaffold"
```

---

### Task 7: Symbol-graph Codable models

**Files:**
- Create: `src/tools/appkit-api/Tests/AppKitAPICoreTests/Fixtures.swift`
- Create: `src/tools/appkit-api/Tests/AppKitAPICoreTests/ModelTests.swift`
- Create: `src/tools/appkit-api/Sources/AppKitAPICore/SymbolGraph.swift`
- Delete: `src/tools/appkit-api/Sources/AppKitAPICore/Placeholder.swift`

- [ ] **Step 1: Write the test fixture (real symbol-graph shape, verified 2026-06-09)**

`Tests/AppKitAPICoreTests/Fixtures.swift`:
```swift
enum Fixtures {
    // Minimal AppKit symbol graph: a class, one of its properties, and a deprecated method.
    static let appKit = """
    {
      "metadata": { "formatVersion": { "major": 0, "minor": 6, "patch": 0 }, "generator": "test" },
      "module": { "name": "AppKit" },
      "symbols": [
        {
          "kind": { "identifier": "swift.class", "displayName": "Class" },
          "identifier": { "precise": "c:objc(cs)NSGlassEffectView", "interfaceLanguage": "swift" },
          "names": { "title": "NSGlassEffectView" },
          "pathComponents": ["NSGlassEffectView"],
          "declarationFragments": [
            { "kind": "keyword", "spelling": "class" },
            { "kind": "text", "spelling": " " },
            { "kind": "identifier", "spelling": "NSGlassEffectView" }
          ],
          "availability": [ { "domain": "macOS", "introduced": { "major": 26, "minor": 0 } } ]
        },
        {
          "kind": { "identifier": "swift.property", "displayName": "Instance Property" },
          "identifier": { "precise": "c:objc(cs)NSGlassEffectView(py)effectIsInteractive", "interfaceLanguage": "swift" },
          "names": { "title": "effectIsInteractive" },
          "pathComponents": ["NSGlassEffectView", "effectIsInteractive"],
          "declarationFragments": [
            { "kind": "keyword", "spelling": "var" },
            { "kind": "text", "spelling": " " },
            { "kind": "identifier", "spelling": "effectIsInteractive" },
            { "kind": "text", "spelling": ": " },
            { "kind": "typeIdentifier", "spelling": "Bool" }
          ],
          "availability": [ { "domain": "macOS", "introduced": { "major": 27, "minor": 0 } } ]
        },
        {
          "kind": { "identifier": "swift.method", "displayName": "Instance Method" },
          "identifier": { "precise": "c:objc(cs)NSCursor(im)showCenteredAt", "interfaceLanguage": "swift" },
          "names": { "title": "show(centeredAt:size:completionHandler:)" },
          "pathComponents": ["NSCursor", "show(centeredAt:size:completionHandler:)"],
          "declarationFragments": [
            { "kind": "keyword", "spelling": "func" },
            { "kind": "text", "spelling": " " },
            { "kind": "identifier", "spelling": "show" }
          ],
          "availability": [ {
            "domain": "macOS",
            "introduced": { "major": 10, "minor": 9 },
            "deprecated": { "major": 14, "minor": 0 },
            "message": "Use NSCursor.disappearingItemCursor instead"
          } ]
        }
      ],
      "relationships": [
        { "kind": "memberOf",
          "source": "c:objc(cs)NSGlassEffectView(py)effectIsInteractive",
          "target": "c:objc(cs)NSGlassEffectView" }
      ]
    }
    """
}
```

- [ ] **Step 2: Write the failing model test**

`Tests/AppKitAPICoreTests/ModelTests.swift`:
```swift
import Testing
import Foundation
@testable import AppKitAPICore

@Test func decodesSymbolGraph() throws {
    let data = Data(Fixtures.appKit.utf8)
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: data)
    #expect(graph.symbols.count == 3)
    #expect(graph.relationships.count == 1)

    let glass = try #require(graph.symbols.first { $0.names.title == "NSGlassEffectView" })
    #expect(glass.kind.identifier == "swift.class")
    #expect(glass.pathComponents == ["NSGlassEffectView"])
    #expect(glass.declaration == "class NSGlassEffectView")

    let prop = try #require(graph.symbols.first { $0.names.title == "effectIsInteractive" })
    let macos = try #require(prop.macOSAvailability)
    #expect(macos.introducedString == "27.0")

    let cursor = try #require(graph.symbols.first { $0.pathComponents.first == "NSCursor" })
    #expect(cursor.macOSAvailability?.deprecatedString == "14.0")
    #expect(cursor.macOSAvailability?.message == "Use NSCursor.disappearingItemCursor instead")
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd src/tools/appkit-api && swift test 2>&1 | tail -15`
Expected: FAIL — compilation error, `cannot find 'SymbolGraph' in scope`.

- [ ] **Step 4: Implement the models**

Delete the placeholder, then write `Sources/AppKitAPICore/SymbolGraph.swift`:
```swift
import Foundation

public struct SymbolGraph: Decodable, Sendable {
    public let symbols: [Symbol]
    public let relationships: [Relationship]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbols = try c.decodeIfPresent([Symbol].self, forKey: .symbols) ?? []
        relationships = try c.decodeIfPresent([Relationship].self, forKey: .relationships) ?? []
    }
    enum CodingKeys: String, CodingKey { case symbols, relationships }
}

public struct Symbol: Decodable, Sendable {
    public struct Names: Decodable, Sendable { public let title: String }
    public struct Kind: Decodable, Sendable { public let identifier: String }
    public struct Identifier: Decodable, Sendable { public let precise: String }
    public struct Fragment: Decodable, Sendable { public let spelling: String }

    public let names: Names
    public let kind: Kind
    public let identifier: Identifier
    public let pathComponents: [String]
    public let declarationFragments: [Fragment]?
    public let availability: [Availability]?

    /// The qualified name, e.g. "NSGlassEffectView.effectIsInteractive".
    public var qualifiedName: String { pathComponents.joined(separator: ".") }

    /// The reconstructed Swift declaration, e.g. "var effectIsInteractive: Bool".
    public var declaration: String {
        (declarationFragments ?? []).map(\.spelling).joined()
    }

    /// The macOS entry from the availability list, if any.
    public var macOSAvailability: Availability? {
        availability?.first { $0.domain == "macOS" }
    }
}

public struct Availability: Decodable, Sendable {
    public struct Version: Decodable, Sendable {
        public let major: Int
        public let minor: Int?
        public let patch: Int?
        public var string: String { "\(major).\(minor ?? 0)" }
    }
    public let domain: String?
    public let introduced: Version?
    public let deprecated: Version?
    public let obsoleted: Version?
    public let message: String?

    public var introducedString: String? { introduced?.string }
    public var deprecatedString: String? { deprecated?.string }
    public var obsoletedString: String? { obsoleted?.string }
}

public struct Relationship: Decodable, Sendable {
    public let kind: String
    public let source: String
    public let target: String
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd src/tools/appkit-api && swift test 2>&1 | tail -15`
Expected: PASS — `Test run with 1 test ... passed`.

- [ ] **Step 6: Commit**

```bash
git add src/tools/appkit-api/Sources/AppKitAPICore/SymbolGraph.swift src/tools/appkit-api/Tests
git rm --cached --ignore-unmatch src/tools/appkit-api/Sources/AppKitAPICore/Placeholder.swift
git add -A src/tools/appkit-api
git commit -m "feat(appkit-api): symbol-graph Codable models"
```

---

### Task 8: Symbol index (symbols + memberOf)

**Files:**
- Create: `src/tools/appkit-api/Tests/AppKitAPICoreTests/IndexTests.swift`
- Create: `src/tools/appkit-api/Sources/AppKitAPICore/SymbolIndex.swift`

- [ ] **Step 1: Write the failing index test**

`Tests/AppKitAPICoreTests/IndexTests.swift`:
```swift
import Testing
import Foundation
@testable import AppKitAPICore

private func makeIndex() throws -> SymbolIndex {
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: Data(Fixtures.appKit.utf8))
    return SymbolIndex(graphs: [graph])
}

@Test func indexBuildsAndLooksUpByQualifiedName() throws {
    let index = try makeIndex()
    #expect(index.symbolCount == 3)

    let hit = try #require(index.check("NSGlassEffectView.effectIsInteractive"))
    #expect(hit.kind.identifier == "swift.property")
    #expect(hit.macOSAvailability?.introducedString == "27.0")

    #expect(index.check("NSGlassEffectView.doesNotExist") == nil)
}

@Test func indexResolvesMembersOfAType() throws {
    let index = try makeIndex()
    let members = index.members(of: "NSGlassEffectView")
    #expect(members.map(\.names.title) == ["effectIsInteractive"])
}

@Test func indexSearchRanksExactPrefixFirst() throws {
    let index = try makeIndex()
    let results = index.search("glass", limit: 10)
    #expect(results.first?.names.title == "NSGlassEffectView")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src/tools/appkit-api && swift test --filter IndexTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'SymbolIndex' in scope`.

- [ ] **Step 3: Implement the index**

`Sources/AppKitAPICore/SymbolIndex.swift`:
```swift
import Foundation

public struct SymbolIndex: Sendable {
    private let all: [Symbol]
    private let byPrecise: [String: Symbol]
    private let byQualified: [String: [Symbol]]
    private let memberPreciseByContainer: [String: [String]]

    public var symbolCount: Int { all.count }

    public init(graphs: [SymbolGraph]) {
        var all: [Symbol] = []
        var byPrecise: [String: Symbol] = [:]
        var byQualified: [String: [Symbol]] = [:]
        var members: [String: [String]] = [:]

        for graph in graphs {
            for s in graph.symbols {
                all.append(s)
                byPrecise[s.identifier.precise] = s
                byQualified[s.qualifiedName, default: []].append(s)
            }
            for r in graph.relationships where r.kind == "memberOf" {
                members[r.target, default: []].append(r.source)
            }
        }
        self.all = all
        self.byPrecise = byPrecise
        self.byQualified = byQualified
        self.memberPreciseByContainer = members
    }

    /// Exact qualified-name lookup ("Type" or "Type.member"). Returns the first match.
    public func check(_ qualified: String) -> Symbol? {
        byQualified[qualified]?.first
    }

    /// All symbols whose qualified name or title contains `name`.
    public func availability(of name: String) -> [Symbol] {
        if let exact = byQualified[name] { return exact }
        let lower = name.lowercased()
        return all.filter {
            $0.qualifiedName.lowercased() == lower || $0.names.title.lowercased() == lower
        }
    }

    /// Members of a type, resolved via the `memberOf` relationship.
    public func members(of typeName: String) -> [Symbol] {
        guard let container = byQualified[typeName]?.first else { return [] }
        let ids = memberPreciseByContainer[container.identifier.precise] ?? []
        return ids.compactMap { byPrecise[$0] }
            .sorted { $0.names.title < $1.names.title }
    }

    /// Enum cases of an enum type (members whose kind is an enum case).
    public func enumCases(of typeName: String) -> [Symbol] {
        members(of: typeName).filter { $0.kind.identifier == "swift.enum.case" }
    }

    /// Fuzzy search over titles and qualified names: exact > prefix > contains.
    public func search(_ query: String, limit: Int) -> [Symbol] {
        let q = query.lowercased()
        func score(_ s: Symbol) -> Int? {
            let t = s.names.title.lowercased()
            let qn = s.qualifiedName.lowercased()
            if t == q { return 0 }
            if t.hasPrefix(q) { return 1 }
            if qn.hasPrefix(q) { return 2 }
            if t.contains(q) { return 3 }
            if qn.contains(q) { return 4 }
            return nil
        }
        return all
            .compactMap { s in score(s).map { (s, $0) } }
            .sorted { ($0.1, $0.0.names.title) < ($1.1, $1.0.names.title) }
            .prefix(limit)
            .map(\.0)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd src/tools/appkit-api && swift test --filter IndexTests 2>&1 | tail -15`
Expected: PASS — 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add src/tools/appkit-api/Sources/AppKitAPICore/SymbolIndex.swift src/tools/appkit-api/Tests/AppKitAPICoreTests/IndexTests.swift
git commit -m "feat(appkit-api): in-memory symbol index with member/search queries"
```

---

### Task 9: Encodable output DTOs + per-symbol projection

**Files:**
- Create: `src/tools/appkit-api/Tests/AppKitAPICoreTests/OutputTests.swift`
- Create: `src/tools/appkit-api/Sources/AppKitAPICore/Output.swift`

- [ ] **Step 1: Write the failing output test**

`Tests/AppKitAPICoreTests/OutputTests.swift`:
```swift
import Testing
import Foundation
@testable import AppKitAPICore

@Test func projectsSymbolToStableJSON() throws {
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: Data(Fixtures.appKit.utf8))
    let index = SymbolIndex(graphs: [graph])
    let sym = try #require(index.check("NSGlassEffectView.effectIsInteractive"))

    let out = SymbolOut(sym)
    #expect(out.name == "effectIsInteractive")
    #expect(out.qualified == "NSGlassEffectView.effectIsInteractive")
    #expect(out.kind == "swift.property")
    #expect(out.declaration == "var effectIsInteractive: Bool")
    #expect(out.availability?.introduced == "27.0")

    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let json = String(decoding: try enc.encode(out), as: UTF8.self)
    #expect(json.contains("\"introduced\":\"27.0\""))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src/tools/appkit-api && swift test --filter OutputTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'SymbolOut' in scope`.

- [ ] **Step 3: Implement the DTOs**

`Sources/AppKitAPICore/Output.swift`:
```swift
import Foundation

public struct AvailabilityOut: Encodable, Sendable {
    public let introduced: String?
    public let deprecated: String?
    public let obsoleted: String?
    public let message: String?

    public init?(_ a: Availability?) {
        guard let a else { return nil }
        introduced = a.introducedString
        deprecated = a.deprecatedString
        obsoleted = a.obsoletedString
        message = a.message
    }
}

public struct SymbolOut: Encodable, Sendable {
    public let name: String
    public let qualified: String
    public let kind: String
    public let declaration: String
    public let availability: AvailabilityOut?

    public init(_ s: Symbol) {
        name = s.names.title
        qualified = s.qualifiedName
        kind = s.kind.identifier
        declaration = s.declaration
        availability = AvailabilityOut(s.macOSAvailability)
    }
}

/// Encode any Encodable as pretty, key-sorted JSON for CLI output.
public func emitJSON<T: Encodable>(_ value: T) throws -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try enc.encode(value), as: UTF8.self)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd src/tools/appkit-api && swift test --filter OutputTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/tools/appkit-api/Sources/AppKitAPICore/Output.swift src/tools/appkit-api/Tests/AppKitAPICoreTests/OutputTests.swift
git commit -m "feat(appkit-api): JSON output DTOs"
```

---

### Task 10: Extractor — SDK resolution + cache-path logic

**Files:**
- Create: `src/tools/appkit-api/Tests/AppKitAPICoreTests/ExtractorTests.swift`
- Create: `src/tools/appkit-api/Sources/AppKitAPICore/Extractor.swift`

- [ ] **Step 1: Write the failing extractor test (pure logic only — no SDK calls)**

`Tests/AppKitAPICoreTests/ExtractorTests.swift`:
```swift
import Testing
import Foundation
@testable import AppKitAPICore

@Test func buildsTargetTriple() {
    #expect(Extractor.targetTriple(sdkVersion: "27.0") == "arm64-apple-macos27.0")
    #expect(Extractor.targetTriple(sdkVersion: "26.1") == "arm64-apple-macos26.1")
}

@Test func cacheDirIsKeyedBySDKVersionAndModule() {
    let dir = Extractor.cacheDir(sdkVersion: "27.0", module: "AppKit")
    #expect(dir.pathComponents.contains("appkit-api"))
    #expect(dir.pathComponents.contains("27.0"))
    #expect(dir.lastPathComponent == "AppKit")
}

@Test func extractArgsUseExplicitMacosSDK() {
    let args = Extractor.extractArguments(module: "AppKit", sdkPath: "/SDK", target: "arm64-apple-macos27.0", outputDir: "/out")
    #expect(args.contains("symbolgraph-extract"))
    #expect(args.contains("-module-name")); #expect(args.contains("AppKit"))
    #expect(args.contains("-sdk")); #expect(args.contains("/SDK"))
    #expect(args.contains("-target")); #expect(args.contains("arm64-apple-macos27.0"))
    #expect(args.contains("-minimum-access-level")); #expect(args.contains("public"))
    #expect(args.contains("-output-dir")); #expect(args.contains("/out"))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src/tools/appkit-api && swift test --filter ExtractorTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'Extractor' in scope`.

- [ ] **Step 3: Implement the extractor**

`Sources/AppKitAPICore/Extractor.swift`:
```swift
import Foundation

public struct Extractor: Sendable {
    public init() {}

    // ---- Pure helpers (unit-tested) ----

    public static func targetTriple(sdkVersion: String) -> String {
        "arm64-apple-macos\(sdkVersion)"
    }

    public static func cacheDir(sdkVersion: String, module: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/appkit-api", isDirectory: true)
            .appendingPathComponent(sdkVersion, isDirectory: true)
            .appendingPathComponent(module, isDirectory: true)
    }

    public static func extractArguments(module: String, sdkPath: String, target: String, outputDir: String) -> [String] {
        ["symbolgraph-extract",
         "-module-name", module,
         "-sdk", sdkPath,
         "-target", target,
         "-minimum-access-level", "public",
         "-output-dir", outputDir]
    }

    // ---- Live operations (exercised by the end-to-end step, not unit tests) ----

    public enum ExtractorError: Error, CustomStringConvertible {
        case command(String, Int32, String)
        case noGraphs(URL)
        public var description: String {
            switch self {
            case let .command(cmd, code, err): return "`\(cmd)` failed (exit \(code)): \(err)"
            case let .noGraphs(dir): return "no .symbols.json found in \(dir.path)"
            }
        }
    }

    public func sdkPath() throws -> String { try Self.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"]) }
    public func sdkVersion() throws -> String { try Self.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"]) }

    /// Ensure the symbol graphs for `module` are present in cache; extract if missing. Returns the cache dir.
    @discardableResult
    public func ensureExtracted(module: String) throws -> URL {
        let version = try sdkVersion()
        let dir = Self.cacheDir(sdkVersion: version, module: module)
        let primary = dir.appendingPathComponent("\(module).symbols.json")
        if FileManager.default.fileExists(atPath: primary.path) { return dir }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sdk = try sdkPath()
        let target = Self.targetTriple(sdkVersion: version)
        let args = Self.extractArguments(module: module, sdkPath: sdk, target: target, outputDir: dir.path)
        _ = try Self.run("/usr/bin/swift", args)
        guard FileManager.default.fileExists(atPath: primary.path) else { throw ExtractorError.noGraphs(dir) }
        return dir
    }

    /// Load all `<module>*.symbols.json` files in `dir` into decoded graphs.
    public func loadGraphs(in dir: URL, module: String) throws -> [SymbolGraph] {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(module) && $0.pathExtension == "json" }
        guard !files.isEmpty else { throw ExtractorError.noGraphs(dir) }
        let dec = JSONDecoder()
        return try files.map { try dec.decode(SymbolGraph.self, from: Data(contentsOf: $0)) }
    }

    /// Build a ready-to-query index for a module (extracting + caching as needed).
    public func index(module: String) throws -> SymbolIndex {
        let dir = try ensureExtracted(module: module)
        return SymbolIndex(graphs: try loadGraphs(in: dir, module: module))
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out; proc.standardError = err
        try proc.run(); proc.waitUntilExit()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if proc.terminationStatus != 0 {
            throw ExtractorError.command("\(launchPath) \(args.joined(separator: " "))",
                                         proc.terminationStatus,
                                         String(decoding: errData, as: UTF8.self))
        }
        return outStr
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd src/tools/appkit-api && swift test --filter ExtractorTests 2>&1 | tail -15`
Expected: PASS — 3 tests.

- [ ] **Step 5: Run the whole suite to confirm nothing regressed**

Run: `cd src/tools/appkit-api && swift test 2>&1 | tail -8`
Expected: all tests pass (models + index + output + extractor).

- [ ] **Step 6: Commit**

```bash
git add src/tools/appkit-api/Sources/AppKitAPICore/Extractor.swift src/tools/appkit-api/Tests/AppKitAPICoreTests/ExtractorTests.swift
git commit -m "feat(appkit-api): SDK-resolving symbol-graph extractor with caching"
```

---

### Task 11: CLI subcommands wiring

**Files:**
- Modify: `src/tools/appkit-api/Sources/appkit-api/AppKitAPI.swift` (replace the placeholder entry point)

- [ ] **Step 1: Replace the CLI with full subcommands**

`Sources/appkit-api/AppKitAPI.swift`:
```swift
import ArgumentParser
import Foundation
import AppKitAPICore

@main
struct AppKitAPI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appkit-api",
        abstract: "Query macOS SDK API existence and availability from symbol-graph data.",
        subcommands: [Check.self, Members.self, AvailabilityCmd.self, Search.self, Enums.self]
    )
}

struct ModuleOption: ParsableArguments {
    @Option(name: .long, help: "SDK module to query (default: AppKit).")
    var module: String = "AppKit"
}

private func loadIndex(_ module: String) throws -> SymbolIndex {
    do { return try Extractor().index(module: module) }
    catch { throw ValidationError("Failed to load \(module) symbol graph: \(error)") }
}

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check whether a symbol exists (e.g. NSGlassEffectView.effectIsInteractive).")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Qualified name: Type or Type.member.") var symbol: String

    func run() throws {
        let index = try loadIndex(opts.module)
        if let s = index.check(symbol) {
            struct R: Encodable { let query: String; let exists: Bool; let symbol: SymbolOut }
            print(try emitJSON(R(query: symbol, exists: true, symbol: SymbolOut(s))))
        } else {
            struct R: Encodable { let query: String; let exists: Bool }
            print(try emitJSON(R(query: symbol, exists: false)))
            throw ExitCode(1)
        }
    }
}

struct Members: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the members of a type.")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Type name, e.g. NSGlassEffectView.") var type: String

    func run() throws {
        let index = try loadIndex(opts.module)
        struct R: Encodable { let type: String; let members: [SymbolOut] }
        print(try emitJSON(R(type: type, members: index.members(of: type).map(SymbolOut.init))))
    }
}

struct AvailabilityCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "availability", abstract: "Show macOS availability for a symbol.")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Symbol name (title or qualified).") var symbol: String

    func run() throws {
        let index = try loadIndex(opts.module)
        struct R: Encodable { let symbol: String; let matches: [SymbolOut] }
        print(try emitJSON(R(symbol: symbol, matches: index.availability(of: symbol).map(SymbolOut.init))))
    }
}

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fuzzy-search symbols by name.")
    @OptionGroup var opts: ModuleOption
    @Option(name: .long, help: "Max results.") var limit: Int = 20
    @Argument(help: "Query.") var query: String

    func run() throws {
        let index = try loadIndex(opts.module)
        struct R: Encodable { let query: String; let results: [SymbolOut] }
        print(try emitJSON(R(query: query, results: index.search(query, limit: limit).map(SymbolOut.init))))
    }
}

struct Enums: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the cases of an enum type.")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Enum type name.") var type: String

    func run() throws {
        let index = try loadIndex(opts.module)
        struct R: Encodable { let type: String; let cases: [SymbolOut] }
        print(try emitJSON(R(type: type, cases: index.enumCases(of: type).map(SymbolOut.init))))
    }
}
```

- [ ] **Step 2: Build**

Run: `cd src/tools/appkit-api && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: End-to-end verification against the REAL AppKit SDK**

This is the live integration check (first run extracts ~31MB, ~30s; subsequent runs are cached).
Run:
```bash
cd src/tools/appkit-api
swift run appkit-api check NSGlassEffectView.effectIsInteractive
swift run appkit-api availability NSViewCornerConfiguration
swift run appkit-api members NSGlassEffectView
swift run appkit-api search glass --limit 5
```
Expected:
- `check` → JSON with `"exists":true` and `"introduced":"27.0"`.
- `availability` → a match with `"introduced":"27.0"`.
- `members` → includes `effectIsInteractive`, `style`, `tintColor`, `cornerRadius`, `contentView`.
- `search glass` → `NSGlassEffectView` ranked first.

- [ ] **Step 4: Commit**

```bash
git add src/tools/appkit-api/Sources/appkit-api/AppKitAPI.swift
git commit -m "feat(appkit-api): CLI subcommands (check/members/availability/search/enums)"
```

---

### Task 12: `build-tools.sh` + tool README

**Files:**
- Create: `scripts/build-tools.sh`
- Create: `src/tools/appkit-api/README.md`

- [ ] **Step 1: Write `scripts/build-tools.sh`**

```bash
#!/usr/bin/env bash
# Build the native AppKit dev tools, ad-hoc sign them, and install into the
# skill dirs that use them (and ~/.local/bin for direct use).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

build_tool() {
  local name="$1" dest_skill="$2"
  echo "==> Building $name"
  ( cd "$REPO_ROOT/src/tools/$name" && swift build -c release )
  local built="$REPO_ROOT/src/tools/$name/.build/release/$name"
  echo "==> Ad-hoc signing $name"
  codesign --force --sign - "$built"
  echo "==> Installing $name -> $BIN_DIR and $dest_skill"
  cp "$built" "$BIN_DIR/$name"
  if [ -n "$dest_skill" ]; then
    mkdir -p "$REPO_ROOT/$dest_skill"
    cp "$built" "$REPO_ROOT/$dest_skill/$name"
  fi
}

build_tool "appkit-api" "plugins/appkit/skills/appkit-design"
# appkit-search is added by a later plan.

echo "Done. Tools in $BIN_DIR (and copied into skill dirs)."
"$BIN_DIR/appkit-api" --help >/dev/null && echo "appkit-api: smoke OK"
```

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x scripts/build-tools.sh && scripts/build-tools.sh 2>&1 | tail -8`
Expected: ends with `appkit-api: smoke OK`. (`.build/` and the copied binary in the skill dir are gitignored per `.gitignore`.)

- [ ] **Step 3: Confirm the binary is gitignored (not accidentally committed)**

Run: `git check-ignore plugins/appkit/skills/appkit-design/appkit-api && echo "ignored OK"`
Expected: `ignored OK`.

- [ ] **Step 4: Write `src/tools/appkit-api/README.md`**

```markdown
# appkit-api

An SDK API + availability validator for macOS frameworks. Answers "does this
symbol exist, and what macOS version does it require?" from
`swift symbolgraph-extract` data — so an agent never guesses an API name or an
`@available` version.

## Build
```bash
swift build -c release        # or: scripts/build-tools.sh from the repo root
```

## Usage
```bash
appkit-api check NSGlassEffectView.effectIsInteractive   # exists? + availability
appkit-api availability NSViewCornerConfiguration        # min macOS / deprecation
appkit-api members NSGlassEffectView                      # members of a type
appkit-api search glass --limit 10                       # fuzzy name search
appkit-api enums NSGlassEffectView.Style                 # enum cases
appkit-api --module Foundation check NSString.length     # any SDK module
```

First query for a module extracts + caches its symbol graph under
`~/Library/Caches/appkit-api/<sdk-version>/<module>/` (~30s, ~31MB for AppKit);
later queries are instant. Cache invalidates automatically when the SDK version
changes. Requires the SDK to be resolvable via `xcrun --sdk macosx`.

## Tests
```bash
swift test     # Swift Testing; query logic runs against a checked-in fixture
```
```

- [ ] **Step 5: Commit**

```bash
git add scripts/build-tools.sh src/tools/appkit-api/README.md
git commit -m "feat(tools): build-tools.sh + appkit-api README"
```

---

### Task 13: Update CHANGELOG and close out

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Confirm the full test suite is green**

Run: `cd src/tools/appkit-api && swift test 2>&1 | tail -6`
Expected: all tests pass.

- [ ] **Step 2: Ensure CHANGELOG reflects what shipped**

Confirm `CHANGELOG.md` `[Unreleased] / Added` already lists the plugin scaffold, relocated skills, agent, and `appkit-api`. If anything is missing, add a bullet. (Content was created in Task 5; this is a verification + top-up step.)

- [ ] **Step 3: Commit any CHANGELOG change**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for scaffold + appkit-api" || echo "nothing to commit"
```

---

## Self-Review (completed during authoring)

**Spec coverage:** Phase 0 (§11.0) → Tasks 1–5. Phase 1a `appkit-api` (§5.1) → Tasks 6–13, using the verified symbol-graph data source, the `xcrun --sdk macosx` SDK-resolution fix, the documented cache path, and all five verbs (`check`/`members`/`availability`/`search`/`enums`). Binary-distribution decision (§3.2: build locally, ad-hoc sign, don't commit binaries) → Task 12 + `.gitignore`. Out-of-scope items (appkit-search, new skills, appkit-setup wiring) are explicitly deferred.

**Type consistency:** `Symbol.declaration`, `Symbol.qualifiedName`, `Symbol.macOSAvailability`, `Availability.introducedString/deprecatedString`, `SymbolIndex.check/members/availability/search/enumCases`, `SymbolOut(_:)`, `AvailabilityOut(_:)`, `Extractor.targetTriple/cacheDir/extractArguments/ensureExtracted/loadGraphs/index`, and `emitJSON(_:)` are defined once and referenced consistently across tasks and tests.

**Placeholder scan:** No TBD/TODO; every code and command step contains complete content. The only deferred items are explicitly labeled "later plan."

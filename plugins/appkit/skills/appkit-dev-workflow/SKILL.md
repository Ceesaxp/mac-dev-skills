---
name: appkit-dev-workflow
description: "Build and run workflow for native macOS AppKit apps — project creation with Tuist, the build-and-run.sh helper, xcodebuild, launching the .app, reading stdout/crash logs, error diagnosis, and prerequisites. Use when building, running, or fixing build errors in an AppKit / Swift / Cocoa project."
---

### Create or Open a Project

A native AppKit GUI app must be a **`.app` bundle** with an `Info.plist` — you cannot just `swift run` an executable and get a proper menu bar, Dock icon, window activation, or resource bundle. The supported, agent-friendly scaffold is an **Xcode project generated from a declarative `Project.swift` via [Tuist](https://docs.tuist.dev)** (`brew install tuist`). This is the AppKit analog of `dotnet new`: write source + `Project.swift`, run `tuist generate`, build with `xcodebuild`.

**New app** — write a `Project.swift` (start from `templates/Project.swift` in this skill) plus minimal sources, then generate:
```bash
tuist generate --no-open   # produces MyApp.xcodeproj + MyApp.xcworkspace from Project.swift
```

Canonical no-storyboard entry point (`Sources/main.swift`) — robust, avoids nib/storyboard requirements:
```swift
import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)      // shows in Dock + gets a menu bar
    app.activate()                         // NSApp.activate (macOS 14+); foregrounds the app
    app.run()
}
```
```swift
// Sources/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let wc = MainWindowController()
        wc.showWindow(nil)
        windowController = wc
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```
Build the window/content in an `NSWindowController` + `NSViewController` (see the `appkit-design` skill for layout, controls, sizing, and Liquid Glass).

**Existing app** — read the project to understand its shape before changing anything:
- `*.xcodeproj` / `*.xcworkspace`, or `Project.swift` (Tuist) / `project.yml` (XcodeGen) / `Package.swift` (SwiftPM).
- Deployment target (`MACOSX_DEPLOYMENT_TARGET`) and Swift language mode.
- Whether it uses storyboards/XIBs or is programmatic; AppKit vs. SwiftUI interop; MVC vs. MVVM.
- Existing dependencies (SwiftPM `Package.resolved`, or CocoaPods/Carthage if present).

### Add Packages

For a small dependency graph, declare SwiftPM packages inline in `Project.swift` under `packages:` and reference them per-target via `.package(product:)`, then regenerate:
```swift
let project = Project(
    name: "MyApp",
    packages: [
        .remote(url: "https://github.com/sparkle-project/Sparkle",
                requirement: .upToNextMajor(from: "2.0.0")),
    ],
    targets: [
        .target(name: "MyApp", /* … */ dependencies: [.package(product: "Sparkle")]),
    ]
)
```
For a larger graph, prefer a dedicated `Tuist/Package.swift` that lists the dependencies, then run `tuist install` and reference each with `.external(name: "Sparkle")` in the target. Pin to a major (`.upToNextMajor(from:)`) rather than an exact version so you pick up compatible fixes. Run `tuist generate` after editing `Project.swift` (`build-and-run.sh` does this for you, and runs `tuist install` first when a `Tuist/Package.swift` is present).

### Build & Run

Use the `build-and-run.sh` script included with this skill — it does the whole loop:
```bash
./build-and-run.sh
```

What it does automatically:
1. Verifies Xcode is selected (`xcode-select -p`) and the license is accepted.
2. Runs `tuist generate` if a `Project.swift` exists and the generated project is missing or stale (and `tuist install` first if a `Tuist/Package.swift` declares dependencies).
3. Auto-detects the scheme (or takes one as an argument) and the host architecture (arm64/x86_64).
4. Builds Debug with `xcodebuild` into a predictable `./build` DerivedData path.
5. Locates the built `.app` from `xcodebuild -showBuildSettings`.
6. Launches it with `open` (returns immediately; app runs detached).

**Reading output.** A normal `open MyApp.app` returns immediately and detaches, so you won't see the app's `stdout`. To watch logs and crashes (the analog of "debug output"):
```bash
./build-and-run.sh --logs        # runs MyApp.app/Contents/MacOS/MyApp in the foreground, streaming stdout/stderr
```
Run this in the **background** (Bash tool `run_in_background: true`) so it doesn't block your turn while the app is open; then read the streamed output. Alternatively, for already-running apps, tail the unified log:
```bash
log stream --level debug --predicate 'process == "MyApp"'
```

**Options:**
```bash
./build-and-run.sh                              # generate (if needed), build, launch with open
./build-and-run.sh --scheme MyApp              # explicit scheme
./build-and-run.sh --logs                       # build, then run the inner binary streaming stdout (use background)
./build-and-run.sh --skip-run                   # build only (safe to run in foreground)
./build-and-run.sh --configuration Release      # override Debug
```

**If the build fails:** read ALL errors (Swift emits the full set in one pass — no need to guess), batch-fix them, then re-run `build-and-run.sh`.

**If the app crashes on launch:** run with `--logs` and read the stderr/exception, or check the latest crash report:
```bash
ls -t ~/Library/Logs/DiagnosticReports/MyApp-*.ips | head -1 | xargs cat
```

### Common Errors

| Error / symptom | Fix |
|---|---|
| `xcode-select: error: tool 'xcodebuild' requires Xcode` | Point at full Xcode: `sudo xcode-select -s /Applications/Xcode.app`; accept license: `sudo xcodebuild -license accept` |
| `tuist: command not found` | `brew install tuist` (or run `/appkit-setup`) |
| `No such module 'AppKit'` on a SwiftPM executable | You're building a bare executable, not an app bundle — scaffold an Xcode project (Tuist) instead |
| `Cannot find 'X' in scope` / `no such module` | Add the `import`, or add the SwiftPM package to `Project.swift` (or `Tuist/Package.swift`) and regenerate |
| `'NSGlassEffectView' is only available in macOS 26 or newer` | Wrap usage in `if #available(macOS 26, *)` or raise the deployment target to 26.0 |
| Window opens then app immediately quits | Missing/short-lived window controller reference — retain it on the `AppDelegate`; ensure `app.run()` is called |
| App launches but no menu bar / not in Dock | `setActivationPolicy(.regular)` not set, or running the raw binary without a bundle — launch the `.app` with `open` |
| `Call to main actor-isolated ... in a synchronous nonisolated context` | Mark the type/method `@MainActor`, or hop with `await MainActor.run { }` |
| Blank/black window | Content view not added or zero-size constraints — verify `contentView`/constraints; check `translatesAutoresizingMaskIntoConstraints = false` |
| `code signing is required for product type 'Application'` (on device-style targets) | For local Debug, set `CODE_SIGN_IDENTITY=-` (ad-hoc) or "Sign to Run Locally" / automatic signing |
| `The app is damaged` after copying a build | Quarantine/unsigned — for local runs `xattr -cr MyApp.app`; for distribution see `appkit-packaging` |

### Prerequisites

| Requirement | Minimum | Recommended | Install |
|---|---|---|---|
| macOS | matches your deployment target | macOS 26 Tahoe (to build for Tahoe) | — |
| Xcode | 26 (for the macOS 26 SDK) | latest 26.x (Swift 6.3+) | Mac App Store, or `xcodes install` |
| Command Line Tools / license | accepted | accepted | `sudo xcodebuild -license accept` |
| Tuist | 4.x | latest | `brew install tuist` |
| Homebrew | — | latest | <https://brew.sh> |

If any of these are missing when you try to use them — `xcodebuild`/`tuist` not found, the Xcode license unaccepted, no Xcode selected — **do not try to install Xcode yourself or work around it**. Stop and tell the user the prerequisite is missing and ask them to run `/appkit-setup` (a user-invoked skill that installs and verifies everything). Then retry the failed command.

### Critical Rules

- ❌ NEVER ship a bare `swift build` executable as a GUI app — AppKit apps need a `.app` bundle with `Info.plist` (use Tuist + `xcodebuild`).
- ❌ NEVER set `LSUIElement`/agent activation just to silence a "no window" bug — fix the window controller lifetime.
- ❌ NEVER block the main thread (`.sync` to the main queue, semaphore waits on main) — it deadlocks the UI.
- ❌ NEVER hardcode an absolute DerivedData path from another machine — let `build-and-run.sh` resolve `BUILT_PRODUCTS_DIR`.

### References

- `build-and-run.sh` — included with this skill; generates, builds, and launches automatically.
- `templates/Project.swift` — a minimal Tuist manifest for a programmatic AppKit app + UI test target, targeting macOS 26.

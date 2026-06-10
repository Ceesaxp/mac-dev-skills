---
name: appkit-setup
description: "Install and verify the prerequisites the AppKit dev skills depend on — Xcode 27 (for the macOS 27 SDK) with its license accepted, the Command Line Tools, Homebrew, and the CLI tools (Tuist, swift-format, create-dmg). Use when setting up a new Mac, or when another appkit skill reports a missing prerequisite (e.g. xcodebuild/tuist not found, the Xcode license isn't accepted, or no signing identity is present)."
disable-model-invocation: true
---

### Purpose

Install and verify the prerequisites every other `appkit-*` skill assumes are present on the machine.

This skill is **idempotent** — every step checks first, skips if already satisfied, and moves on. Re-running on a fully set-up Mac is a fast no-op.

It is **user-invoked only** — run it explicitly with `/appkit-setup`. The agent will not load it on its own; if a later command fails because a prerequisite is missing, the agent stops and asks the user to run this.

### Steps

**Batch all detection up front** — run every check together, show the user the full picture, then install only what's missing.

#### Detect everything

```bash
# Xcode selected + version (need full Xcode for the macOS 27 SDK, not just CLT)
XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
XCODE_VER="$(xcodebuild -version 2>/dev/null | head -1 || true)"      # e.g. "Xcode 27.x"
# License accepted? (xcodebuild fails with a license error if not)
if xcodebuild -version >/dev/null 2>&1; then XCODE_LICENSE="ok"; else XCODE_LICENSE="not accepted"; fi

# Homebrew
BREW="$(command -v brew || true)"

# CLI tools
TUIST="$(command -v tuist || true)"
# swift-format ships inside the Xcode toolchain (also runnable as `swift format`);
# a standalone `swift-format` binary can additionally be installed via Homebrew.
SWIFTFORMAT="$(command -v swift-format || true)"
CREATE_DMG="$(command -v create-dmg || true)"

# Developer-mode for running tests/debugger without repeated auth prompts
DEVTOOLS="$(DevToolsSecurity -status 2>/dev/null || true)"

# Signing identities (informational — needed only for appkit-packaging)
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | grep -c 'Developer ID Application')"
```

Print a one-shot status table so the user sees what you're about to do, e.g.:

```
Xcode (full, ≥27)        ✅ Xcode 27.0 at /Applications/Xcode.app
                         (or ❌ only Command Line Tools / missing — see note below)
Xcode license            ⚠ not accepted — needs `sudo xcodebuild -license accept`
Homebrew                 ✅ found  (or ❌ missing — will install)
Tuist                    ❌ missing — will `brew install tuist`
swift-format             ✅ found (ships with Xcode toolchain; standalone via brew)
create-dmg               ❌ missing — will `brew install create-dmg`
DevToolsSecurity         ⚠ disabled — needs admin to enable
Developer ID identity    ⏭ 0 found (only needed for signing/notarization)
```

#### Install what's missing

Skip anything already-OK. The remaining steps:

##### Xcode 27 (do NOT auto-install — ask first)

A full **Xcode 27** is required for the **macOS 27 SDK**. It is multi-gigabyte, so **never download it silently.** If only the Command Line Tools are present (or `xcode-select -p` points at `/Library/Developer/CommandLineTools`), or the version is below 27, tell the user and offer options — don't act without consent:

> Building for macOS 26 Tahoe needs the full Xcode 27 (several GB). I won't download it automatically. You can install it from the Mac App Store, or with `xcodes` for a specific version:
> ```bash
> brew install xcodesorg/made/xcodes
> xcodes install 27          # or a specific 27.x
> sudo xcode-select -s /Applications/Xcode.app
> ```

If a full Xcode is already installed but not selected, point at it (this is safe and fast):
```bash
sudo xcode-select -s /Applications/Xcode.app    # adjust path if versioned
```

##### Accept the Xcode license (needs admin)

If the license isn't accepted, `xcodebuild` fails. Accepting requires `sudo` — **ask the user before triggering the prompt:**

> Xcode's license hasn't been accepted, which blocks `xcodebuild`. Accepting needs one admin command (`sudo`). Run it now?
> ```bash
> sudo xcodebuild -license accept
> ```

If they decline, print the command for later and continue to the summary.

##### Homebrew (only if missing)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
After install, make sure `brew` is on `PATH` for the rest of the session (Apple Silicon default):
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

##### CLI tools — install if missing, then upgrade to latest

These ship breaking changes between releases; the skills assume latest. Install whatever's missing, then upgrade:
```bash
brew install tuist swift-format create-dmg   # no-op for already-installed
brew upgrade tuist swift-format create-dmg   # bump to latest
```
`swift-format` is also bundled with the Xcode toolchain (run as `swift format …`), so the Homebrew install is only needed if you want the standalone `swift-format` binary on `PATH` — install it for parity with `appkit-code-review`'s `swift-format lint` invocation. Tuist 4.x can alternatively be managed with `mise` or the official install script if the user prefers that over Homebrew.

##### DevToolsSecurity (ask first — needs admin)

Enabling developer mode lets the debugger/test runner attach without repeated authorization prompts. It needs `sudo` — **ask first:**

> Enabling Xcode developer mode (so test/debug runs don't prompt for authorization each time) needs one admin command. Run it now?
> ```bash
> sudo DevToolsSecurity -enable
> ```

If declined, print the command and continue.

> **Signing identities are NOT set up here.** A **Developer ID Application** certificate is only needed for `appkit-packaging` (signing/notarization). Creating it involves the Apple Developer portal and your Apple account — out of scope for machine setup. If `appkit-packaging` later reports no identity, point the user to the portal (Certificates → Developer ID Application).

##### Build the native tools (required — the suite's grounding tools)

`appkit-api` (SDK symbol/availability validator) and `appkit-search` (HIG-grounded pattern search) back the whole suite — `appkit-design` and the agent call them constantly. Build, sign, and install both (idempotent; needs the full Xcode):
```bash
scripts/build-tools.sh    # builds → ad-hoc signs → installs appkit-api + appkit-search (with its corpus bundle) into ~/.local/bin
```
Confirm they work: `appkit-api check NSGlassEffectView` and `appkit-search list` should both return JSON.

##### Optional research tooling (advanced / dual-use — only if the user wants it)

These are **not** needed for normal app building; set them up only for `appkit-private-apis` / `appkit-app-inspector`.

- **flexscope** (runtime inspector, drives `appkit-app-inspector`) — the user's **separate** repo. If it's present at its path, build it: `( cd "$FLEXSCOPE_DIR" && swift build -c release && ./scripts/sign.sh )`, then gate with `flexscope doctor` (it must be all-green — SIP/AMFI/library-validation off; see `appkit-app-inspector`). **Dev-box only.** If absent, point the user to `appkit-app-inspector` for how to obtain/build it — do **not** clone it automatically.
- **PrivateHeaderKit** (header dumper, used by `appkit-private-apis`) — check whether `privateheaderkit-dump` is on `PATH`; if not, point the user to `appkit-private-apis` (`swift run -c release privateheaderkit-install` from its repo). It's a static dumper — no SIP changes.

### Final summary — always print this

After everything, print a single-table summary so the user knows exactly what changed:

```
==== appkit-setup summary ====
Xcode (full, ≥27)     ⏭ already present (Xcode 27.0)   (or ❌ action needed: install Xcode 27)
Xcode license         ✅ accepted   (or ⏭ skipped — user declined: run `sudo xcodebuild -license accept`)
Homebrew              ⏭ already present
Tuist                 ✅ installed
swift-format          ✅ upgraded to latest
create-dmg            ✅ installed
DevToolsSecurity      ✅ enabled   (or ⏭ skipped — user declined)
Native tools          ✅ appkit-api + appkit-search built & installed (~/.local/bin)
Developer ID identity ⏭ 0 found (only needed for signing — see appkit-packaging)
Research tooling      ⏭ flexscope / PrivateHeaderKit not set up (optional — see appkit-app-inspector / appkit-private-apis)

You're ready. Try:
  Activate the appkit-dev agent and ask it to "build me a macOS markdown editor with a live preview"
```

### Things to NOT do

- ❌ **Do not auto-download Xcode.** It's multi-GB. Always ask, and offer the App Store / `xcodes` options.
- ❌ **Do not trigger `sudo` prompts without asking first** — license acceptance and `DevToolsSecurity` both need admin; confirm before each.
- ❌ **Do not try to create signing certificates.** That's an Apple-account flow handled in `appkit-packaging`, not here.
- ❌ **Do not silently retry on failure.** If a `brew install` fails (no network, tap down, permissions), record the error in the summary table and move on so the user can see what failed.
- ❌ **Do not assume Command Line Tools are enough** — a CLT-only machine cannot build against the macOS 27 SDK; you need the full Xcode.
- ❌ **Do not skip the `brew shellenv` step** after installing Homebrew, or subsequent `brew install` calls fail with "command not found".

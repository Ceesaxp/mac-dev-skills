---
name: appkit-packaging
description: "Code signing, notarization, and distribution for native macOS AppKit apps — release builds, Developer ID signing (codesign), notarization (notarytool), stapling, building signed .dmg / .pkg installers, GitHub Actions CI, TestFlight beta distribution, and Mac App Store submission. Use when preparing a release, signing an app, notarizing, creating an installer, setting up CI packaging, distributing a beta via TestFlight, or publishing to the Mac App Store."
---

### Distribution paths

macOS has a few distinct release pipelines — pick first:

- **Developer ID (outside the App Store).** Sign with a **Developer ID Application** cert, **notarize** with Apple, **staple** the ticket, ship a `.dmg` or `.pkg`. This is the bulk of this skill.
- **TestFlight (beta).** Upload an App-Store-signed build to App Store Connect, then distribute to internal/external testers via the **TestFlight** app on macOS. No notarization; uses App Review (lightweight Beta App Review for external testers). The on-ramp to a Mac App Store release. See `references/ci-and-app-store.md`.
- **Mac App Store.** Sign with **Apple Distribution** / **3rd Party Mac Developer** certs, upload to App Store Connect; the store does **App Review** (not notarization) and re-signs for delivery. There is no clean first-party CLI submit — it's Transporter / Xcode Organizer. See `references/ci-and-app-store.md`.

TestFlight and the Mac App Store share the same build, certs, and upload step — TestFlight is the beta stage of that one pipeline, not a separate signing path. This is the macOS analog of WinUI's MSIX-signing vs. Microsoft-Store split.

### Private APIs & distribution (advisory)

If your app uses private APIs, method swizzling, or anything learned by runtime-inspecting other apps (`appkit-private-apis`, `appkit-app-inspector`), the pipeline choice above is also a **policy** choice — surface it, don't gate on it:

- **App Store review may reject private-API usage** — Apple judges **case-by-case**, there's no public allow-list, and not every use is auto-rejected. Hiding a private class name from the static scanner (no string literals, `object_getIvar` over KVC) defeats *static* analysis only; it does **not** make runtime use policy-safe.
- **Developer ID + notarization is the escape hatch.** If review rejects it — or to avoid the question — ship **outside** the store (web / Sparkle / direct download), the Developer-ID flow that is the bulk of this skill. Private APIs are allowed there; you own the risk that an OS update breaks them.
- **The inspection tooling never ships regardless.** flexscope's injected dylib (`appkit-app-inspector`) is a dev-box-only tool; only *knowledge* (a font, a constraint) crosses into the product, never the tool or any injection step.

The suite never blocks you from shipping these — it tells you the trade-off so you pick the right pipeline. (Reciprocal advisories live in `appkit-private-apis` and `appkit-app-inspector`.)

### Quick Reference (Developer ID)

| Task | Command |
|---|---|
| Build for release | `./BuildAndRun.sh --configuration Release --skip-run` (or `xcodebuild -configuration Release archive`) |
| List signing identities | `security find-identity -v -p codesigning` |
| Strip quarantine before signing | `xattr -cr MyApp.app` |
| Sign (hardened runtime + timestamp) | `codesign --force --options runtime --timestamp --sign "Developer ID Application: NAME (TEAMID)" MyApp.app` |
| Verify signature | `codesign --verify --deep --strict --verbose=2 MyApp.app` |
| Zip for notarization | `ditto -c -k --keepParent MyApp.app MyApp.zip` |
| Store notary credentials (once) | `xcrun notarytool store-credentials "AC_NOTARY" --apple-id … --team-id … --password <app-specific>` |
| Submit + wait | `xcrun notarytool submit MyApp.zip --keychain-profile "AC_NOTARY" --wait` |
| Read a rejection log | `xcrun notarytool log <submission-id> --keychain-profile "AC_NOTARY" log.json` |
| Staple the ticket | `xcrun stapler staple MyApp.app` |
| Gatekeeper check | `spctl -a -vvv -t install MyApp.app` |

> The `notarize.sh` script bundled with this skill runs the whole sign → zip → submit → staple → verify chain. Use it once you have a Release build and a stored notary profile.

### End-to-End Workflow (Developer ID)

#### Step 1 — Build for release
```bash
./BuildAndRun.sh --configuration Release --skip-run
```
Or archive for a clean exported product:
```bash
xcodebuild -scheme MyApp -configuration Release -derivedDataPath ./build \
  -archivePath ./build/MyApp.xcarchive archive
```

#### Step 2 — Find your signing identity (one-time)
```bash
security find-identity -v -p codesigning
```
You need a **"Developer ID Application: Your Name (TEAMID)"** identity in the login keychain. If you only see Apple Development / Apple Distribution, you don't have a Developer ID cert yet — create one in the Apple Developer portal (Certificates → Developer ID Application) and download it. `TEAMID` is your 10-character team identifier.

#### Step 3 — Sign (inside-out, hardened runtime, timestamped)
Notarization **requires** the hardened runtime (`--options runtime`) and a secure timestamp (`--timestamp`). Sign **nested code first, the app bundle last** — frameworks, helpers, XPC services, then the `.app`. Apple discourages `--deep` for production; sign each nested item explicitly.
```bash
xattr -cr MyApp.app           # remove any quarantine xattrs first
IDENTITY="Developer ID Application: Your Name (TEAMID)"

# nested code, deepest first (frameworks, helpers, plugins) — example:
find MyApp.app/Contents/Frameworks -name "*.framework" -o -name "*.dylib" | while read -r item; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
done

# then the app bundle itself
codesign --force --options runtime --timestamp \
  --entitlements MyApp.entitlements \
  --sign "$IDENTITY" MyApp.app

codesign --verify --deep --strict --verbose=2 MyApp.app   # 0 = good
```
If you need runtime exceptions (JIT, disabling library validation for plug-ins, etc.), declare them in `MyApp.entitlements` — keep them minimal.

#### Step 4 — Store notary credentials (one-time)
Create an **app-specific password** at appleid.apple.com, then cache a notarytool profile in the keychain so later submits need no secrets:
```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "abcd-efgh-ijkl-mnop"     # the app-specific password
```
(Alternatively authenticate with an App Store Connect API key: `--key`, `--key-id`, `--issuer`.)

#### Step 5 — Notarize and wait
notarytool wants an archive — a `.zip` (use `ditto`, **not** Finder/`zip`, to preserve the bundle), or submit a `.dmg`/`.pkg` directly.
```bash
ditto -c -k --keepParent MyApp.app MyApp.zip
xcrun notarytool submit MyApp.zip --keychain-profile "AC_NOTARY" --wait
```
`--wait` blocks until Apple returns `Accepted` or `Invalid`. On `Invalid`, pull the log — it names the exact unsigned/misconfigured binary:
```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_NOTARY" log.json
```

#### Step 6 — Staple
Attach the notarization ticket so Gatekeeper passes **offline**. Staple the artifact you ship:
```bash
xcrun stapler staple MyApp.app        # staple the app (then re-package), or
xcrun stapler staple MyApp.dmg        # staple the dmg/pkg you distribute
```
(You can't staple a `.zip` — staple the `.app` inside, or staple the `.dmg`/`.pkg`.)

#### Step 7 — Verify like a first-run user would
```bash
spctl -a -vvv -t install MyApp.app    # expect: accepted, source=Notarized Developer ID
xcrun stapler validate MyApp.app
codesign --verify --deep --strict --verbose=2 MyApp.app
```

#### Step 8 — Package for distribution
**DMG** (drag-to-Applications):
```bash
# simplest:
hdiutil create -volname "MyApp" -srcfolder MyApp.app -ov -format UDZO MyApp.dmg
# nicer (background, /Applications symlink): brew install create-dmg
create-dmg --volname "MyApp" --app-drop-link 450 160 MyApp.dmg MyApp.app
```
Then **sign and staple the DMG itself** so the download is trusted as one unit:
```bash
codesign --force --timestamp --sign "$IDENTITY" MyApp.dmg
xcrun stapler staple MyApp.dmg
```
**PKG** (installer, e.g. needs a privileged step):
```bash
pkgbuild --component MyApp.app --install-location /Applications MyApp-comp.pkg
productbuild --package MyApp-comp.pkg \
  --sign "Developer ID Installer: Your Name (TEAMID)" MyApp.pkg
xcrun notarytool submit MyApp.pkg --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple MyApp.pkg
```
(PKG signing uses the **Developer ID Installer** cert — a different cert from Application signing.)

### Key Rules

- **Notarization needs hardened runtime + timestamp.** Missing either → `Invalid`. (`--options runtime --timestamp`.)
- **Sign nested code inside-out**, app bundle last. Avoid `--deep` for production.
- **Use `ditto -c -k --keepParent`** to zip for notarization — Finder's "Compress" and plain `zip` mangle bundle symlinks/metadata and fail.
- **Staple the artifact you actually ship** (the `.app` inside the dmg, or the dmg/pkg). A stapled ticket is what lets Gatekeeper pass without network.
- **The DMG/PKG itself should be signed and (for dmg) stapled**, not just the app inside it.
- **App Store is a different cert + flow** — don't sign a store build with Developer ID. See the reference.
- **Never disable Gatekeeper or tell users to `xattr -d` your download** as a "fix" — that masks a real signing/notarization failure.

### CI/CD

`references/ci-and-app-store.md` has a full **GitHub Actions** workflow (macOS runner, import a base64 cert into a temporary keychain, build → sign → notarize → staple → upload artifact) plus the Mac App Store submission notes. The shape:
```yaml
jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: '26' }
      # import Developer ID cert from secrets into a temp keychain, then:
      - run: ./plugins/appkit/skills/appkit-packaging/notarize.sh ...
```

### TestFlight (beta distribution)

Before a Mac App Store release, distribute betas through **TestFlight** — same App-Store-signed build, same App Store Connect upload, but testers install via the **TestFlight app on macOS** (macOS 12+). It does **not** use Developer ID or notarization.

Flow:
1. **Build an App Store package** exactly as for the store (App Sandbox on, Apple Distribution signing, an increasing `CFBundleVersion`) — see the App Store section in `references/ci-and-app-store.md`. The same archive feeds both TestFlight and a store release.
2. **Upload to App Store Connect** (Xcode Organizer → Distribute → App Store Connect, the Transporter app, `xcrun altool --upload-app`, or the App Store Connect API in CI). Processing takes ~5–30 min.
3. **Provide Test Information** in the app's **TestFlight** tab (beta description, what to test, feedback email) — required before external testing.
4. **Add testers:**
   - **Internal** — up to 100 App Store Connect users on your team; builds are available **immediately after processing, no review**. (Builds can be marked "TestFlight Internal Only".)
   - **External** — up to 10,000 testers via email or a public link; the first build (and significant changes) must pass a lightweight **Beta App Review**.
5. **Testers install** via the macOS TestFlight app and send feedback/crash reports. **Builds expire 90 days** after upload; ship a new build to continue.

Don't use TestFlight to ship to end users in place of the store — Apple prohibits it and it risks account action. See `references/ci-and-app-store.md` for the upload commands, `ExportOptions.plist`, and CI automation (shared with the App Store section).

### Troubleshooting

| Symptom | Fix |
|---|---|
| `errSecInternalComponent` on codesign | Identity not in the keychain or keychain locked — `security unlock-keychain`; confirm with `find-identity` |
| notarytool returns `Invalid` | `notarytool log <id>` — almost always an unsigned/un-hardened nested binary; re-sign it inside-out |
| `The binary is not signed with a valid Developer ID certificate` | You signed with Apple Development, not Developer ID Application |
| `code object is not signed at all` (nested) | A framework/helper was missed — sign every nested Mach-O before the bundle |
| "App is damaged and can't be opened" on another Mac | Not notarized/stapled, or shipped a `zip` made by Finder — notarize + staple, repackage with `ditto`/`create-dmg` |
| `spctl` says `source=Unnotarized Developer ID` | Notarization didn't complete or wasn't stapled — finish Steps 5–6 |
| Hardened-runtime crash (e.g. plug-in won't load) | Add the specific entitlement (library-validation/JIT) — minimally — and re-sign |
| `stapler staple` → `Error 65 / could not find ticket` | Notarization for that exact binary hasn't propagated yet, or you stapled before `Accepted` — wait, re-staple |

### References

| File | Read when… |
|---|---|
| `notarize.sh` | You want the sign → notarize → staple → verify chain run for you |
| `references/ci-and-app-store.md` | Setting up GitHub Actions release CI, distributing via TestFlight, or submitting to the Mac App Store |

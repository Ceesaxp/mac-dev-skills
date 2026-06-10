# CI and Mac App Store — Reference

Detailed companions to the `appkit-packaging` SKILL: a full GitHub Actions release pipeline (Developer ID), TestFlight beta distribution, and the Mac App Store submission path. See [SKILL.md](../SKILL.md) for the local workflow.

---

## GitHub Actions — Developer ID release

The hard part in CI is that signing needs your **Developer ID Application** certificate and private key available on an ephemeral macOS runner, without leaking them. The pattern: export the cert+key as a base64 `.p12` secret, import it into a **temporary keychain** at the start of the job, and delete the keychain at the end. Notarization uses an **App Store Connect API key** (cleaner for CI than an Apple-ID app-specific password).

### Secrets to configure (repo → Settings → Secrets)

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12` of your exported Developer ID Application cert **and** private key |
| `DEVELOPER_ID_P12_PASSWORD` | the password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string used for the temporary keychain |
| `AC_API_KEY_P8_BASE64` | base64 of the App Store Connect API key `.p8` file |
| `AC_API_KEY_ID` | the key ID (e.g. `2X9R4HXF34`) |
| `AC_API_ISSUER_ID` | the issuer UUID from App Store Connect |
| `SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |

### Workflow

```yaml
name: Release
on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: macos-15          # provides Xcode 26 toolchains
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 26
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '26'

      - name: Install tools
        run: brew install tuist create-dmg

      - name: Import Developer ID certificate into a temp keychain
        env:
          P12_BASE64:   ${{ secrets.DEVELOPER_ID_P12_BASE64 }}
          P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
          KC_PASSWORD:  ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
          echo "$P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security create-keychain -p "$KC_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 3600 "$KEYCHAIN"
          security unlock-keychain -p "$KC_PASSWORD" "$KEYCHAIN"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
            -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASSWORD" "$KEYCHAIN"
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          echo "SIGNING_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"

      - name: Store notarytool credentials (API key)
        env:
          KEY_P8_BASE64: ${{ secrets.AC_API_KEY_P8_BASE64 }}
          KEY_ID:        ${{ secrets.AC_API_KEY_ID }}
          ISSUER_ID:     ${{ secrets.AC_API_ISSUER_ID }}
        run: |
          echo "$KEY_P8_BASE64" | base64 --decode > "$RUNNER_TEMP/ac_key.p8"
          xcrun notarytool store-credentials "AC_NOTARY" \
            --key "$RUNNER_TEMP/ac_key.p8" \
            --key-id "$KEY_ID" \
            --issuer "$ISSUER_ID"

      - name: Build (Release)
        run: ./plugins/appkit/skills/appkit-dev-workflow/build-and-run.sh --configuration Release --skip-run

      - name: Sign, notarize, staple, build DMG
        run: |
          APP=$(find ./build/Build/Products/Release -maxdepth 1 -name '*.app' | head -1)
          ./plugins/appkit/skills/appkit-packaging/notarize.sh \
            --app "$APP" \
            --identity "${{ secrets.SIGN_IDENTITY }}" \
            --profile  AC_NOTARY \
            --dmg

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MyApp-dmg
          path: ./build/Build/Products/Release/*.dmg

      - name: Clean up keychain
        if: always()
        run: security delete-keychain "$SIGNING_KEYCHAIN" || true
```

**Notes**
- `macos-15` (or the newest available macOS runner image) carries the Xcode 26 toolchains; `setup-xcode` pins the exact version. Check the runner image release notes for which Xcodes are installed before pinning.
- Importing into a **dedicated temp keychain** (not `login.keychain`) keeps the runner clean and lets `if: always()` delete it.
- Prefer the **App Store Connect API key** over an Apple-ID app-specific password in CI — it has no human MFA and is revocable.
- For tag-triggered releases, also add a step to create a GitHub Release and attach the `.dmg`.

---

## Mac App Store submission

The App Store path does **not** use Developer ID or notarization. Apple does **App Review**, and the store re-signs your build for delivery. You still sign locally, but with App Store certs.

### Certs & profiles
- **Apple Distribution** certificate (app signing) + a **Mac App Store** provisioning profile for the app's bundle ID.
- **3rd Party Mac Developer Installer** / **Mac Installer Distribution** certificate if you build a `.pkg` for upload (App Store apps are delivered as signed `.pkg`).
- Manage these in the Apple Developer portal, or let Xcode "Automatically manage signing".

### Required for an App Store build (vs. Developer ID)
- **App Sandbox is mandatory** (`com.apple.security.app-sandbox = true` in entitlements) — scope every entitlement (file access, network client/server, hardware) to what you actually use.
- Set the bundle ID, version (`CFBundleShortVersionString`), and build (`CFBundleVersion`) to match the App Store Connect record.
- No hardened-runtime/Developer-ID-only entitlements; use the App Store entitlement set.

### Build and upload
The cleanest route is an Xcode **archive** → **Organizer** → **Distribute App → App Store Connect**, which validates, signs, and uploads in one flow. From CI/CLI:
```bash
# Archive
xcodebuild -scheme MyApp -configuration Release \
  -archivePath ./build/MyApp.xcarchive archive

# Export an App Store package using an ExportOptions.plist
#   (method = app-store-connect; teamID = TEAMID; signingStyle = automatic|manual)
xcodebuild -exportArchive \
  -archivePath ./build/MyApp.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath ./build/export

# Upload to App Store Connect — altool --upload-app, Transporter, or the ASC API.
# (notarytool is the NOTARY tool for Developer ID — it does NOT upload to the store.)
xcrun altool --validate-app -f ./build/export/MyApp.pkg \
  -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
xcrun altool --upload-app -f ./build/export/MyApp.pkg \
  -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
```
`ExportOptions.plist` (minimal, App Store). **Use `app-store-connect`** — `app-store` is deprecated (Xcode 27 still accepts it as an alias):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>TEAMID</string>
  <key>signingStyle</key><string>automatic</string>
  <!-- manual signing? add: -->
  <!-- <key>signingCertificate</key><string>Apple Distribution</string> -->
  <!-- <key>installerSigningCertificate</key><string>Mac Installer Distribution</string> -->
  <!-- <key>provisioningProfiles</key><dict><key>com.you.MyApp</key><string>Profile Name</string></dict> -->
  <!-- upload directly from xcodebuild instead of a separate altool step: -->
  <!-- <key>destination</key><string>upload</string> -->
</dict></plist>
```

> **`altool` API-key CI trap:** unlike `notarytool` (`--key <path>`), `altool` takes **no key path** — with `--apiKey`/`--apiIssuer` it searches `./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys`, and `$API_PRIVATE_KEYS_DIR` for a file named exactly `AuthKey_<KEYID>.p8`. In CI, base64-decode your `.p8` into one of those dirs under that name first (or pass `--p8-file-path <path>`). For a **Team** key pass `--apiIssuer`; for an **Individual** key **omit** it (passing it returns 401).

### Then, in App Store Connect (browser)
1. Create the app record (bundle ID, name, primary language, SKU).
2. Complete metadata: description, keywords, support URL, **privacy policy** (required), and the **App Privacy** questionnaire.
3. Upload screenshots at the required Mac sizes.
4. Set the **age rating** questionnaire.
5. Select the uploaded build, set pricing/availability, and **Submit for Review**.

There is **no fully first-party CLI to push a build through review** — uploading is scriptable (`altool --upload-app` / Transporter / the App Store Connect API), but creating the record, metadata, screenshots, and the actual submit are browser steps in App Store Connect. This mirrors the WinUI "Microsoft Store submission is browser-based" note.

### Gotchas
- **Rejected for missing sandbox / over-broad entitlements** — the most common automated-validation failure. Trim entitlements to the minimum.
- **`CFBundleVersion` must increase** with every upload, even for the same marketing version.
- **Privacy manifest** — if you use APIs/data categories that require it, include a `PrivacyInfo.xcprivacy`; validation will flag omissions.
- App Store and Developer ID are **mutually exclusive signings** — don't ship a Developer-ID-signed build to the store or vice-versa.

---

## TestFlight beta distribution

TestFlight is the **beta stage of the App Store pipeline**, not a separate signing path. You produce and upload the *same* App-Store-signed build described above; the only differences are where testers get it (the **TestFlight app on macOS**, available macOS 12+) and that you distribute it before — or instead of, during beta — a public release. There is **no Developer ID and no notarization** involved.

### What's the same as App Store, what's different

Same: Apple Distribution signing, App Sandbox required, the bundle ID/version setup, and the **upload step**. Different: you don't submit for full App Store Review to test — internal builds need no review, external builds need only a lightweight Beta App Review.

> For builds to be eligible for TestFlight they must carry App Store distribution provisioning (application identifiers in the profile). A Developer ID build cannot be used for TestFlight.

### Step 1 — Build and upload (shared with App Store)

Archive and export an App Store package exactly as in the Mac App Store section above (`xcodebuild archive` → `-exportArchive` with `method = app-store-connect`), then upload to App Store Connect. Any of:
- **Xcode Organizer** → Distribute App → App Store Connect (validates, signs, uploads).
- **Transporter** app (drag the `.pkg`).
- **CLI:** `xcrun altool --upload-app -f ./build/export/MyApp.pkg -t macos --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"` (App Store Connect API key — ideal for CI).

Processing in App Store Connect takes roughly **5–30 minutes**; the build then appears under the app's **TestFlight** tab.

### Step 2 — Provide Test Information

In the app's **TestFlight** tab → Test Information, fill in the beta app description, "what to test" notes, and a feedback email. This is **required before you can invite external testers** (and good practice for internal ones).

### Step 3 — Add testers

| Track | Limit | Review? | Availability |
|---|---|---|---|
| **Internal** | up to 100 App Store Connect users on your team | none | immediately after processing |
| **External** | up to 10,000 (email invite or public link) | first build + significant changes pass a lightweight **Beta App Review** | after approval |

Create tester **groups** (e.g. "QA", "Power Users") and assign specific builds per group for staged rollouts. Builds can be uploaded as **TestFlight Internal Only** to keep them off the external track entirely. Testers install through the macOS TestFlight app and can submit feedback and crash reports; App Store Connect shows installs, sessions, and crashes per build (aggregate, not per-user).

### Step 4 — Build expiry

**A TestFlight build is testable for up to 90 days** from upload. To keep testing past that, upload a new build (remember to bump `CFBundleVersion`). External testers get a new build only after it's reviewed again, unless you mark it as having no significant changes.

### CI automation

The same GitHub Actions shape as the Developer ID job applies, swapping the sign/notarize step for archive → export (`method: app-store-connect`) → upload. Authenticate uploads with an **App Store Connect API key** (`--apiKey`/`--apiIssuer`, or the App Store Connect API / `fastlane pilot`) so there's no interactive login. Tester management is also scriptable via the App Store Connect API; assigning builds to external groups still triggers Beta App Review.

### Gotchas

- **Internal group greyed out / testers see nothing** — almost always missing **Test Information** (beta app description). Fill it in, then re-assign the build.
- **`CFBundleVersion` must increase** for every upload, same as the store.
- **Don't use TestFlight as a distribution channel for real users** — it's for testing only; using it to bypass App Store Review violates Apple's terms and can get the account terminated.
- **Build expired mid-test** — 90-day limit hit; upload a fresh build.
- **External build stuck "Waiting for Review"** — Beta App Review is required for the first external build and after significant changes; internal testing needs no review and is the fast path while iterating.

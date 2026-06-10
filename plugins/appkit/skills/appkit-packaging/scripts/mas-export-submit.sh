#!/usr/bin/env bash
set -euo pipefail
#
# mas-export-submit.sh — Mac App Store pipeline from an xcarchive.
#   archive (optional) → xcodebuild -exportArchive (method=app-store-connect) → altool validate + upload
#
# Auth is App Store Connect API key ONLY — no Apple ID, no app-specific password, no interactive prompt.
# "Submit for Review" is NOT scripted here: there is no first-party CLI for the final submit
# (App Store Connect browser UI / fastlane deliver / ASC API). This stops at a successful upload.

usage() {
  cat >&2 <<'EOF'
Usage: mas-export-submit.sh [options]

Provide an existing archive OR a scheme to archive:
  -a, --archive PATH       Path to an existing .xcarchive
  -s, --scheme NAME        Scheme to archive (used only when --archive is absent)

Export options (a plist is generated if not supplied):
  -o, --export-options P   ExportOptions.plist (method MUST be app-store-connect)
  -t, --team-id TEAMID     10-char Team ID (required when generating the plist)
  -e, --export-path DIR    Export output dir (default: ./export)

App Store Connect API key (all three required — no passwords anywhere):
  -k, --key-id KEYID       ASC API Key ID            (env: KEY_ID)
  -i, --issuer-id ISSUER   ASC API Issuer ID         (env: ISSUER_ID)
  -p, --p8 PATH            Path to AuthKey_<KEYID>.p8 (env: P8_PATH)

      --no-upload          Export only; skip altool validate/upload.
  -h, --help               Show this help.

Env equivalents: ARCHIVE_PATH, SCHEME, EXPORT_OPTIONS, TEAM_ID, EXPORT_PATH, KEY_ID, ISSUER_ID, P8_PATH.
EOF
  exit "${1:-2}"
}

# ---- defaults / env ---------------------------------------------------------
ARCHIVE_PATH="${ARCHIVE_PATH:-}"; SCHEME="${SCHEME:-}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-}"; TEAM_ID="${TEAM_ID:-}"
EXPORT_PATH="${EXPORT_PATH:-./export}"
KEY_ID="${KEY_ID:-}"; ISSUER_ID="${ISSUER_ID:-}"; P8_PATH="${P8_PATH:-}"
DO_UPLOAD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--archive)        ARCHIVE_PATH="$2"; shift 2;;
    -s|--scheme)         SCHEME="$2"; shift 2;;
    -o|--export-options) EXPORT_OPTIONS="$2"; shift 2;;
    -t|--team-id)        TEAM_ID="$2"; shift 2;;
    -e|--export-path)    EXPORT_PATH="$2"; shift 2;;
    -k|--key-id)         KEY_ID="$2"; shift 2;;
    -i|--issuer-id)      ISSUER_ID="$2"; shift 2;;
    -p|--p8)             P8_PATH="$2"; shift 2;;
    --no-upload)         DO_UPLOAD=0; shift;;
    -h|--help)           usage 0;;
    *) echo "ERROR: unknown argument: $1" >&2; usage;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo ">> $*" >&2; }

# ---- 1. validate inputs -----------------------------------------------------
[[ -n "$ARCHIVE_PATH" || -n "$SCHEME" ]] || die "supply --archive PATH or --scheme NAME"
if [[ $DO_UPLOAD -eq 1 ]]; then
  [[ -n "$KEY_ID"    ]] || die "--key-id / KEY_ID required (or pass --no-upload)"
  [[ -n "$ISSUER_ID" ]] || die "--issuer-id / ISSUER_ID required (Team key; OMIT only for INDIVIDUAL keys)"
fi

# ---- archive on demand ------------------------------------------------------
if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="./build/${SCHEME}.xcarchive"
  log "archiving scheme '$SCHEME' → $ARCHIVE_PATH"
  # App Sandbox + an increasing CFBundleVersion + Apple Distribution signing must already be set in the project.
  xcodebuild -scheme "$SCHEME" -configuration Release \
    -archivePath "$ARCHIVE_PATH" archive
fi
[[ -d "$ARCHIVE_PATH" ]] || die "xcarchive not found: $ARCHIVE_PATH"

# ---- 2. generate a minimal ExportOptions.plist if none supplied -------------
# method MUST be app-store-connect. NEVER write the deprecated 'app-store' value.
CLEANUP_PLIST=""
if [[ -z "$EXPORT_OPTIONS" ]]; then
  [[ -n "$TEAM_ID" ]] || die "--team-id required to generate an ExportOptions.plist (or pass --export-options)"
  EXPORT_OPTIONS="$(mktemp -t ExportOptions-AppStore.XXXXXX.plist)"
  CLEANUP_PLIST="$EXPORT_OPTIONS"
  log "generating ExportOptions.plist (method=app-store-connect, signingStyle=automatic) → $EXPORT_OPTIONS"
  cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
fi
[[ -f "$EXPORT_OPTIONS" ]] || die "ExportOptions.plist not found: $EXPORT_OPTIONS"
trap '[[ -n "$CLEANUP_PLIST" ]] && rm -f "$CLEANUP_PLIST"' EXIT

# ---- 3a. export the archive -------------------------------------------------
rm -rf "$EXPORT_PATH"
log "xcodebuild -exportArchive → $EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH"

# A store export produces a flat, installer-signed .pkg (Mac Installer Distribution cert).
PKG="$(/usr/bin/find "$EXPORT_PATH" -maxdepth 1 -name '*.pkg' | head -n1)"
[[ -n "$PKG" ]] || die "no .pkg in $EXPORT_PATH — a store export must yield a signed flat .pkg"
log "exported package: $PKG"

# ---- 3b. validate + upload via altool ---------------------------------------
# altool takes NO key path: it searches ./private_keys, ~/private_keys, ~/.private_keys,
# ~/.appstoreconnect/private_keys, and $API_PRIVATE_KEYS_DIR for a file named exactly
# AuthKey_<KEYID>.p8. We stage the supplied .p8 into ~/.appstoreconnect/private_keys so the
# search succeeds. (Same .p8 file-location handling as app-store-upload.sh.)
# NOTE: --upload-app is the ONLY store uploader (notarytool is NOT a store uploader);
#       altool --notarize-app was REMOVED in Xcode 27.
if [[ $DO_UPLOAD -eq 0 ]]; then
  log "--no-upload: export complete, skipping altool. Package: $PKG"
else
  STAGED_KEY=""
  if [[ -n "$P8_PATH" ]]; then
    [[ -f "$P8_PATH" ]] || die "p8 not found: $P8_PATH"
    KEYDIR="$HOME/.appstoreconnect/private_keys"
    mkdir -p "$KEYDIR"
    DEST="$KEYDIR/AuthKey_${KEY_ID}.p8"   # exact name altool greps for
    if [[ "$(cd "$(dirname "$P8_PATH")" && pwd)/$(basename "$P8_PATH")" != "$DEST" ]]; then
      cp "$P8_PATH" "$DEST"
      STAGED_KEY="$DEST"
    fi
    log "staged API key at $DEST"
  else
    log "no --p8 given; relying on altool's default private_keys search dirs for AuthKey_${KEY_ID}.p8"
  fi
  # Clean up only a key WE copied in; never delete a pre-existing one.
  trap '[[ -n "$STAGED_KEY" ]] && rm -f "$STAGED_KEY"; [[ -n "$CLEANUP_PLIST" ]] && rm -f "$CLEANUP_PLIST"' EXIT

  # --apiKey / --apiIssuer are camelCase. -t macos targets the Mac platform.
  log "altool --validate-app (macos)"
  xcrun altool --validate-app -f "$PKG" -t macos \
    --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

  log "altool --upload-app (macos)"
  xcrun altool --upload-app -f "$PKG" -t macos \
    --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

  log "upload accepted — App Store Connect is now processing the build (~5–30 min)."
fi

# ---- 4. reminders -----------------------------------------------------------
cat >&2 <<'EOF'

────────────────────────────────────────────────────────────────────────────
Mac App Store reminders:
  • App Sandbox is MANDATORY — com.apple.security.app-sandbox must be in the
    app's entitlements, or the build is rejected at upload/processing.
  • App signing cert  = "Apple Distribution"          (NOT Developer ID Application)
  • Installer cert    = "Mac Installer Distribution"  (NOT Developer ID Installer)
  • Notarization does NOT apply here — the store does App Review and re-signs.
  • FINAL STEP IS BROWSER-ONLY: "Submit for Review" has no first-party CLI.
    Do it in App Store Connect (or fastlane deliver / the ASC API). TestFlight
    internal testers get the build automatically once processing finishes.
────────────────────────────────────────────────────────────────────────────
EOF

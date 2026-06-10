#!/usr/bin/env bash
set -euo pipefail
#
# app-store-upload.sh
# Validate + upload an App-Store-signed flat .pkg to App Store Connect
# (TestFlight / Mac App Store) using an App Store Connect API key (.p8).
#
# NO notarytool here: notarytool is a NOTARIZER for Developer ID distribution,
# NOT a store uploader. Store binaries go through `xcrun altool` (validate then
# upload). NO interactive passwords anywhere — ASC API key auth only.
#
# Prerequisites (built earlier in the packaging pipeline, not by this script):
#   - App signing cert:       Apple Distribution        (NOT Developer ID Application)
#   - Installer signing cert: Mac Installer Distribution (NOT Developer ID Installer)
#   - App Sandbox is MANDATORY for the Mac App Store.
#   - Export with ExportOptions method = app-store-connect (the current key;
#     the old `app-store` value is deprecated), e.g.:
#       xcodebuild -exportArchive -archivePath X.xcarchive \
#         -exportOptionsPlist ExportOptions.plist -exportPath ./export
#
# Usage:
#   app-store-upload.sh -f App.pkg -k <KEY_ID> -i <ISSUER_ID> -p AuthKey.p8
#
# Env var equivalents (flags win over env):
#   PKG_PATH, KEY_ID, ISSUER_ID, P8_PATH

usage() {
  cat >&2 <<'EOF'
Usage: app-store-upload.sh -f <App.pkg> -k <KEY_ID> -i <ISSUER_ID> -p <AuthKey.p8>

  -f  Path to the App-Store-signed flat installer .pkg (or env PKG_PATH)
  -k  App Store Connect API Key ID                      (or env KEY_ID)
  -i  App Store Connect Issuer ID                        (or env ISSUER_ID)
  -p  Path to the AuthKey_<KEY_ID>.p8 private key file    (or env P8_PATH)
  -h  Show this help

All four values are required. Secrets are read from files/args only —
this script never prompts for or accepts an interactive password.

Caveat (--apiIssuer / --issuer): a TEAM-scoped key REQUIRES the Issuer ID.
An INDIVIDUAL-scoped key must OMIT the issuer (passing it returns HTTP 401).
This script targets TEAM keys (issuer required); for an Individual key, drop
the -i flag and remove --apiIssuer from the altool calls below.
EOF
}

# --- seed from env, then let flags override ---------------------------------
PKG_PATH="${PKG_PATH:-}"
KEY_ID="${KEY_ID:-}"
ISSUER_ID="${ISSUER_ID:-}"
P8_PATH="${P8_PATH:-}"

while getopts ":f:k:i:p:h" opt; do
  case "$opt" in
    f) PKG_PATH="$OPTARG" ;;
    k) KEY_ID="$OPTARG" ;;
    i) ISSUER_ID="$OPTARG" ;;
    p) P8_PATH="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "error: unknown flag -$OPTARG" >&2; usage; exit 2 ;;
    :)  echo "error: flag -$OPTARG requires an argument" >&2; usage; exit 2 ;;
  esac
done

# --- validate args ----------------------------------------------------------
missing=0
for pair in "PKG_PATH:.pkg path (-f)" "KEY_ID:KEY_ID (-k)" \
            "ISSUER_ID:ISSUER_ID (-i)" "P8_PATH:.p8 path (-p)"; do
  var="${pair%%:*}"; label="${pair#*:}"
  if [[ -z "${!var}" ]]; then
    echo "error: missing required ${label}" >&2
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then usage; exit 2; fi

[[ -f "$PKG_PATH" ]] || { echo "error: .pkg not found: $PKG_PATH" >&2; exit 2; }
[[ "$PKG_PATH" == *.pkg ]] || { echo "error: expected a flat .pkg installer: $PKG_PATH" >&2; exit 2; }
[[ -f "$P8_PATH" ]]  || { echo "error: .p8 key not found: $P8_PATH" >&2; exit 2; }

command -v xcrun >/dev/null || { echo "error: xcrun not on PATH (install Xcode/CLT)" >&2; exit 2; }

# --- altool .p8 file-location trap ------------------------------------------
# altool takes NO key-path argument by default. It searches, in order:
#   ./private_keys  ~/private_keys  ~/.private_keys  ~/.appstoreconnect/private_keys
#   and $API_PRIVATE_KEYS_DIR — for a file named EXACTLY AuthKey_<KEY_ID>.p8.
# We copy the provided key into ~/.appstoreconnect/private_keys/ under the
# required name so altool can find it. (Modern altool also accepts
# `--p8-file-path <path>`; we install to the canonical dir instead, which works
# across versions.)
KEY_DIR="${HOME}/.appstoreconnect/private_keys"
DEST_KEY="${KEY_DIR}/AuthKey_${KEY_ID}.p8"
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
if [[ "$(cd "$(dirname "$P8_PATH")" && pwd)/$(basename "$P8_PATH")" != "$DEST_KEY" ]]; then
  cp -f "$P8_PATH" "$DEST_KEY"
fi
chmod 600 "$DEST_KEY"
echo ">> Installed API key for altool: $DEST_KEY" >&2

# --- validate (must pass BEFORE we upload) ----------------------------------
# altool uses camelCase flags: --apiKey / --apiIssuer. -t macos selects platform.
echo ">> Validating $PKG_PATH against App Store Connect ..." >&2
if ! xcrun altool --validate-app \
      -f "$PKG_PATH" \
      -t macos \
      --apiKey "$KEY_ID" \
      --apiIssuer "$ISSUER_ID"; then
  echo "error: --validate-app failed; NOT uploading. Fix the issues above and retry." >&2
  exit 1
fi
echo ">> Validation passed." >&2

# --- upload -----------------------------------------------------------------
echo ">> Uploading $PKG_PATH to App Store Connect ..." >&2
xcrun altool --upload-app \
  -f "$PKG_PATH" \
  -t macos \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID"
echo ">> Upload complete." >&2

# --- next step (no CLI for this) --------------------------------------------
cat >&2 <<'EOF'

NOTE: The build is now uploaded and will appear in App Store Connect /
TestFlight after processing (minutes). "Submit for Review" is a SEPARATE step
with NO first-party CLI — do it in the App Store Connect web UI (or via the
public ASC REST API / fastlane deliver). altool only validates and uploads.
EOF

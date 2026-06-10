#!/usr/bin/env bash
set -euo pipefail
#
# notarize.sh — Developer ID: sign -> notarize -> staple -> verify
#
# Takes a built .app, signs it for Developer ID distribution, runs the full
# Apple notarization chain via notarytool, staples the ticket, and verifies.
# Optionally builds + signs a .dmg from the .app and notarizes/staples that too.
#
# Auth is ASC API key ONLY. No interactive passwords, no app-specific passwords.
# Either a stored notary keychain profile, or raw --key/--key-id/--issuer.
#
# Xcode 27 facts baked in:
#   - altool --notarize-app is REMOVED; notarytool is the only notarizer.
#   - notarytool accepts .dmg / .pkg / .zip only (NOT a raw .app).
#   - Staple the artifact you SHIP (.app/.dmg), NEVER the .zip you submitted.
#   - Use `ditto -c -k --keepParent` to zip (Finder "Compress" breaks signatures).
#   - Sign nested Mach-O inside-out, the bundle LAST; avoid `codesign --deep`.
#   - For a Team (Organization) ASC key, --issuer is required.
#     For an INDIVIDUAL ASC key, OMIT --issuer or notarytool 401s.

usage() {
  cat >&2 <<'EOF'
Usage:
  notarize.sh --app <App.app> --identity <"Developer ID Application: Name (TEAMID)"> \
              ( --keychain-profile <PROFILE> | --key <AuthKey.p8> --key-id <KEYID> [--issuer <ISSUER>] ) \
              [--make-dmg] [--entitlements <file.plist>]

Flags (or matching env vars):
  --app                APP                 Path to the built .app bundle (required)
  --identity           SIGN_IDENTITY       "Developer ID Application: ..." identity (required)
  --keychain-profile   NOTARY_PROFILE      Stored notarytool profile name (auth option A)
  --key                ASC_KEY             Path to ASC API .p8 key       (auth option B)
  --key-id             ASC_KEY_ID          ASC API Key ID                (auth option B)
  --issuer             ASC_ISSUER          ASC API Issuer ID (Team keys only; OMIT for Individual)
  --entitlements       ENTITLEMENTS        Optional entitlements plist for hardened runtime
  --make-dmg                               Also build + sign + notarize + staple a .dmg

Auth: provide EITHER --keychain-profile OR (--key + --key-id [+ --issuer]). Never both.
Create a profile once with:
  xcrun notarytool store-credentials "AC_NOTARY" --key <p8> --key-id <id> --issuer <iss>
EOF
  exit 2
}

APP="${APP:-}"; SIGN_IDENTITY="${SIGN_IDENTITY:-}"; NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ASC_KEY="${ASC_KEY:-}"; ASC_KEY_ID="${ASC_KEY_ID:-}"; ASC_ISSUER="${ASC_ISSUER:-}"
ENTITLEMENTS="${ENTITLEMENTS:-}"; MAKE_DMG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2;;
    --identity) SIGN_IDENTITY="$2"; shift 2;;
    --keychain-profile) NOTARY_PROFILE="$2"; shift 2;;
    --key) ASC_KEY="$2"; shift 2;;
    --key-id) ASC_KEY_ID="$2"; shift 2;;
    --issuer) ASC_ISSUER="$2"; shift 2;;
    --entitlements) ENTITLEMENTS="$2"; shift 2;;
    --make-dmg) MAKE_DMG=1; shift;;
    -h|--help) usage;;
    *) echo "ERROR: unknown argument: $1" >&2; usage;;
  esac
done

# --- validate inputs -------------------------------------------------------
[[ -n "$APP" ]] || { echo "ERROR: --app is required" >&2; usage; }
[[ -d "$APP" && "$APP" == *.app ]] || { echo "ERROR: --app must be an existing .app bundle: $APP" >&2; exit 1; }
[[ -n "$SIGN_IDENTITY" ]] || { echo "ERROR: --identity (Developer ID Application) is required" >&2; usage; }

# Exactly one auth mode. Build the notarytool auth args array.
NOTARY_AUTH=()
if [[ -n "$NOTARY_PROFILE" ]]; then
  [[ -z "$ASC_KEY$ASC_KEY_ID$ASC_ISSUER" ]] || { echo "ERROR: use EITHER --keychain-profile OR --key/--key-id/--issuer, not both" >&2; exit 1; }
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "$ASC_KEY" && -n "$ASC_KEY_ID" ]]; then
  [[ -f "$ASC_KEY" ]] || { echo "ERROR: --key file not found: $ASC_KEY" >&2; exit 1; }
  NOTARY_AUTH=(--key "$ASC_KEY" --key-id "$ASC_KEY_ID")
  # Team key -> --issuer required; Individual key -> OMIT --issuer (else 401).
  [[ -n "$ASC_ISSUER" ]] && NOTARY_AUTH+=(--issuer "$ASC_ISSUER")
else
  echo "ERROR: no auth provided. Need --keychain-profile OR --key + --key-id." >&2; usage
fi

ENT_ARGS=()
[[ -n "$ENTITLEMENTS" ]] && { [[ -f "$ENTITLEMENTS" ]] || { echo "ERROR: entitlements not found: $ENTITLEMENTS" >&2; exit 1; }; ENT_ARGS=(--entitlements "$ENTITLEMENTS"); }

echo ">> Notarizing: $APP" >&2
echo ">> Identity:   $SIGN_IDENTITY" >&2

# --- 1. strip quarantine ---------------------------------------------------
echo ">> [1/6] Stripping quarantine xattrs (xattr -cr)" >&2
xattr -cr "$APP"

# --- 2. sign nested Mach-O inside-out, then the bundle LAST -----------------
# Hardened runtime (--options runtime) + secure timestamp (--timestamp) are
# both MANDATORY for notarization. We deliberately avoid `--deep` (unreliable,
# Apple-deprecated): we sign inner binaries first, the .app wrapper last.
echo ">> [2/6] Signing nested Mach-O inside-out, bundle last" >&2
while IFS= read -r -d '' inner; do
  case "$inner" in "$APP") continue;; esac   # bundle itself signed last
  echo "   sign: $inner" >&2
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "${ENT_ARGS[@]}" "$inner"
done < <(find "$APP/Contents" \( -name '*.dylib' -o -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.bundle' \) -print0)

echo "   sign (bundle last): $APP" >&2
codesign --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" "${ENT_ARGS[@]}" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

# --- 3. zip with ditto + notarytool submit --wait --------------------------
ZIP="${APP%.app}.zip"
echo ">> [3/6] ditto -c -k --keepParent -> $ZIP (NOT a Finder zip)" >&2
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

submit_and_wait() {  # $1 = artifact to submit (.zip/.dmg/.pkg)
  local artifact="$1" out rc sid status
  echo ">> notarytool submit $artifact --wait" >&2
  out="$(xcrun notarytool submit "$artifact" "${NOTARY_AUTH[@]}" --wait --no-progress 2>&1)" && rc=0 || rc=$?
  echo "$out" >&2
  sid="$(printf '%s\n' "$out" | awk '/[Ii]d:/{print $2; exit}')"
  status="$(printf '%s\n' "$out" | awk -F': *' '/status:/{print $2; exit}')"
  if [[ "$status" != "Accepted" || $rc -ne 0 ]]; then
    # On Invalid (or any non-Accepted), pull the detailed log and fail loudly.
    if [[ -n "$sid" ]]; then
      local log="${artifact%.*}.notary-log.json"
      echo ">> Notarization NOT accepted (status=$status). Fetching log -> $log" >&2
      xcrun notarytool log "$sid" "${NOTARY_AUTH[@]}" "$log" >&2 || true
      echo "ERROR: notarization failed. See log: $log" >&2
    else
      echo "ERROR: notarization failed and no submission id was returned." >&2
    fi
    exit 1
  fi
  echo ">> Accepted (submission $sid)" >&2
}

echo ">> [4/6] Submitting for notarization" >&2
submit_and_wait "$ZIP"

# --- 4. staple the SHIPPED artifact (the .app), then verify ----------------
# Staple the .app — never the .zip (the .zip was only a transport for submit).
echo ">> [5/6] Stapling ticket to $APP" >&2
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo ">> [6/6] Verifying signature + Gatekeeper assessment" >&2
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t install "$APP"
rm -f "$ZIP"   # transport artifact no longer needed
echo ">> .app DONE: signed, notarized, stapled, verified." >&2

# --- optional: build + sign + notarize + staple a .dmg ---------------------
if [[ "$MAKE_DMG" -eq 1 ]]; then
  DMG="${APP%.app}.dmg"
  echo ">> [dmg] Building $DMG via hdiutil" >&2
  rm -f "$DMG"
  hdiutil create -volname "$(basename "${APP%.app}")" -srcfolder "$APP" -ov -format UDZO "$DMG"
  echo ">> [dmg] Signing $DMG (Developer ID Application, hardened runtime + timestamp)" >&2
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  echo ">> [dmg] Notarizing $DMG (notarytool accepts .dmg directly)" >&2
  submit_and_wait "$DMG"
  echo ">> [dmg] Stapling + verifying $DMG" >&2
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  codesign --verify --deep --strict --verbose=2 "$DMG"
  spctl -a -vvv -t install "$DMG"
  echo ">> .dmg DONE: $DMG" >&2
fi

echo ">> All artifacts shipped." >&2

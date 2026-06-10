#!/usr/bin/env bash
#
# build-and-run.sh — build and (optionally) run a native macOS AppKit app.
#
# One command to generate + build + launch:  ./build-and-run.sh
#
# - Verifies Xcode is selected and its license is accepted
# - Runs `tuist generate` if a Project.swift exists and the generated project is missing/stale
#   (running `tuist install` first if a Tuist/Package.swift declares external dependencies)
# - Auto-detects the scheme and host architecture (arm64/x86_64), defaults to Debug
# - Builds into a predictable ./build DerivedData path
# - Finds the built .app from `xcodebuild -showBuildSettings`
# - Launches it with `open` (returns immediately, app runs detached)
#
# Examples:
#   ./build-and-run.sh                          # generate (if needed), build, launch with `open`
#   ./build-and-run.sh --scheme MyApp           # explicit scheme
#   ./build-and-run.sh --logs                   # run the inner binary streaming stdout/stderr (use in background)
#   ./build-and-run.sh --skip-run               # build only
#   ./build-and-run.sh --configuration Release  # override Debug
#
set -euo pipefail

SCHEME=""
CONFIGURATION="Debug"
SKIP_RUN=0
LOGS=0
DERIVED="./build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme)        SCHEME="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --skip-run)      SKIP_RUN=1; shift ;;
    --logs)          LOGS=1; shift ;;
    -h|--help)       grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
gray()   { printf '\033[90m%s\033[0m\n' "$*"; }

# -- 0. Verify Xcode is selected and licensed --------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  red "ERROR: No Xcode selected."
  red  "Run: sudo xcode-select -s /Applications/Xcode.app   (then accept the license)"
  red  "Or run the /appkit-setup skill."
  exit 1
fi
if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  red "ERROR: xcodebuild not usable — the Xcode license may not be accepted."
  red  "Run: sudo xcodebuild -license accept"
  exit 1
fi

# -- 1. Generate the Xcode project from Project.swift if needed --------------
PROJ=$(ls -1d ./*.xcworkspace ./*.xcodeproj 2>/dev/null | head -1 || true)
if [[ -f Project.swift ]]; then
  REGEN=0
  if [[ -z "$PROJ" ]]; then
    REGEN=1
  elif [[ Project.swift -nt "$PROJ" ]]; then
    REGEN=1
  fi
  if [[ "$REGEN" == "1" ]]; then
    if ! command -v tuist >/dev/null 2>&1; then
      red "ERROR: Project.swift found but tuist is not installed."
      red  "Run: brew install tuist   (or the /appkit-setup skill)"
      exit 1
    fi
    # Resolve external Swift Package dependencies first, if any are declared.
    if [[ -f Tuist/Package.swift ]]; then
      cyan "--> Resolving dependencies (tuist install)"
      tuist install
    fi
    cyan "--> Generating Xcode project from Project.swift (tuist generate)"
    tuist generate --no-open    # --no-open: don't launch Xcode; we build headless with xcodebuild
    PROJ=$(ls -1d ./*.xcworkspace ./*.xcodeproj 2>/dev/null | head -1 || true)
  fi
fi

if [[ -z "$PROJ" ]]; then
  red "ERROR: No .xcodeproj / .xcworkspace found and no Project.swift to generate one from."
  red  "Create a Project.swift (see this skill's templates/Project.swift) or open an existing project."
  exit 1
fi

# -- 2. Pick the xcodebuild container flag (-workspace vs -project) -----------
if [[ "$PROJ" == *.xcworkspace ]]; then
  CONTAINER=(-workspace "$PROJ")
else
  CONTAINER=(-project "$PROJ")
fi

# -- 3. Resolve the scheme ---------------------------------------------------
if [[ -z "$SCHEME" ]]; then
  # Parse the JSON list of schemes; pick the first if unambiguous.
  SCHEMES=$(xcodebuild "${CONTAINER[@]}" -list -json 2>/dev/null \
            | /usr/bin/python3 -c 'import sys,json; print("\n".join(json.load(sys.stdin).get("project",json.load(sys.stdin) if False else {}).get("schemes",[])))' 2>/dev/null || true)
  if [[ -z "$SCHEMES" ]]; then
    # Fallback: plain text parse
    SCHEMES=$(xcodebuild "${CONTAINER[@]}" -list 2>/dev/null | awk '/Schemes:/{f=1;next} f&&NF{gsub(/^ +/,"");print}')
  fi
  COUNT=$(printf '%s\n' "$SCHEMES" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ "$COUNT" == "1" ]]; then
    SCHEME=$(printf '%s\n' "$SCHEMES" | sed '/^$/d' | head -1)
  elif [[ "$COUNT" -gt 1 ]]; then
    # Prefer a scheme that is not a *Tests target
    SCHEME=$(printf '%s\n' "$SCHEMES" | sed '/^$/d' | grep -vi 'test' | head -1)
    [[ -z "$SCHEME" ]] && SCHEME=$(printf '%s\n' "$SCHEMES" | sed '/^$/d' | head -1)
    gray "--> Multiple schemes found; using '$SCHEME'. Override with --scheme."
  else
    red "ERROR: Could not determine a scheme. Pass one with --scheme <name>."
    exit 1
  fi
fi

# -- 4. Detect host architecture ---------------------------------------------
ARCH=$(uname -m)   # arm64 or x86_64

# -- 5. Build ----------------------------------------------------------------
echo ""
cyan "--> Building scheme '$SCHEME' ($CONFIGURATION, arch=$ARCH)"
gray "--> $PROJ"
set +e
xcodebuild "${CONTAINER[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$ARCH" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build
BUILD_EXIT=$?
set -e

if [[ $BUILD_EXIT -ne 0 ]]; then
  echo ""
  red "BUILD FAILED (exit code $BUILD_EXIT)"
  exit $BUILD_EXIT
fi
echo ""
green "BUILD SUCCEEDED"

# -- 6. Locate the built .app ------------------------------------------------
SETTINGS=$(xcodebuild "${CONTAINER[@]}" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
            -destination "platform=macOS,arch=$ARCH" -derivedDataPath "$DERIVED" \
            -showBuildSettings 2>/dev/null)
PRODUCTS_DIR=$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
PRODUCT_NAME=$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME =/{print $2; exit}')
APP_PATH="$PRODUCTS_DIR/$PRODUCT_NAME"

if [[ -z "$PRODUCTS_DIR" || ! -d "$APP_PATH" ]]; then
  red "WARNING: Could not locate the built .app (looked at: $APP_PATH). Skipping run."
  exit 0
fi
gray "--> App: $APP_PATH"

# -- 7. Run ------------------------------------------------------------------
if [[ $SKIP_RUN -eq 1 ]]; then
  gray "--> Skipping run (--skip-run)"
  exit 0
fi

BIN="$APP_PATH/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist" 2>/dev/null || basename "$PRODUCT_NAME" .app)"

if [[ $LOGS -eq 1 && -x "$BIN" ]]; then
  echo ""
  cyan "--> Launching inner binary (streaming stdout/stderr): $BIN"
  gray "    Run this in the background so it doesn't block your turn."
  gray "    Crashes and exceptions appear below."
  echo ""
  exec "$BIN"
else
  echo ""
  cyan "--> Launching: open \"$APP_PATH\""
  open "$APP_PATH"
  green "App launched. (Use --logs to stream stdout/stderr; check ~/Library/Logs/DiagnosticReports for crashes.)"
fi

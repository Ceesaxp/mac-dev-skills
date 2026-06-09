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
"$BIN_DIR/appkit-api" --help >/dev/null || { echo "ERROR: appkit-api smoke test failed (missing/unsigned/wrong-arch binary?)" >&2; exit 1; }
echo "appkit-api: smoke OK"

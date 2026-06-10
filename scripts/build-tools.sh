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
  local release_dir="$REPO_ROOT/src/tools/$name/.build/release"
  local built="$release_dir/$name"
  echo "==> Ad-hoc signing $name"
  codesign --force --sign - "$built"
  echo "==> Installing $name -> $BIN_DIR and $dest_skill"
  install_binary "$built" "$release_dir" "$BIN_DIR" "$name"
  if [ -n "$dest_skill" ]; then
    mkdir -p "$REPO_ROOT/$dest_skill"
    install_binary "$built" "$release_dir" "$REPO_ROOT/$dest_skill" "$name"
  fi
}

# Copy the executable plus any SwiftPM resource bundles that sit next to it in
# the release dir. `Bundle.module` resolves bundles relative to the executable,
# so a binary copied without its `*.bundle` siblings fatal-errors at runtime
# (appkit-search embeds its corpus this way).
install_binary() {
  local built="$1" release_dir="$2" dest_dir="$3" name="$4"
  cp "$built" "$dest_dir/$name"
  local bundle
  for bundle in "$release_dir"/*.bundle; do
    [ -e "$bundle" ] || continue
    rm -rf "$dest_dir/$(basename "$bundle")"
    cp -R "$bundle" "$dest_dir/"
  done
}

build_tool "appkit-api" "plugins/appkit/skills/appkit-design"
build_tool "appkit-search" "plugins/appkit/skills/appkit-design"

echo "Done. Tools in $BIN_DIR (and copied into skill dirs)."
"$BIN_DIR/appkit-api" --help >/dev/null || { echo "ERROR: appkit-api smoke test failed (missing/unsigned/wrong-arch binary?)" >&2; exit 1; }
echo "appkit-api: smoke OK"
# Exercise the corpus, not just --help: this loads the embedded resource bundle,
# so it catches a binary installed without its `*.bundle` sibling.
"$BIN_DIR/appkit-search" list >/dev/null || { echo "ERROR: appkit-search smoke test failed (missing resource bundle / unsigned / wrong-arch binary?)" >&2; exit 1; }
echo "appkit-search: smoke OK"

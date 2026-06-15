#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/generate-apple-platform-tools-contracts.sh [--check] [--source PATH]

Regenerate the generated apple-platform-tools CLI contract references inside the
appkit skills. The source checkout must be apple-platform-tools.

Options:
  --check        fail if generated references drift from the source checkout
  --source PATH apple-platform-tools checkout (default: $APPLE_PLATFORM_TOOLS_ROOT or ../../../Projects/apple-platform-tools)
EOF
}

mode="write"
source_root="${APPLE_PLATFORM_TOOLS_ROOT:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --source)
      source_root="${2:-}"
      if [[ -z "$source_root" ]]; then
        echo "--source requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
if [[ -z "$source_root" ]]; then
  source_root="$(cd "$repo_root/../../../Projects/apple-platform-tools" 2>/dev/null && pwd || true)"
fi
if [[ -z "$source_root" || ! -x "$source_root/scripts/generate-mac-dev-skills-contracts.sh" ]]; then
  cat >&2 <<EOF
apple-platform-tools source checkout not found, or it lacks the export generator.

Set APPLE_PLATFORM_TOOLS_ROOT or pass --source:
  APPLE_PLATFORM_TOOLS_ROOT=/path/to/apple-platform-tools scripts/generate-apple-platform-tools-contracts.sh
EOF
  exit 1
fi

generated_dir="$repo_root/plugins/appkit/skills"

copy_exports_from() {
  local export_root="$1"
  for rel in \
    appkit-design/references/apple-platform-tools-contracts.md \
    appkit-app-inspector/references/cli-contract.md \
    appkit-app-inspector/references/doctor-and-dev-box.md \
    appkit-app-inspector/references/failure-signatures.md \
    appkit-app-inspector/references/filter-drill-and-selectors.md \
    appkit-private-apis/references/header-dumper.md \
    appkit-private-apis/references/redump.md
  do
    if [[ ! -f "$export_root/$rel" ]]; then
      echo "missing generated export: $rel" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$generated_dir/$rel")"
    cp "$export_root/$rel" "$generated_dir/$rel"
  done
}

generate_to_repo() {
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  "$source_root/scripts/generate-mac-dev-skills-contracts.sh" --out "$tmp/mac-dev-skills"
  copy_exports_from "$tmp/mac-dev-skills"
}

if [[ "$mode" == "check" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  "$source_root/scripts/generate-mac-dev-skills-contracts.sh" --out "$tmp/export"
  current="$tmp/current"
  mkdir -p "$current"
  for rel in \
    appkit-design/references/apple-platform-tools-contracts.md \
    appkit-app-inspector/references/cli-contract.md \
    appkit-app-inspector/references/doctor-and-dev-box.md \
    appkit-app-inspector/references/failure-signatures.md \
    appkit-app-inspector/references/filter-drill-and-selectors.md \
    appkit-private-apis/references/header-dumper.md \
    appkit-private-apis/references/redump.md
  do
    mkdir -p "$(dirname "$current/$rel")"
    if [[ -f "$generated_dir/$rel" ]]; then
      cp "$generated_dir/$rel" "$current/$rel"
    fi
  done
  if ! diff -qr "$current" "$tmp/export"; then
    cat >&2 <<EOF

apple-platform-tools contract references drifted.
Run:
  APPLE_PLATFORM_TOOLS_ROOT=$source_root scripts/generate-apple-platform-tools-contracts.sh
EOF
    exit 1
  fi
else
  generate_to_repo
fi

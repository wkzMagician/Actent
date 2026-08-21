#!/usr/bin/env bash
set -euo pipefail

mode="${1:-${DARTLOOM_BUILD_MODE:-release}}"
case "$mode" in
  debug|profile|release) ;;
  *)
    echo "Unsupported Flutter build mode: $mode" >&2
    exit 64
    ;;
esac

case "$mode" in
  debug) configuration="Debug" ;;
  profile) configuration="Profile" ;;
  release) configuration="Release" ;;
esac
targets="${DARTLOOM_NATIVE_TARGETS:-}"
if [[ -z "$targets" ]]; then
  exit 0
fi

while IFS= read -r target; do
  [[ -z "$target" ]] && continue
  xcodebuild \
    -project ios/Runner.xcodeproj \
    -target "$target" \
    -configuration "$configuration" \
    -sdk iphoneos \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
done <<< "$targets"
